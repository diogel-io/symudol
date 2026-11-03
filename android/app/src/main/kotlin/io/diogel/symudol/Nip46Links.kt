package io.diogel.symudol

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `nostrconnect:` links from other apps, for NIP-46 pairing (diogel-io/symudol#31).
 *
 * The link filter sits on [ALIAS], which is off until Dart turns it on, so a build that hides
 * NIP-46 (#26) is never offered for these links. A link is kept until Dart takes it, and handed
 * over once. It carries the client's secret, so it is never logged.
 */
class Nip46Links(private val context: Context) {
    private var pendingLink: String? = null
    private var channel: MethodChannel? = null

    companion object {
        const val CHANNEL = "io.diogel.symudol/nip46_links"
        const val ALIAS = "io.diogel.symudol.Nip46LinkAlias"
        private const val TAG = "Diogel-Nip46Links"

        /**
         * The `nostrconnect:` link [intent] opens, or null. A link reopened from recents is
         * not a new one, so it is ignored.
         */
        fun linkFrom(intent: Intent?): String? {
            if (intent?.action != Intent.ACTION_VIEW) return null
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
            val data = intent.data ?: return null
            if (!data.scheme.equals("nostrconnect", ignoreCase = true)) return null
            return intent.dataString
        }
    }

    /** Keeps the link [intent] opens, if any, and tells Dart one is waiting. */
    fun receive(intent: Intent?): Boolean {
        val link = linkFrom(intent) ?: return false
        DiogelLog.d(TAG) { "receive: a nostrconnect link arrived" }
        pendingLink = link
        channel?.invokeMethod("linkAvailable", null)
        return true
    }

    /**
     * [receive] for the intent an activity is created with. A recreated activity keeps its
     * launch intent, whose link was handed over already, so it is ignored then.
     */
    fun receiveOnCreate(intent: Intent?, recreated: Boolean): Boolean =
        if (recreated) false else receive(intent)

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeLink" -> {
                val link = pendingLink
                pendingLink = null
                result.success(link)
            }
            "setLinksEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    setAliasEnabled(enabled)
                } catch (e: Exception) {
                    DiogelLog.w(TAG, "setLinksEnabled failed", e)
                    return result.error("ALIAS_FAILED", "could not change link handling", null)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setAliasEnabled(enabled: Boolean) {
        val component = ComponentName(context.packageName, ALIAS)
        val wanted = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        val packageManager = context.packageManager
        if (packageManager.getComponentEnabledSetting(component) == wanted) return
        packageManager.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
    }
}
