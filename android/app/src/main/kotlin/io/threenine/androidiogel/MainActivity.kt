package io.threenine.androidiogel

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private enum class CompletionAction { NONE, FINISH, BACKGROUND }

    private val channelName = "io.threenine.androidiogel/nip55"
    private var channel: MethodChannel? = null
    private var initialNip55Intent: Map<String, Any?>? = null
    private var latestNip55Intent: Map<String, Any?>? = null
    private var activeRequestToken: String? = null
    private var nextRequestNumber = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialNip55Intent = parseNip55Intent(intent)
        activeRequestToken = initialNip55Intent?.get("requestToken") as? String
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = parseNip55Intent(intent)
        if (payload != null) {
            if (activeRequestToken != null) {
                val requestToken = payload["requestToken"] as? String
                if (requestToken != null) {
                    Nip55BridgeRegistry.reject(
                        requestToken,
                        "Diogel is already reviewing another NIP-55 request"
                    )
                }
                return
            }
            activeRequestToken = payload["requestToken"] as? String
            latestNip55Intent = payload
            channel?.invokeMethod("onNip55Intent", payload)
        }
    }

    private fun parseNip55Intent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        if (data.scheme != "nostrsigner") return null

        val token = intent.getStringExtra("requestToken")
            ?: "nip55-${System.currentTimeMillis()}-${nextRequestNumber++}"
        val callerPackage = intent.getStringExtra("callingPackage") ?: callingPackage ?: intent.`package`
        return mapOf(
            "requestToken" to token,
            "type" to (intent.getStringExtra("type") ?: Nip55UriParser.queryParameter(data, "type")),
            "content" to Nip55UriParser.content(data),
            "id" to (intent.getStringExtra("id") ?: Nip55UriParser.queryParameter(data, "id")),
            "currentUser" to (intent.getStringExtra("current_user") ?: Nip55UriParser.queryParameter(data, "current_user")),
            "pubkey" to (intent.getStringExtra("pubkey") ?: Nip55UriParser.queryParameter(data, "pubkey")),
            "permissions" to (intent.getStringExtra("permissions") ?: Nip55UriParser.queryParameter(data, "permissions")),
            "callbackUrl" to Nip55UriParser.queryParameter(data, "callbackUrl"),
            "returnType" to Nip55UriParser.queryParameter(data, "returnType"),
            "compressionType" to Nip55UriParser.queryParameter(data, "compressionType"),
            "callingPackage" to callerPackage,
            "callerAppLabel" to (intent.getStringExtra("callerAppLabel") ?: resolveAppLabel(callerPackage)),
            "callerCertificateSha256" to (
                intent.getStringExtra("callerCertificateSha256")
                    ?: resolveSigningCertificateSha256(callerPackage)
                ),
            "referrer" to (intent.getStringExtra("referrer") ?: referrer?.toString()),
            "intentPackage" to (intent.getStringExtra("intentPackage") ?: intent.`package`),
            "sourceHint" to (intent.getStringExtra("sourceHint") ?: callerPackage ?: referrer?.host),
            "bridgeToken" to intent.getStringExtra("requestToken"),
            "dataUri" to data.toString()
        )
    }

    private fun resolveAppLabel(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveSigningCertificateSha256(packageName: String?): String? {
        if (packageName.isNullOrBlank()) return null
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
            digest.joinToString(":") { byte -> "%02X".format(byte) }
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
            val uriBuilder = Uri.parse(callbackUrl).buildUpon()
                .appendQueryParameter("result", result)
            extras["id"]?.toString()?.let { uriBuilder.appendQueryParameter("id", it) }
            extras["returnType"]?.toString()?.let { uriBuilder.appendQueryParameter("returnType", it) }
            extras["compressionType"]?.toString()?.let { uriBuilder.appendQueryParameter("compressionType", it) }
            startActivity(Intent(Intent.ACTION_VIEW, uriBuilder.build()))
        } catch (_: Exception) {
            // Keep the normal result path as fallback.
        }
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
        if (action == CompletionAction.NONE) return
        val runnable = Runnable {
            when (action) {
                CompletionAction.BACKGROUND -> moveTaskToBack(true)
                CompletionAction.FINISH -> finish()
                CompletionAction.NONE -> Unit
            }
        }
        // Give Flutter and plugins a short grace period to deliver MethodChannel
        // responses before we background/finish the activity for the caller handoff.
        val view = window?.decorView
        if (view != null) {
            view.postDelayed(runnable, 500L)
        } else {
            runnable.run()
        }
    }

    private fun isActiveRequest(arguments: Map<*, *>?): Boolean {
        val requestedToken = arguments?.get("requestToken") as? String
        val activeToken = activeRequestToken
        return activeToken != null && requestedToken == activeToken
    }
}
