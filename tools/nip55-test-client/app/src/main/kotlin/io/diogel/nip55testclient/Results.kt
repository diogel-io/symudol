package io.diogel.nip55testclient

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * The one running scenario and its verdict. Every verdict is a single logcat line under [TAG],
 * `RESULT <id> PASS|FAIL <reason>`, which nip55_device_check.sh reads.
 *
 * Main thread only. A singleton so CallbackActivity can report for the browser scenario.
 */
object Results {
    const val TAG = "Nip55Test"

    private val handler = Handler(Looper.getMainLooper())
    private var current: String? = null
    private var timeout: Runnable? = null

    var listener: ((String) -> Unit)? = null

    fun start(id: String, timeoutMs: Long, onTimeout: () -> Unit) {
        current?.let { report(it, "FAIL", "superseded by $id") }
        current = id
        timeout = Runnable { onTimeout() }.also { handler.postDelayed(it, timeoutMs) }
        Log.i(TAG, "START $id")
        listener?.invoke("$id: running")
    }

    fun isRunning(id: String): Boolean = current == id

    fun pass(id: String, reason: String) = report(id, "PASS", reason)

    fun fail(id: String, reason: String) = report(id, "FAIL", reason)

    private fun report(id: String, verdict: String, reason: String) {
        if (current != id) return
        current = null
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        // Reasons are short and single-line, so the script can print them in its summary.
        val line = "RESULT $id $verdict ${reason.replace('\n', ' ')}"
        Log.i(TAG, line)
        listener?.invoke(line)
    }
}
