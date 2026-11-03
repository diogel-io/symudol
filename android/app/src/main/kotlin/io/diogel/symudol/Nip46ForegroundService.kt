package io.diogel.symudol

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Keeps Symudol's process, and so the Dart relay connections, alive while it is in the
 * background and the user wants remote signing (diogel-io/symudol#29).
 *
 * It holds no keys and does no crypto. It only runs while MainActivity exists: the activity
 * stops it when it is destroyed, which is when the native key is cleared (#9). A vault lock
 * leaves it running, so a request held for unlock can still reach the user.
 */
class Nip46ForegroundService : Service() {

    companion object {
        const val ACTION_START = "io.diogel.symudol.nip46.START"
        const val ACTION_STOP = "io.diogel.symudol.nip46.STOP"
        const val CHANNEL_ID = "nip46_service"
        const val NOTIFICATION_ID = 4601

        /** Called on the main thread when the user taps Stop. */
        @Volatile var onStopRequested: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, Nip46ForegroundService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, Nip46ForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            onStopRequested?.invoke()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Not restarted by the system: without the activity there is no engine to serve.
        return START_NOT_STICKY
    }

    private fun buildNotification(): android.app.Notification {
        ensureChannel()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, Nip46ForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(getString(R.string.nip46_service_title))
            .setContentText(getString(R.string.nip46_service_text))
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(0, getString(R.string.nip46_service_stop), stop)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.nip46_service_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }
}
