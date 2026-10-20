package io.diogel.symudol

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/**
 * A clock the user cannot change, for PIN lockouts (diogel-io/symudol#16).
 *
 * `elapsedRealtime` counts from boot, including deep sleep, and is not moved by the date and
 * time settings. It restarts at each boot, so the boot count says which boot a reading belongs
 * to. `BOOT_COUNT` is available from API 24, the minSdk.
 */
object MonotonicClock {
    const val CHANNEL = "io.diogel.symudol/clock"

    fun now(context: Context): Map<String, Long> = mapOf(
        "elapsedRealtimeMs" to SystemClock.elapsedRealtime(),
        "bootCount" to Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, 0).toLong(),
    )
}
