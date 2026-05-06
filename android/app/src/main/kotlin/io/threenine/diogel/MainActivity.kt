package io.threenine.diogel

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.security.MessageDigest
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    private val TAG = "Diogel-MainActivity"
    private enum class CompletionAction { NONE, FINISH, BACKGROUND }

    companion object {
        private val appLabelCache = ConcurrentHashMap<String, String>()
        private val certificateCache = ConcurrentHashMap<String, String>()
        @Volatile private var currentActivity: WeakReference<MainActivity>? = null

        fun deliverNip55BridgeIntent(intent: Intent): Boolean {
            val activity = currentActivity?.get() ?: return false
            return activity.deliverNip55IntentFromBridge(intent)
        }
    }

    private val channelName = "io.threenine.diogel/nip55"
    private var channel: MethodChannel? = null
    private var initialNip55Intent: Map<String, Any?>? = null
    private var latestNip55Intent: Map<String, Any?>? = null
    private var activeRequestToken: String? = null
    private var lastDeliveredToken: String? = null
    private var nextRequestNumber = 0L
    private var pendingCompletionRunnable: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "onCreate: intent=$intent")
        currentActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
        initialNip55Intent = parseNip55Intent(intent)
        activeRequestToken = initialNip55Intent?.get("requestToken") as? String
        Log.d(TAG, "onCreate: initialNip55Intent=$initialNip55Intent, activeRequestToken=$activeRequestToken")
        
        // Asynchronously resolve app label and certificate if they are missing
        initialNip55Intent?.let { resolveMetadataAsync(it) { updated -> initialNip55Intent = updated } }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.d(TAG, "configureFlutterEngine")
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.let { Nip55ProviderBridge.attach(it) }
        channel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "onMethodCall: ${call.method}")
            when (call.method) {
                "getInitialNip55Intent" -> {
                    val payload = initialNip55Intent
                    initialNip55Intent = null
                    result.success(payload)
                }
                "consumeLatestNip55Intent" -> {
                    val payload = latestNip55Intent
                    latestNip55Intent = null
                    result.success(payload)
                }
                "completeNip55Intent" -> {
                    val action = completeNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
                    runAfterMethodResponse(action)
                }
                "rejectNip55Intent" -> {
                    val action = rejectNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
                    runAfterMethodResponse(action)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (currentActivity?.get() == this) {
            currentActivity = null
        }
        Nip55ProviderBridge.detach(channel)
        super.onDestroy()
    }

    override fun onResume() {
        currentActivity = WeakReference(this)
        super.onResume()
    }

    override fun onNewIntent(intent: Intent) {
        Log.d(TAG, "onNewIntent: intent=$intent")
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = parseNip55Intent(intent)
        if (payload != null) deliverNip55Payload(payload)
    }

    private fun deliverNip55IntentFromBridge(intent: Intent): Boolean {
        val payload = parseNip55Intent(intent) ?: return false
        return deliverNip55Payload(payload)
    }

    private fun deliverNip55Payload(payload: Map<String, Any?>): Boolean {
        if (channel == null) return false
        val requestToken = payload["requestToken"] as? String

        if (requestToken != null && requestToken == lastDeliveredToken) {
            Log.d(TAG, "deliverNip55Payload: Token $requestToken already delivered, ignoring")
            return true
        }

        if (activeRequestToken != null) {
            Log.d(TAG, "deliverNip55Payload: Already have active request ($activeRequestToken), rejecting new one ($requestToken)")
            if (requestToken != null) {
                lastDeliveredToken = requestToken
                Nip55BridgeRegistry.reject(
                    requestToken,
                    "Diogel is already reviewing another NIP-55 request"
                )
            }
            return true
        }
        activeRequestToken = requestToken
        lastDeliveredToken = requestToken
        latestNip55Intent = payload

        // Asynchronously resolve metadata before sending to Dart.
        resolveMetadataAsync(payload) { updated ->
            latestNip55Intent = updated
            Log.d(TAG, "deliverNip55Payload: Sending onNip55Intent to Dart")
            runOnUiThread {
                channel?.invokeMethod("onNip55Intent", updated)
            }
        }
        return true
    }

    private fun parseNip55Intent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val data = intent.data
        
        // If it's a handoff from Nip55BridgeActivity, it might not have the VIEW action or data set on the intent itself,
        // but it will have the requestToken and either parsed extras or dataUri.
        val hasNip55Extras = intent.hasExtra("requestToken") && intent.hasExtra("type")
        
        if (intent.action != Intent.ACTION_VIEW || data?.scheme != "nostrsigner") {
            if (!hasNip55Extras) return null
        }

        val token = intent.getStringExtra("requestToken")
            ?: if (data != null && data.scheme == "nostrsigner") {
                 "nip55-${System.currentTimeMillis()}-${nextRequestNumber++}"
               } else {
                 return null
               }
        
        val callerPackage = intent.getStringExtra("callingPackage") ?: callingPackage ?: intent.`package`
        
        val parsedTypeExtra = intent.getStringExtra("type")
        val parsedType = parsedTypeExtra
            ?: (data?.let { Nip55UriParser.queryParameter(it, "type") })
        if (parsedType == null) return null

        val shouldUseControlQueryForContent = parsedTypeExtra == null || parsedType == "nip04_decrypt"
        val parsedContent = intent.getStringExtra("content")
            ?: (data?.let { Nip55UriParser.content(it, parsedType, shouldUseControlQueryForContent) })

        return mapOf(
            "requestToken" to token,
            "type" to parsedType,
            "content" to parsedContent,
            "id" to (intent.getStringExtra("id") ?: (data?.let { Nip55UriParser.queryParameter(it, "id") })),
            "currentUser" to (intent.getStringExtra("currentUser") ?: intent.getStringExtra("current_user") ?: (data?.let { Nip55UriParser.queryParameter(it, "current_user") })),
            "pubkey" to (intent.getStringExtra("pubkey") ?: intent.getStringExtra("pubKey") ?: (data?.let { Nip55UriParser.queryParameter(it, "pubkey") })),
            "permissions" to (intent.getStringExtra("permissions") ?: (data?.let { Nip55UriParser.queryParameter(it, "permissions") })),
            "callbackUrl" to (intent.getStringExtra("callbackUrl") ?: (data?.let { Nip55UriParser.queryParameter(it, "callbackUrl") })),
            "returnType" to (intent.getStringExtra("returnType") ?: (data?.let { Nip55UriParser.queryParameter(it, "returnType") })),
            "compressionType" to (intent.getStringExtra("compressionType") ?: (data?.let { Nip55UriParser.queryParameter(it, "compressionType") })),
            "isBrowserFlow" to intent.getBooleanExtra("isBrowserFlow", false),
            "callingPackage" to callerPackage,
            "callerAppLabel" to intent.getStringExtra("callerAppLabel"),
            "callerCertificateSha256" to intent.getStringExtra("callerCertificateSha256"),
            "referrer" to (intent.getStringExtra("referrer") ?: referrer?.toString()),
            "intentPackage" to (intent.getStringExtra("intentPackage") ?: intent.`package`),
            "sourceHint" to (intent.getStringExtra("sourceHint") ?: callerPackage ?: referrer?.host),
            "bridgeToken" to intent.getStringExtra("requestToken"),
            "dataUri" to (intent.getStringExtra("dataUri") ?: data?.toString())
        )
    }

    private fun resolveMetadataAsync(payload: Map<String, Any?>, callback: (Map<String, Any?>) -> Unit) {
        val callerPackage = payload["callingPackage"] as? String
        if (callerPackage.isNullOrBlank()) {
            callback(payload)
            return
        }

        val hasLabel = payload["callerAppLabel"] != null
        val hasCert = payload["callerCertificateSha256"] != null
        if (hasLabel && hasCert) {
            callback(payload)
            return
        }

        backgroundExecutor.execute {
            val updated = payload.toMutableMap()
            if (!hasLabel) {
                updated["callerAppLabel"] = resolveAppLabel(callerPackage)
            }
            if (!hasCert) {
                updated["callerCertificateSha256"] = resolveSigningCertificateSha256(callerPackage)
            }
            callback(updated)
        }
    }

    private fun resolveAppLabel(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        appLabelCache[packageName]?.let { return it }
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            val label = packageManager.getApplicationLabel(appInfo).toString()
            appLabelCache[packageName] = label
            label
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveSigningCertificateSha256(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        certificateCache[packageName]?.let { return it }
        return try {
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                info.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                info.signatures
            }
            val signature = signatures?.firstOrNull() ?: return null
            val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            val cert = digest.joinToString(":") { byte -> "%02X".format(byte) }
            certificateCache[packageName] = cert
            cert
        } catch (_: Exception) {
            null
        }
    }

    private fun completeNip55Intent(arguments: Map<*, *>?): CompletionAction {
        if (!isActiveRequest(arguments)) return CompletionAction.NONE
        val extras = arguments?.get("extras") as? Map<*, *> ?: emptyMap<Any, Any>()
        maybeLaunchCallback(extras)
        maybeCopyToClipboard(extras)
        val bridgeToken = activeRequestToken
        if (bridgeToken != null && Nip55BridgeRegistry.complete(bridgeToken, extras)) {
            activeRequestToken = null
            return CompletionAction.BACKGROUND
        }
        val resultIntent = Intent()
        extras.forEach { (key, value) ->
            if (key is String && value != null) {
                resultIntent.putExtra(key, value.toString())
            }
        }
        setResult(Activity.RESULT_OK, resultIntent)
        activeRequestToken = null
        return CompletionAction.FINISH
    }

    private fun maybeLaunchCallback(extras: Map<*, *>) {
        val callbackUrl = extras["callbackUrl"] as? String ?: return
        val result = extras["result"]?.toString() ?: return
        try {
            val callbackUri = buildCallbackUri(callbackUrl, result, extras)
            startActivity(Intent(Intent.ACTION_VIEW, callbackUri))
        } catch (_: Exception) {
            // Keep the normal result path as fallback.
        }
    }

    private fun buildCallbackUri(callbackUrl: String, result: String, extras: Map<*, *>): Uri {
        val uri = Uri.parse(callbackUrl)
        if (callbackUrl.endsWith("=")) {
            return Uri.parse(callbackUrl + Uri.encode(result))
        }
        val uriBuilder = uri.buildUpon()
            .appendQueryParameter("result", result)
        extras["id"]?.toString()?.let { uriBuilder.appendQueryParameter("id", it) }
        extras["returnType"]?.toString()?.let { uriBuilder.appendQueryParameter("returnType", it) }
        extras["compressionType"]?.toString()?.let { uriBuilder.appendQueryParameter("compressionType", it) }
        return uriBuilder.build()
    }

    private fun maybeCopyToClipboard(extras: Map<*, *>) {
        if (extras["copyToClipboard"] != true) return
        val result = extras["result"]?.toString() ?: return
        val label = extras["clipboardLabel"]?.toString() ?: "NIP-55 result"
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.setPrimaryClip(ClipData.newPlainText(label, result))
    }

    private fun rejectNip55Intent(arguments: Map<*, *>?): CompletionAction {
        if (!isActiveRequest(arguments)) return CompletionAction.NONE
        val bridgeToken = activeRequestToken
        val error = arguments?.get("error") as? String
        if (bridgeToken != null && Nip55BridgeRegistry.reject(bridgeToken, error)) {
            activeRequestToken = null
            return CompletionAction.BACKGROUND
        }
        val resultIntent = Intent()
        if (!error.isNullOrBlank()) {
            resultIntent.putExtra("error", error)
        }
        setResult(Activity.RESULT_CANCELED, resultIntent)
        activeRequestToken = null
        return CompletionAction.FINISH
    }

    private fun runAfterMethodResponse(action: CompletionAction) {
        Log.d(TAG, "runAfterMethodResponse: action=$action")
        if (action == CompletionAction.NONE) return

        // Cancel any existing pending completion to avoid finishing/backgrounding
        // if a second request arrived during the grace period of the first.
        pendingCompletionRunnable?.let { mainHandler.removeCallbacks(it) }

        val runnable = Runnable {
            pendingCompletionRunnable = null

            // Double check that no new request has become active during the delay.
            if (activeRequestToken != null) {
                Log.d(TAG, "runAfterMethodResponse: Skipping $action because a new request is active")
                return@Runnable
            }

            Log.d(TAG, "Executing completion action: $action")
            when (action) {
                CompletionAction.BACKGROUND -> moveTaskToBack(true)
                CompletionAction.FINISH -> finish()
                CompletionAction.NONE -> Unit
            }
        }
        pendingCompletionRunnable = runnable

        // Give Flutter and plugins a short grace period to deliver MethodChannel
        // responses before we background/finish the activity for the caller handoff.
        mainHandler.postDelayed(runnable, 150L)
    }

    private fun isActiveRequest(arguments: Map<*, *>?): Boolean {
        val requestedToken = arguments?.get("requestToken") as? String
        val activeToken = activeRequestToken
        return activeToken != null && requestedToken == activeToken
    }
}
