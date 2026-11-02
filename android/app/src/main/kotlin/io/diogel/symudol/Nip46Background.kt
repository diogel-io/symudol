package io.diogel.symudol

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Dart side's way to the NIP-46 foreground service and its request notices
 * (diogel-io/symudol#29). A notice names no client, kind or content, on the lock screen or
 * anywhere else: the client name is unverified and the content is private (SR-21, SR-23).
 */
class Nip46Background(private val activity: Activity, private val channel: MethodChannel) {

    companion object {
        const val CHANNEL = "io.diogel.symudol/nip46_service"
        const val REQUESTS_CHANNEL_ID = "nip46_requests"
        private const val PERMISSION_REQUEST = 4602
    }

    init {
        Nip46ForegroundService.onStopRequested = {
            channel.invokeMethod("stopRequested", null)
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                Nip46ForegroundService.start(activity.applicationContext)
                result.success(null)
            }
            "stop" -> {
                Nip46ForegroundService.stop(activity.applicationContext)
                result.success(null)
            }
            "showHeldRequest" -> {
                val sessionId = call.argument<String>("sessionId")
                    ?: return result.error("ARGS", "sessionId missing", null)
                showHeldRequest(sessionId)
                result.success(null)
            }
            "cancelHeldRequest" -> {
                val sessionId = call.argument<String>("sessionId")
                    ?: return result.error("ARGS", "sessionId missing", null)
                NotificationManagerCompat.from(activity).cancel(sessionId, 0)
                result.success(null)
            }
            "notificationsAllowed" -> result.success(notificationsAllowed())
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsAllowed()) {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        PERMISSION_REQUEST,
                    )
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** MainActivity is going: the service must not outlive the engine (#9). */
    fun detach() {
        Nip46ForegroundService.onStopRequested = null
        Nip46ForegroundService.stop(activity.applicationContext)
    }

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun showHeldRequest(sessionId: String) {
        if (!notificationsAllowed()) return
        ensureRequestsChannel()
        val open = PendingIntent.getActivity(
            activity,
            2,
            Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(activity, REQUESTS_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(activity.getString(R.string.nip46_request_title))
            .setContentText(activity.getString(R.string.nip46_request_text))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(activity).notify(sessionId, 0, notification)
        } catch (e: SecurityException) {
            DiogelLog.w("Diogel-Nip46", "Request notice not shown: no permission", e)
        }
    }

    private fun ensureRequestsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = activity.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(REQUESTS_CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                REQUESTS_CHANNEL_ID,
                activity.getString(R.string.nip46_requests_channel),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }
}
