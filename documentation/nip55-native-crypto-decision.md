# NIP-55 Native Crypto — Signing Decision

Decided 2026-10-07 in diogel-io/symudol#12.

## Context

The background `Nip55ContentProvider` answers remembered NIP-55 requests while the vault is
unlocked. It used to sign `sign_event` and `sign_message` in Kotlin (`Nip55NativeCrypto`), with
hand-written secp256k1 and BIP-340 code:

- the curve arithmetic uses `BigInteger`, which is not constant-time;
- it once had a point-doubling bug (dividing by `y` instead of `2y`) that produced invalid
  signatures;
- its `selfTest()` ran, but its result was ignored;
- a native signature was never verified before it was returned. The Dart vault service verifies
  every signature it makes.

## Options

1. **Keep native signing**: verify each signature before returning it, fail closed when the
   self-test fails, and move to a vetted library. Verifying with the same hand-written curve code
   that signed proves little, and a vetted native library (for example secp256k1-kmp) adds a JNI
   dependency.
2. **Route signing to Dart**: native code never signs; the request goes to the Dart vault service.

## Decision

Option 2. Native code never signs.

A `sign_event` or `sign_message` with a remembered allow is passed through `Nip55ProviderBridge`
to `Nip55Controller.handleProviderQuery`, which signs with `VaultService`.
`VaultServiceImpl.signNostrEvent` and `DartNostrCryptoService.signMessage` verify the signature
before returning it; one that fails is an error, which the provider returns as no answer.

This route is open whenever native signing could have run: the native key is cleared in
`MainActivity.onDestroy`, at the same moment the bridge detaches (#9).

A `sign_message` of a Nostr event serialisation is still refused natively before it reaches the
bridge (#8). Dart refuses it too.

## What Native Code Still Does

- Transport: request tokens, result ownership, permission mirroring, caller identity.
- `get_public_key`.
- NIP-04 and NIP-44 encrypt/decrypt, and `decrypt_zap_event`, with native ECDH. These run only
  while `Nip55NativeCrypto.selfTestPassed`: known answers for the curve arithmetic (1·G, 2·G, a
  full-width scalar) and a NIP-44 conversation-key vector, computed once. If it fails, those
  methods fall through to the Dart bridge too.

The ECDH still uses the hand-written, non-constant-time curve code, and native code still holds
the key for it. The self-test catches broken arithmetic, not timing leaks. Routing encryption to
Dart as well, or adopting a vetted library, is follow-up work.

## Consequences

- Background signing waits on the Flutter engine: the bridge posts to the main thread and blocks
  the client's Binder thread for up to 3 seconds (`Nip55ProviderBridge`).
- When Dart cannot answer (a NIP-55 request is pending review, the vault is locked, or the bridge
  times out), the provider returns `null` and the client falls back to the intent, where the user
  sees the request. That is safe, but may mean more prompts.
- No unverified signature leaves the app.

## Tests

- `Nip55ContentProviderTest`: a remembered kind is signed by Dart and only that kind; with no
  Flutter engine to answer, nothing is signed; a failed self-test stops native encryption and
  Dart answers instead.
- `Nip55NativeCryptoTest`: native crypto has no signing operation; the self-test passes.
- `nip55_controller_test.dart`: a provider `sign_event` returns a signature that verifies; a
  signature that fails verification is never returned.
