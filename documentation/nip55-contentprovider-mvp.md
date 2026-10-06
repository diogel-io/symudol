# NIP-55 ContentProvider — MVP Scope Decision

## Summary

Diogel's `Nip55ContentProvider` implements **warm-session ContentProvider support**:
a remembered-grant, vault-unlocked fast path that answers NIP-55 queries from
client apps without launching the Flutter UI. This is distinct from cold background
signing, which Diogel does not support.

## What the ContentProvider Covers

| Scenario | Behaviour |
|----------|-----------|
| Remembered allow grant + vault unlocked | Native crypto or Flutter bridge handles the request inline; returns a populated cursor. |
| Remembered reject grant | Returns a `rejected` cursor immediately. |
| First-time request (no remembered grant) | Returns `null` so the client falls back to foreground Intent. |
| Vault locked + no remembered grant | Returns `null`; client falls back to Intent. |

## What It Intentionally Does Not Cover

**Cold background signing** — signing a new request in the background without any
prior user interaction — is out of MVP scope (not cold background signing).
Supporting it would require storing the private key in a background-accessible
location or launching a headless background service, both of which weaken the
security model. The ContentProvider path is fast and silent only because the user
already granted permission and the vault is already unlocked from a recent
foreground session.

## Implementation Design

The ContentProvider reuses the **same parser, approval policy, vault** surface as
the foreground NIP-55 path:

- `Nip55RequestCodec` handles projection parsing.
- `Nip55PermissionMirror` mirrors remembered grants from the Dart permission store.
- `Nip55CryptoBridge` provides access to the active identity's in-memory private key.
- `Nip55NativeCrypto` performs crypto operations (Schnorr signing, NIP-04/NIP-44).

There is no separate code path for ContentProvider crypto. The only difference
from the foreground path is that the ContentProvider skips the approval UI — it
only auto-executes requests already covered by a remembered allow grant.

## How Long the Native Key Lives

The ContentProvider can only answer while `Nip55CryptoBridge` holds the key
(diogel-io/symudol#9):

- The key is sent from Dart as raw bytes and held as a `ByteArray`, which is
  zeroed when cleared. It is never a JVM `String`.
- It is cleared when the vault locks, when `MainActivity` is destroyed (the
  Flutter engine, and its lock timers, go with it), and when the app detaches.
- When the app goes to the background, Dart gives the native side a lock
  deadline: the background-lock delay, or, while a NIP-55 review is pending,
  the review's remaining time plus that delay. A main-looper timer clears the
  key at the deadline, and every read checks it, so it holds without the
  Flutter engine. Returning to the foreground removes the deadline.
- A pending review is rejected after 5 minutes. The background lock is
  deferred while a request is pending and applies once it settles.
- With no key, a remembered request gets `null` (the client falls back to the
  intent). It is not passed on to the Flutter bridge.

The Dart vault's own copy of the key, and the `BigInteger`s used during
signing, can't be zeroed; this bounds the native copy only.

## Projection Shape Validation

**Projection shape validation** is enforced before bridging to Flutter. The
`hasRequiredProjection` function checks that mandatory fields (event JSON, peer
pubkey for encrypt/decrypt) are present in the projection array. If any required
field is missing, the ContentProvider returns `null` rather than forwarding an
incomplete request.

`currentUser` is intentionally optional: some NIP-55 clients (early Amethyst
versions) do not send it. The ContentProvider resolves identity from the active
vault key instead.

## Null vs Rejected Cursor

- **`null`**: returned when there is no remembered grant, the vault is locked, or
  the projection is missing required fields. The client falls back to a foreground
  Intent.
- **Rejected cursor** (`rejected` column, value `true`): returned only when there
  is an explicit remembered reject grant. The client should not prompt the user
  again for that operation.

These two outcomes have different meanings to the client. Mixing them (e.g.
returning a rejected cursor when the vault is locked) would cause clients to
silently fail instead of showing an approval UI.
