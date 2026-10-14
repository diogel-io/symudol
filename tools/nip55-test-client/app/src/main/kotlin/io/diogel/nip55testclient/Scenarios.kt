package io.diogel.nip55testclient

import android.app.Activity
import android.content.Intent
import android.net.Uri

/**
 * One scenario run. Callbacks arriving after the verdict (a late activity result, a slow query)
 * are dropped, so each scenario reports exactly once.
 */
class Run(val id: String, private val activity: ScenarioActivity) {
    var onTimeout: () -> Unit = { fail("timed out") }

    val active: Boolean get() = Results.isRunning(id)

    fun pass(reason: String) = Results.pass(id, reason)

    fun fail(reason: String) = Results.fail(id, reason)

    /** The public key from the last get_public_key, or a FAIL when there is none yet. */
    fun requirePubkey(): String? =
        activity.storedPubkey ?: run {
            fail("no public key yet: run intent_get_public_key first")
            null
        }

    fun storePubkey(pubkey: String) {
        activity.storedPubkey = pubkey
    }

    fun launch(intent: Intent, onResult: (Int, Intent?) -> Unit): Int =
        activity.launch(intent) { code, data -> if (active) onResult(code, data) }

    fun cancelLaunch(requestCode: Int) = activity.cancelLaunch(requestCode)

    fun startWithoutResult(intent: Intent) {
        activity.startWithoutResult(intent)?.let { fail(it) }
    }

    fun query(method: String, projection: Array<String>, onAnswer: (ProviderAnswer) -> Unit) =
        activity.query(method, projection) { if (active) onAnswer(it) }
}

class Scenario(
    val id: String,
    val title: String,
    val timeoutMs: Long,
    val body: Run.() -> Unit,
)

/** One provider query and what makes its answer wrong, or null when it is right. */
private class Check(
    val method: String,
    val projection: Array<String>,
    val problem: (ProviderAnswer) -> String?,
)

private const val MESSAGE = "Symudol NIP-55 test client"
private const val EVENT_CONTENT = "Symudol NIP-55 test client"

/** A kind nothing else grants, so only a broad grant could sign it (#5). */
private const val BROAD_KIND = 9999

/** The app the forged request claims to be (#7), and a certificate it might claim. */
private const val FORGED_PACKAGE = "com.vitorpamplona.amethyst"
private const val FORGED_CERTIFICATE =
    "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

const val CALLBACK_URL = "nip55testclient://callback?event="

private fun now(): Long = System.currentTimeMillis() / 1000

/** The result extra of an approved intent request, or null. */
private fun answer(code: Int, data: Intent?): String? =
    data?.getStringExtra("result")?.takeIf { code == Activity.RESULT_OK && it.isNotBlank() }

private fun notAnswered(method: String): (ProviderAnswer) -> String? = { answer ->
    when (answer) {
        is ProviderAnswer.Answered -> "$method answered"
        is ProviderAnswer.Error -> "$method ${answer.describe()}"
        else -> null
    }
}

/** Runs [checks] one after another and hands over every problem found. */
private fun Run.queryEach(checks: List<Check>, problems: List<String> = emptyList(), done: (List<String>) -> Unit) {
    if (checks.isEmpty()) return done(problems)
    val check = checks.first()
    query(check.method, check.projection) { answer ->
        queryEach(checks.drop(1), problems + listOfNotNull(check.problem(answer)), done)
    }
}

/** Encrypts to the peer, then decrypts what came back, through the ContentProvider. */
private fun Run.providerRoundTrip(encrypt: String, decrypt: String, pubkey: String, done: (String?) -> Unit) {
    val plaintext = "provider round trip ${now()}"
    query(encrypt, arrayOf(plaintext, Nostr.PEER_PUBKEY, pubkey)) { encrypted ->
        if (encrypted !is ProviderAnswer.Answered) return@query done("$encrypt ${encrypted.describe()}")
        query(decrypt, arrayOf(encrypted.result, Nostr.PEER_PUBKEY, pubkey)) { decrypted ->
            done(
                when {
                    decrypted !is ProviderAnswer.Answered -> "$decrypt ${decrypted.describe()}"
                    decrypted.result != plaintext -> "$decrypt returned different text"
                    else -> null
                },
            )
        }
    }
}

/** Encrypts to the peer, then decrypts what came back, through two intents. */
private fun Run.intentRoundTrip(encrypt: String, decrypt: String) {
    val pubkey = requirePubkey() ?: return
    val plaintext = "intent round trip ${now()}"
    val extras = mapOf("pubkey" to Nostr.PEER_PUBKEY, "current_user" to pubkey)
    launch(Signer.intent(encrypt, plaintext, extras + ("id" to encrypt))) { code, data ->
        val ciphertext = answer(code, data) ?: return@launch fail("$encrypt not answered (result code $code)")
        launch(Signer.intent(decrypt, ciphertext, extras + ("id" to decrypt))) { decryptCode, decryptData ->
            when (answer(decryptCode, decryptData)) {
                null -> fail("$decrypt not answered (result code $decryptCode)")
                plaintext -> pass("$encrypt then $decrypt returned the plaintext")
                else -> fail("$decrypt returned different text")
            }
        }
    }
}

