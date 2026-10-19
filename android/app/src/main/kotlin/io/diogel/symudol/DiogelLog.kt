package io.diogel.symudol

import android.util.Log

/**
 * The only way Symudol's Kotlin code writes to the system log (SR-21, #14).
 *
 * Debug lines exist only in debug builds: [d] is inline and checks the compile-time
 * [BuildConfig.DEBUG], so a release build drops the message and its string. Warnings and
 * errors stay in release builds but carry only the fixed message and the exception's class
 * name, never its message or stack trace, because an exception's message can quote what it
 * failed to parse.
 *
 * No line may carry event content, plaintext, ciphertext, key material or grant data. Caller
 * package names and methods may go to [d] only.
 */
internal object DiogelLog {
    inline fun d(tag: String, message: () -> String) {
        if (BuildConfig.DEBUG) Log.d(tag, message())
    }

    fun w(tag: String, message: String, error: Throwable? = null) {
        Log.w(tag, line(message, error))
    }

    fun e(tag: String, message: String, error: Throwable? = null) {
        Log.e(tag, line(message, error))
    }

    /** The logged text: the fixed message, plus the exception's class name when there is one. */
    fun line(message: String, error: Throwable?): String =
        if (error == null) message else "$message (${error.javaClass.simpleName})"
}
