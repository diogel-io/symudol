package io.diogel.nip55testclient

import android.app.Activity
import android.os.Bundle

/**
 * Where Symudol sends the browser flow's result: `nip55testclient://callback?event=<signature>`.
 * Reports the browser_callback verdict, then gets out of the way.
 */
class CallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val signature = intent?.data?.getQueryParameter("event")
        if (Results.isRunning(SCENARIO)) {
            if (Nostr.isHex(signature, 128)) {
                Results.pass(SCENARIO, "callback returned a signature")
            } else {
                Results.fail(SCENARIO, "callback returned no signature")
            }
        }
        finish()
    }

    private companion object {
        const val SCENARIO = "browser_callback"
    }
}