/**
 * Every scenario, in the order nip55_device_check.sh runs them. Order matters: the provider
 * checks after a grant rely on the grants the intent scenarios remember.
 */
object Scenarios {
    val all: List<Scenario> = listOf(
        Scenario("provider_before_grant", "Provider: no answer before a grant", 30_000) {
            val event = Nostr.unsignedEvent(1, EVENT_CONTENT, now())
            queryEach(
                listOf(
                    Check("get_public_key", arrayOf("login"), notAnswered("get_public_key")),
                    Check("sign_event", arrayOf(event, "", ""), notAnswered("sign_event")),
                    Check("sign_message", arrayOf(MESSAGE), notAnswered("sign_message")),
                    Check("nip44_encrypt", arrayOf(MESSAGE, Nostr.PEER_PUBKEY), notAnswered("nip44_encrypt")),
                    Check("nip44_decrypt", arrayOf("AgAAAA", Nostr.PEER_PUBKEY), notAnswered("nip44_decrypt")),
                    Check("nip04_encrypt", arrayOf(MESSAGE, Nostr.PEER_PUBKEY), notAnswered("nip04_encrypt")),
                    Check("nip04_decrypt", arrayOf("AAAA?iv=AAAA", Nostr.PEER_PUBKEY), notAnswered("nip04_decrypt")),
                ),
            ) { problems ->
                if (problems.isEmpty()) pass("no method answered before a grant") else fail(problems.joinToString("; "))
            }
        },

        Scenario("provider_broad_grant", "Provider: a broad sign_event grant signs nothing (#5)", 150_000) {
            val permissions = """[{"type":"get_public_key"},{"type":"sign_event"}]"""
            launch(Signer.intent("get_public_key", "", mapOf("id" to "broad-grant", "permissions" to permissions))) { code, data ->
                val pubkey = answer(code, data)
                    ?: return@launch fail("get_public_key with a broad sign_event permission was not approved")
                storePubkey(pubkey)
                val event = Nostr.unsignedEvent(BROAD_KIND, EVENT_CONTENT, now())
                query("sign_event", arrayOf(event, "", pubkey)) { answer ->
                    if (answer is ProviderAnswer.Answered) {
                        fail("kind $BROAD_KIND was signed in the background from a broad grant")
                    } else {
                        pass("kind $BROAD_KIND not signed in the background: ${answer.describe()}")
                    }
                }
            }
        },

        Scenario("intent_get_public_key", "Intent: get_public_key", 120_000) {
            launch(Signer.intent("get_public_key", "", mapOf("id" to "get-public-key"))) { code, data ->
                val pubkey = answer(code, data)
                val signerPackage = data?.getStringExtra("package")
                when {
                    pubkey == null -> fail("not approved (result code $code)")
                    !Nostr.isHex(pubkey, 64) -> fail("result is not a 64-hex public key")
                    signerPackage != Signer.PACKAGE -> fail("package is $signerPackage, not ${Signer.PACKAGE}")
                    else -> {
                        storePubkey(pubkey)
                        pass("public key ${pubkey.take(8)}…")
                    }
                }
            }
        },

        Scenario("intent_sign_event", "Intent: sign_event", 120_000) {
            val pubkey = requirePubkey() ?: return@Scenario
            val event = Nostr.unsignedEvent(1, EVENT_CONTENT, now())
            launch(Signer.intent("sign_event", event, mapOf("id" to "sign-event", "current_user" to pubkey))) { code, data ->
                val signature = answer(code, data) ?: return@launch fail("not approved (result code $code)")
                val problem = Nostr.signedEventProblem(data?.getStringExtra("event"), pubkey, 1, EVENT_CONTENT)
                when {
                    problem != null -> fail(problem)
                    !Nostr.isHex(signature, 128) -> fail("result is not a 128-hex signature")
                    else -> pass("signed kind 1")
                }
            }
        },

        Scenario("intent_sign_message", "Intent: sign_message", 120_000) {
            val pubkey = requirePubkey() ?: return@Scenario
            launch(Signer.intent("sign_message", MESSAGE, mapOf("id" to "sign-message", "current_user" to pubkey))) { code, data ->
                val signature = answer(code, data)
                when {
                    signature == null -> fail("not approved (result code $code)")
                    !Nostr.isHex(signature, 128) -> fail("result is not a 128-hex signature")
                    else -> pass("signed the message")
                }
            }
        },

        Scenario("intent_nip44_round_trip", "Intent: NIP-44 encrypt then decrypt", 180_000) {
            intentRoundTrip("nip44_encrypt", "nip44_decrypt")
        },

        Scenario("intent_nip04_round_trip", "Intent: NIP-04 encrypt then decrypt", 180_000) {
            intentRoundTrip("nip04_encrypt", "nip04_decrypt")
        },

        Scenario("provider_after_grant", "Provider: answers after remembered grants", 60_000) {
            val pubkey = requirePubkey() ?: return@Scenario
            val event = Nostr.unsignedEvent(1, EVENT_CONTENT, now())
            queryEach(
                listOf(
                    Check("get_public_key", arrayOf("login")) { answer ->
                        when {
                            answer !is ProviderAnswer.Answered -> "get_public_key ${answer.describe()}"
                            answer.result != pubkey -> "get_public_key returned another key"
                            else -> null
                        }
                    },
                    Check("sign_event", arrayOf(event, "", pubkey)) { answer ->
                        when {
                            answer !is ProviderAnswer.Answered -> "sign_event ${answer.describe()}"
                            !Nostr.isHex(answer.result, 128) -> "sign_event result is not a 128-hex signature"
                            else -> Nostr.signedEventProblem(answer.event, pubkey, 1, EVENT_CONTENT)
                                ?.let { "sign_event $it" }
                        }
                    },
                    Check("sign_message", arrayOf(MESSAGE, "", pubkey)) { answer ->
                        when {
                            answer !is ProviderAnswer.Answered -> "sign_message ${answer.describe()}"
                            !Nostr.isHex(answer.result, 128) -> "sign_message result is not a 128-hex signature"
                            else -> null
                        }
                    },
                ),
            ) { problems ->
                providerRoundTrip("nip44_encrypt", "nip44_decrypt", pubkey) { nip44 ->
                    providerRoundTrip("nip04_encrypt", "nip04_decrypt", pubkey) { nip04 ->
                        val all = problems + listOfNotNull(nip44, nip04)
                        if (all.isEmpty()) pass("every remembered method answered") else fail(all.joinToString("; "))
                    }
                }
            }
        },

        Scenario(
            "intent_sign_message_event_serialisation",
            "Intent: sign_message refuses an event serialisation (#8)",
            30_000,
        ) {
            val pubkey = requirePubkey() ?: return@Scenario
            val message = Nostr.serialise(pubkey, now(), 1, emptyList(), EVENT_CONTENT)
            val requestCode = launch(
                Signer.intent("sign_message", message, mapOf("id" to "event-serialisation", "current_user" to pubkey)),
            ) { code, data ->
                if (answer(code, data) != null) {
                    fail("an event serialisation was signed as a message")
                } else {
                    pass("refused (result code $code, rejected=${data?.getStringExtra("rejected")})")
                }
            }
            onTimeout = {
                cancelLaunch(requestCode)
                pass("no signature within 30 s")
            }
        },

        Scenario(
            "provider_sign_message_event_serialisation",
            "Provider: sign_message refuses an event serialisation (#8)",
            30_000,
        ) {
            val pubkey = requirePubkey() ?: return@Scenario
            val message = Nostr.serialise(pubkey, now(), 1, emptyList(), EVENT_CONTENT)
            query("sign_message", arrayOf(message, "", pubkey)) { answer ->
                if (answer is ProviderAnswer.Answered) {
                    fail("an event serialisation was signed as a message")
                } else {
                    pass("not signed: ${answer.describe()}")
                }
            }
        },

        Scenario("intent_forged_identity", "Forged identity: MainActivity ignores caller extras (#7)", 30_000) {
            // Straight to MainActivity, not through the nostrsigner: bridge, claiming to be another
            // app. Before #67 Symudol took the caller from these extras and answered whoever
            // started it; now it accepts a request only from its own bridge.
            val forged = Intent()
                .setClassName(Signer.PACKAGE, "${Signer.PACKAGE}.MainActivity")
                .putExtra("requestToken", "forged-${now()}")
                .putExtra("type", "get_public_key")
                .putExtra("callingPackage", FORGED_PACKAGE)
                .putExtra("callerCertificateSha256", FORGED_CERTIFICATE)
                .putExtra("callerAppLabel", "Amethyst")
            val requestCode = launch(forged) { code, data ->
                if (answer(code, data) != null) {
                    fail("Symudol answered a request posing as $FORGED_PACKAGE that skipped its bridge")
                } else {
                    pass("returned with no answer (result code $code)")
                }
            }
            onTimeout = {
                cancelLaunch(requestCode)
                pass("no answer within 30 s")
            }
        },

        Scenario("browser_callback", "Browser flow: sign_event with a callbackUrl", 120_000) {
            val pubkey = requirePubkey() ?: return@Scenario
            val event = Nostr.unsignedEvent(1, EVENT_CONTENT, now())
            // As a web page sends it: everything in the URI, BROWSABLE, and no activity result.
            // CallbackActivity reports the verdict when Symudol opens the callback.
            val uri = "nostrsigner:${Uri.encode(event)}?compressionType=none&returnType=signature" +
                "&type=sign_event&current_user=$pubkey&callbackUrl=${Uri.encode(CALLBACK_URL)}"
            startWithoutResult(
                Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                    .setPackage(Signer.PACKAGE)
                    .addCategory(Intent.CATEGORY_BROWSABLE),
            )
        },
    )

    val byId: Map<String, Scenario> = all.associateBy { it.id }
}
