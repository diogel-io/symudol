# NIP-55 Client Discovery Reference

This reference shows how an Android Nostr client should discover NIP-55 signers
and build ContentProvider URIs. It is designed to be shared with client
developers (Primal, Amethyst, Dark-Wisp, Nostria, and others) without
Diogel-specific assumptions.

---

## Discovery Flow

### Step 1: Discover installed signers

```kotlin
val discoveryIntent = Intent(Intent.ACTION_VIEW, Uri.parse("nostrsigner:"))
val signers: List<ResolveInfo> = packageManager.queryIntentActivities(discoveryIntent, 0)

// signers is empty if no NIP-55 signer is installed.
// Each signer's package name is in signer.activityInfo.packageName.
```

No hardcoded package names. Any app that exports an activity with the
`nostrsigner:` intent filter is a valid signer.

### Step 2: Let the user choose (or remember their selection)

```kotlin
val selectedSignerPackage: String = /* show picker or recall from preferences */
```

### Step 3: Probe capability with PING

```kotlin
val pingUri = Uri.parse("content://$selectedSignerPackage.PING")
val cursor = contentResolver.query(pingUri, null, null, null, null)
val isAvailable = cursor?.use {
    it.moveToFirst() && it.getColumnIndex("result") >= 0
} ?: false
```

A `null` result means the ContentProvider is unavailable (vault locked, signer
not running). Fall back to a foreground Intent in that case.

### Step 4: Build operation URIs from the discovered package

```kotlin
// sign_event
val signEventUri = Uri.parse("content://$selectedSignerPackage.SIGN_EVENT")

// get_public_key
val getPubkeyUri = Uri.parse("content://$selectedSignerPackage.GET_PUBLIC_KEY")

// nip44_encrypt
val nip44EncryptUri = Uri.parse("content://$selectedSignerPackage.NIP44_ENCRYPT")
```

**Never hardcode a package name.** Use the package discovered in Step 1.

---

## Performing Operations

### get_public_key

```kotlin
val cursor = contentResolver.query(
    Uri.parse("content://$signerPackage.GET_PUBLIC_KEY"),
    arrayOf(""),            // projection[0] = payload (empty for get_public_key)
    null, null, null,
)
val pubkey = cursor?.use {
    if (it.moveToFirst()) it.getString(it.getColumnIndexOrThrow("result")) else null
}
```

### sign_event

```kotlin
val cursor = contentResolver.query(
    Uri.parse("content://$signerPackage.SIGN_EVENT"),
    arrayOf(eventJson, "", currentUserPubkey),  // [payload, "", current_user]
    "1",          // selection = "1" signals intent to sign
    null, null,
)
cursor?.use {
    if (it.moveToFirst()) {
        val sig    = it.getString(it.getColumnIndexOrThrow("signature"))
        val result = it.getString(it.getColumnIndexOrThrow("result"))
        val event  = it.getString(it.getColumnIndexOrThrow("event"))
        // Use `event` as the complete signed event JSON.
    }
}
```

### nip44_encrypt / nip44_decrypt

```kotlin
val cursor = contentResolver.query(
    Uri.parse("content://$signerPackage.NIP44_ENCRYPT"),
    arrayOf(plaintext, peerPubkeyHex, currentUserPubkey),
    null, null, null,
)
val ciphertext = cursor?.use {
    if (it.moveToFirst()) it.getString(it.getColumnIndexOrThrow("result")) else null
}
```

---

## Handling Null and Rejected Cursors

| Cursor result | Meaning | Recommended action |
|---------------|---------|-------------------|
| `null` | No remembered grant, vault locked, or signer not running. | Fall back to foreground Intent via `nostrsigner:` URI. |
| Cursor with `rejected` column | User previously denied this request permanently. | Do not prompt again for this operation. Show an error. |
| Cursor with `result` or `event` | Operation succeeded. | Use the result. |

### Foreground Intent fallback

```kotlin
val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
    data = Uri.parse("nostrsigner:$payload?type=sign_event&id=$requestId")
    `package` = selectedSignerPackage   // target the previously selected signer
}
startActivityForResult(fallbackIntent, REQUEST_CODE_SIGN)
```

The signer delivers results via `onActivityResult`. The result Intent extras follow
the NIP-55 Intent protocol (key names in `strings.xml`).

---

## Authority Convention Summary

| Authority suffix | Operation |
|------------------|-----------|
| `.SIGN_EVENT` | BIP-340 Schnorr event signing |
| `.SIGN_MESSAGE` | Arbitrary message signing |
| `.GET_PUBLIC_KEY` | Retrieve the active identity public key |
| `.NIP44_ENCRYPT` | NIP-44 ECDH + ChaCha20 encryption |
| `.NIP44_DECRYPT` | NIP-44 ECDH + ChaCha20 decryption |
| `.NIP04_ENCRYPT` | NIP-04 ECDH + AES-256-CBC encryption |
| `.NIP04_DECRYPT` | NIP-04 ECDH + AES-256-CBC decryption |
| `.DECRYPT_ZAP_EVENT` | Decrypt a NIP-57 private zap event |
| `.PING` | Capability probe — always returns `pong` |

All authorities are prefixed with the signer's discovered package name, e.g.
`content://io.threenine.diogel.SIGN_EVENT`.

---

## Links

- NIP-55 specification: local copy at
  `../../../../../../30-research/nostr/nips/source/55.md`
- Signer discovery decisions: `nip55-signer-discovery.md`
- Primal compatibility: `nip55-signer-discovery.md#4-primal-compatibility-matrix`
