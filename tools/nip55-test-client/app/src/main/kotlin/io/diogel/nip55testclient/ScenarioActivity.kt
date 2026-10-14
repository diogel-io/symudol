package io.diogel.nip55testclient

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.concurrent.Executors

/**
 * One button per scenario, and the adb entry point:
 * `adb shell am start -n io.diogel.nip55testclient/.ScenarioActivity --es scenario <id>`.
 */
class ScenarioActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val pending = HashMap<Int, (Int, Intent?) -> Unit>()
    private var nextRequestCode = 1
    private lateinit var log: TextView
    private val showLine: (String) -> Unit = { line -> log.append(line + "\n") }

    var storedPubkey: String?
        get() = getSharedPreferences(PREFERENCES, MODE_PRIVATE).getString(KEY_PUBKEY, null)
        set(value) {
            getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putString(KEY_PUBKEY, value).apply()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        Scenarios.all.forEach { scenario ->
            column.addView(Button(this).apply {
                text = scenario.title
                isAllCaps = false
                setOnClickListener { start(scenario.id) }
            })
        }
        log = TextView(this).apply { setTextIsSelectable(true) }
        column.addView(log)
        setContentView(ScrollView(this).apply { addView(column) })
        Results.listener = showLine
        startFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        startFrom(intent)
    }

    override fun onDestroy() {
        // A newer instance may have taken over the log: leave its listener alone.
        if (Results.listener === showLine) Results.listener = null
        worker.shutdown()
        super.onDestroy()
    }

    @Deprecated("The framework Activity result API is all a dependency-free client has.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        pending.remove(requestCode)?.invoke(resultCode, data)
    }

    private fun startFrom(intent: Intent?) {
        intent?.getStringExtra(EXTRA_SCENARIO)?.let { start(it) }
    }

    private fun start(id: String) {
        val scenario = Scenarios.byId[id]
        if (scenario == null) {
            Results.start(id, UNKNOWN_TIMEOUT_MS) {}
            Results.fail(id, "unknown scenario")
            return
        }
        val run = Run(id, this)
        Results.start(id, scenario.timeoutMs) { run.onTimeout() }
        scenario.body(run)
    }

    fun launch(intent: Intent, onResult: (Int, Intent?) -> Unit): Int {
        val requestCode = nextRequestCode++
        pending[requestCode] = onResult
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestCode)
        } catch (e: ActivityNotFoundException) {
            pending.remove(requestCode)
            onResult(RESULT_CANCELED, Intent().putExtra("rejected", "not found: ${e.message}"))
        }
        return requestCode
    }

    fun cancelLaunch(requestCode: Int) {
        pending.remove(requestCode)
        finishActivity(requestCode)
    }

    /** Starts [intent] as a browser would, with no result. Null when started, else why not. */
    fun startWithoutResult(intent: Intent): String? = try {
        startActivity(intent)
        null
    } catch (e: ActivityNotFoundException) {
        "not found: ${e.message}"
    }

    fun query(method: String, projection: Array<String>, onAnswer: (ProviderAnswer) -> Unit) {
        worker.execute {
            val answer = contentResolver.queryNip55(method, projection)
            main.post { onAnswer(answer) }
        }
    }

    companion object {
        const val EXTRA_SCENARIO = "scenario"
        private const val PREFERENCES = "nip55-test-client"
        private const val KEY_PUBKEY = "pubkey"
        private const val UNKNOWN_TIMEOUT_MS = 1_000L
    }
}
