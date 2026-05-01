package io.threenine.androidiogel

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
                    completeNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "rejectNip55Intent" -> {
                    rejectNip55Intent(call.arguments as? Map<*, *>)
                    result.success(null)
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

        val token = "nip55-${System.currentTimeMillis()}-${nextRequestNumber++}"
        return mapOf(
            "requestToken" to token,
            "type" to intent.getStringExtra("type"),
            "content" to extractContent(data),
            "id" to intent.getStringExtra("id"),
            "currentUser" to intent.getStringExtra("current_user"),
            "pubkey" to intent.getStringExtra("pubkey"),
            "permissions" to intent.getStringExtra("permissions"),
            "callerPackage" to (callingPackage ?: referrer?.host ?: intent.`package`),
            "dataUri" to data.toString()
        )
    }

    private fun extractContent(uri: Uri): String? {
        val raw = uri.schemeSpecificPart ?: return null
        if (raw.isBlank()) return null
        return Uri.decode(raw.removePrefix("//"))
    }

    private fun completeNip55Intent(arguments: Map<*, *>?) {
        if (!isActiveRequest(arguments)) return
        val extras = arguments?.get("extras") as? Map<*, *> ?: emptyMap<Any, Any>()
        val resultIntent = Intent()
        extras.forEach { (key, value) ->
            if (key is String && value != null) {
                resultIntent.putExtra(key, value.toString())
            }
        }
        setResult(Activity.RESULT_OK, resultIntent)
        activeRequestToken = null
        finish()
    }

    private fun rejectNip55Intent(arguments: Map<*, *>?) {
        if (!isActiveRequest(arguments)) return
        val resultIntent = Intent()
        val error = arguments?.get("error") as? String
        if (!error.isNullOrBlank()) {
            resultIntent.putExtra("error", error)
        }
        setResult(Activity.RESULT_CANCELED, resultIntent)
        activeRequestToken = null
        finish()
    }

    private fun isActiveRequest(arguments: Map<*, *>?): Boolean {
        val requestedToken = arguments?.get("requestToken") as? String
        val activeToken = activeRequestToken
        return activeToken != null && requestedToken == activeToken
    }
}
