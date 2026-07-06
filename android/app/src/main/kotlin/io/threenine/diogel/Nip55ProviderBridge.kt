package io.threenine.diogel

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

object Nip55ProviderBridge {
    private const val METHOD_HANDLE_PROVIDER_QUERY = "handleNip55ProviderQuery"
    private const val QUERY_TIMEOUT_MS = 3000L
    private const val MAX_QUEUED_QUERIES = 50
    @Volatile private var channel: MethodChannel? = null
    private val queuedQueriesCount = AtomicInteger(0)

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun detach(channel: MethodChannel?) {
        if (this.channel == channel) {
            this.channel = null
        }
    }

    /**
     * Dispatch a NIP-55 query to the Flutter engine and block until a response
     * arrives or the [QUERY_TIMEOUT_MS] deadline (3 s) passes.
     *
     * **Caller-blocking warning**: this method is invoked on the ContentProvider
     * query thread, which is the *calling app's* Binder thread. It will hold that
     * thread for up to 3 seconds while waiting for the Flutter engine to respond.
     * Calling apps that issue the query on their main thread risk an ANR; well-
     * behaved NIP-55 clients (Amethyst, Quartz) use a background thread for
     * ContentResolver queries, so in practice the ANR risk is on the client side.
     * A proper async ContentProvider using ContentResolver.notifyChange() would
     * eliminate this ceiling entirely but requires a protocol change with clients.
     */
    fun query(arguments: Map<String, Any?>): Map<String, Any?>? {
        val activeChannel = channel ?: return null

        if (queuedQueriesCount.get() >= MAX_QUEUED_QUERIES) {
            return null
        }

        queuedQueriesCount.incrementAndGet()
        try {
            val latch = CountDownLatch(1)
            val response = AtomicReference<Map<String, Any?>?>()
            val mainHandler = Handler(Looper.getMainLooper())
            mainHandler.post {
                activeChannel.invokeMethod(
                    METHOD_HANDLE_PROVIDER_QUERY,
                    arguments,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            response.set(castMap(result))
                            latch.countDown()
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            response.set(null)
                            latch.countDown()
                        }

                        override fun notImplemented() {
                            response.set(null)
                            latch.countDown()
                        }
                    }
                )
            }
            return if (latch.await(QUERY_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                response.get()
            } else {
                null
            }
        } finally {
            queuedQueriesCount.decrementAndGet()
        }
    }

    private fun castMap(value: Any?): Map<String, Any?>? {
        if (value !is Map<*, *>) return null
        val result = mutableMapOf<String, Any?>()
        value.forEach { (key, item) ->
            if (key is String) result[key] = item
        }
        return result
    }
}
