package io.diogel.symudol

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
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
        private const val CLIPBOARD_CHANNEL = "io.diogel.symudol/clipboard"
        private val appLabelCache = ConcurrentHashMap<String, String>()
        private val certificateCache = ConcurrentHashMap<String, String>()
        private val appIconCache = ConcurrentHashMap<String, ByteArray>()
        @Volatile private var currentActivity: WeakReference<MainActivity>? = null

        fun deliverNip55BridgeIntent(intent: Intent): Boolean {
            val activity = currentActivity?.get() ?: return false
            return activity.deliverNip55IntentFromBridge(intent)
        }
    }

    private val channelName = "io.diogel.symudol/nip55"
    private var channel: MethodChannel? = null
    private var initialNip55Intent: Map<String, Any?>? = null
    private var latestNip55Intent: Map<String, Any?>? = null
    // Which requests are active, and where answers go: only to the bridge (#7, #68).
    private val router = Nip55RequestRouter()
    private var pendingCompletionRunnable: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        DiogelLog.d(TAG) { "onCreate: action=${intent?.action}" }
        // Flutter draws every screen in this window, keys, decrypted previews and approvals
        // included: keep it out of screenshots, screen recording and the recents preview
        // (SR-23, #15). Set before the first frame.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        currentActivity = WeakReference(this)
        super.onCreate(savedInstanceState)
        initialNip55Intent = router.parse(intent)
        initialNip55Intent?.let { router.activate(it, markDelivered = false) }
        DiogelLog.d(TAG) { "onCreate: activeRequestToken=${router.activeRequestToken}" }
        
        // Asynchronously resolve app label and certificate if they are missing
        initialNip55Intent?.let { resolveMetadataAsync(it) { updated -> initialNip55Intent = updated } }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        DiogelLog.d(TAG) { "configureFlutterEngine" }
        super.configureFlutterEngine(flutterEngine)
        // Sensitive copies from Dart, such as the NIP-46 bunker URI (#94).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "copySensitiveText") return@setMethodCallHandler result.notImplemented()
            val text = call.argument<String>("text")
            if (text == null) return@setMethodCallHandler result.error("INVALID_ARGS", "text required", null)
            try {
                SensitiveClipboard.copy(applicationContext, call.argument<String>("label") ?: "Symudol", text)
            } catch (e: Exception) {
                DiogelLog.w(TAG, "copySensitiveText: clipboard copy failed", e)
                return@setMethodCallHandler result.error("COPY_FAILED", "copy failed", null)
            }
            result.success(null)
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.let { Nip55ProviderBridge.attach(it) }
        channel?.setMethodCallHandler { call, result ->
            DiogelLog.d(TAG) { "onMethodCall: ${call.method}" }
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
                "syncNip55PermissionGrants" -> {
                    val grantsJson = call.arguments as? String
                    DiogelLog.d(TAG) { "onMethodCall: syncNip55PermissionGrants hasGrants=${grantsJson != null}" }
                    if (grantsJson != null) {
                        Nip55PermissionMirror(this).syncGrants(grantsJson)
                    }
                    result.success(null)
                }
                "setNip55ActiveKey" -> {
                    val args = call.arguments as? Map<*, *>
                    // Raw bytes (a Dart Uint8List), never a String, so the key can be zeroed (#9).
                    val privateKey = args?.get("privateKey") as? ByteArray
                    val publicKey = args?.get("publicKey")?.toString()
                    val localId = args?.get("localId")?.toString()
                    DiogelLog.d(TAG) { "onMethodCall: setNip55ActiveKey" }
                    if (privateKey != null && privateKey.size == 32 && publicKey != null) {
                        Nip55CryptoBridge.setActiveKey(privateKey, publicKey, localId ?: "")
                        privateKey.fill(0)
                        result.success(null)
                    } else {
                        privateKey?.fill(0)
                        result.error("INVALID_ARGS", "a 32-byte privateKey and publicKey required", null)
                    }
                }
                "clearNip55ActiveKey" -> {
                    DiogelLog.d(TAG) { "onMethodCall: clearNip55ActiveKey" }
                    Nip55CryptoBridge.clearActiveKey()
                    result.success(null)
                }
                "setNip55LockDeadline" -> {
                    val delayMs = (call.arguments as? Number)?.toLong()
                    if (delayMs == null) {
                        result.error("INVALID_ARGS", "delay in milliseconds required", null)
                    } else {
                        Nip55CryptoBridge.setLockDeadline(delayMs)
                        result.success(null)
                    }
                }
                "clearNip55LockDeadline" -> {
                    Nip55CryptoBridge.clearLockDeadline()
                    result.success(null)
                }
                "getAppIcon" -> {
                    val packageName = call.arguments as? String
                    if (packageName.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        backgroundExecutor.execute {
                            val icon = resolveAppIcon(packageName)
                            mainHandler.post { result.success(icon) }
                        }
                    }
                }
                "setNip55ActiveIdentityPubkey" -> {
                    val pubkey = call.arguments as? String
                    DiogelLog.d(TAG) { "onMethodCall: setNip55ActiveIdentityPubkey" }
                    if (pubkey.isNullOrBlank()) {
                        Nip55PermissionMirror(this).setActiveIdentityPubkey(null)
                    } else {
                        Nip55PermissionMirror(this).setActiveIdentityPubkey(pubkey)
                    }
                    result.success(null)
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
        // The engine goes with the activity (configuration changes are handled in place), and
        // with it the Dart lock timers: the ContentProvider must not keep signing (#9).
        Nip55CryptoBridge.clearActiveKey()
        super.onDestroy()
    }

    override fun onResume() {
        currentActivity = WeakReference(this)
        super.onResume()
    }

    override fun onNewIntent(intent: Intent) {
        DiogelLog.d(TAG) { "onNewIntent: action=${intent.action}" }
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = router.parse(intent)
        if (payload != null) deliverNip55Payload(payload)
    }

    private fun deliverNip55IntentFromBridge(intent: Intent): Boolean {
        val payload = router.parse(intent) ?: return false
        return deliverNip55Payload(payload)
    }

    private fun deliverNip55Payload(payload: Map<String, Any?>): Boolean {
        if (channel == null) return false
        pendingCompletionRunnable?.let {
            DiogelLog.d(TAG) { "deliverNip55Payload: Cancelling pending completion for new request" }
            mainHandler.removeCallbacks(it)
            pendingCompletionRunnable = null
        }
        if (!router.activate(payload, markDelivered = true)) {
            DiogelLog.d(TAG) { "deliverNip55Payload: request already delivered, ignoring" }
            return true
        }
        latestNip55Intent = payload

        // Asynchronously resolve metadata before sending to Dart.
        resolveMetadataAsync(payload) { updated ->
            latestNip55Intent = updated
            DiogelLog.d(TAG) { "deliverNip55Payload: Sending onNip55Intent to Dart" }
            runOnUiThread {
                channel?.invokeMethod("onNip55Intent", updated)
            }
        }
        return true
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

    private fun resolveAppIcon(packageName: String): ByteArray? {
        appIconCache[packageName]?.let { return it }
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val bytes = stream.toByteArray()
            appIconCache[packageName] = bytes
            bytes
        } catch (_: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
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
        val requestedToken = arguments?.get("requestToken") as? String
        if (!router.isActive(requestedToken)) return CompletionAction.NONE
        val extras = arguments?.get("extras") as? Map<*, *> ?: emptyMap<Any, Any>()
        maybeLaunchCallback(extras)
        maybeCopyToClipboard(extras)
        // Only the bridge answers the caller; a result is never handed to whoever started this
        // activity (#7).
        router.complete(requestedToken, extras)
        return CompletionAction.BACKGROUND
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
        // A failed copy must not stop the bridge from answering the caller.
        try {
            SensitiveClipboard.copy(this, label, result)
        } catch (e: Exception) {
            DiogelLog.w(TAG, "completeNip55Intent: clipboard copy failed", e)
        }
    }

    private fun rejectNip55Intent(arguments: Map<*, *>?): CompletionAction {
        val requestedToken = arguments?.get("requestToken") as? String
        if (!router.isActive(requestedToken)) return CompletionAction.NONE
        router.reject(
            requestedToken,
            arguments?.get("error") as? String,
            rejected = arguments?.get("rejected") as? Boolean ?: false,
        )
        return CompletionAction.BACKGROUND
    }

    private fun runAfterMethodResponse(action: CompletionAction) {
        DiogelLog.d(TAG) { "runAfterMethodResponse: action=$action" }
        if (action == CompletionAction.NONE) return

        // Cancel any existing pending completion to avoid finishing/backgrounding
        // if a second request arrived during the grace period of the first.
        pendingCompletionRunnable?.let { mainHandler.removeCallbacks(it) }

        val runnable = Runnable {
            pendingCompletionRunnable = null

            DiogelLog.d(TAG) { "Executing completion action: $action" }
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
}
