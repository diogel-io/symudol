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
                    val shouldFinish = completeNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
                    if (shouldFinish) finishAfterMethodResponse()
                }
                "rejectNip55Intent" -> {
                    val shouldFinish = rejectNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
                    if (shouldFinish) finishAfterMethodResponse()
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
            "type" to (intent.getStringExtra("type") ?: data.safeQueryParameter("type")),
            "content" to extractContent(data),
            "id" to (intent.getStringExtra("id") ?: data.safeQueryParameter("id")),
            "currentUser" to (intent.getStringExtra("current_user") ?: data.safeQueryParameter("current_user")),
            "pubkey" to (intent.getStringExtra("pubkey") ?: data.safeQueryParameter("pubkey")),
            "permissions" to (intent.getStringExtra("permissions") ?: data.safeQueryParameter("permissions")),
            "callbackUrl" to data.safeQueryParameter("callbackUrl"),
            "returnType" to data.safeQueryParameter("returnType"),
            "compressionType" to data.safeQueryParameter("compressionType"),
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

    private fun Uri.safeQueryParameter(name: String): String? {
        if (!isHierarchical) return null
        return try {
            getQueryParameter(name)
        } catch (_: UnsupportedOperationException) {
            null
        }
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

    private fun extractContent(uri: Uri): String? {
        val raw = uri.schemeSpecificPart ?: return null
        if (raw.isBlank()) return null
        val withoutQuery = raw.substringBefore("?")
        return Uri.decode(withoutQuery.removePrefix("//"))
    }

    private fun completeNip55Intent(arguments: Map<*, *>?): Boolean {
        if (!isActiveRequest(arguments)) return false
        val extras = arguments?.get("extras") as? Map<*, *> ?: emptyMap<Any, Any>()
        maybeLaunchCallback(extras)
        maybeCopyToClipboard(extras)
        val bridgeToken = activeRequestToken
        if (bridgeToken != null && Nip55BridgeRegistry.complete(bridgeToken, extras)) {
            activeRequestToken = null
            return true
        }
        val resultIntent = Intent()
        extras.forEach { (key, value) ->
            if (key is String && value != null) {
                resultIntent.putExtra(key, value.toString())
            }
        }
        setResult(Activity.RESULT_OK, resultIntent)
        activeRequestToken = null
        return true
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

    private fun rejectNip55Intent(arguments: Map<*, *>?): Boolean {
        if (!isActiveRequest(arguments)) return false
        val bridgeToken = activeRequestToken
        val error = arguments?.get("error") as? String
        if (bridgeToken != null && Nip55BridgeRegistry.reject(bridgeToken, error)) {
            activeRequestToken = null
            return true
        }
        val resultIntent = Intent()
        if (!error.isNullOrBlank()) {
            resultIntent.putExtra("error", error)
        }
        setResult(Activity.RESULT_CANCELED, resultIntent)
        activeRequestToken = null
        return true
    }

    private fun finishAfterMethodResponse() {
        window?.decorView?.post { finish() } ?: finish()
    }

    private fun isActiveRequest(arguments: Map<*, *>?): Boolean {
        val requestedToken = arguments?.get("requestToken") as? String
        val activeToken = activeRequestToken
        return activeToken != null && requestedToken == activeToken
    }
}
