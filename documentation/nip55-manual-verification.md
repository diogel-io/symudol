# NIP-55 Manual Verification

These checks require an Android emulator/device with Diogel installed and an unlocked vault/active identity unless the scenario says otherwise.

Replace `<active-pubkey>` with the active Diogel identity public key.

## 1. `get_public_key` while unlocked

```bash
adb shell am start \
  -a android.intent.action.VIEW \
  -d 'nostrsigner:' \
  --es type get_public_key \
  io.threenine.diogel
```

Expected UI:

- Diogel opens the public-key request screen.
- Source is shown as a source hint, not verified identity.
- Unknown provenance warning remains visible.
- Approve/reject actions are visible.

Expected caller result:

- Approve returns `RESULT_OK` with `result=<active-pubkey>` and `package=io.threenine.diogel`.
- Reject returns non-OK.

## 2. `sign_event` while unlocked

```bash
adb shell am start \
  -a android.intent.action.VIEW \
  -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A%22hello%20from%20nip55%22%2C%22tags%22%3A%5B%5D%7D' \
  --es type sign_event \
  --es id test-event-1 \
  --es current_user <active-pubkey> \
  io.threenine.diogel
```

Expected UI:

- Diogel opens the signing request review.
- The source appears as a source hint and verification is not implied.
- Unknown provenance warning appears.
- “Event draft JSON” shows the normalized event draft Diogel will sign.

Expected caller result:

- Approve returns `RESULT_OK` with `result=<signature>`, `id=test-event-1`, and `event=<signed event JSON>`.
- The signed event JSON includes `id`, `pubkey`, `created_at`, `kind`, `tags`, `content`, and `sig`.

## 3. `sign_event` while locked, then unlock

Lock Diogel, then run the same `sign_event` command.

Expected UI:

- Diogel opens on the unlock screen.
- Unlock screen explains an external Android app is waiting for NIP-55 review.
- After unlocking, Diogel resumes to the signing request review.

Expected caller result:

- Approve returns the normal signed event result.
- Reject returns non-OK.

## 4. Locked request cancel

While the locked request is waiting on the unlock screen, tap **Cancel external request**.

Expected:

- External caller receives non-OK with a safe cancellation error.
- Diogel clears the pending NIP-55 request.

## 5. Locked request timeout

The app currently times out a locked pending NIP-55 request after roughly five minutes.

Expected:

- If the vault is not unlocked before timeout, Diogel rejects the pending native request with a safe timeout error.
- No signing occurs.

## 6. Signer failure / malformed payload

```bash
adb shell am start \
  -a android.intent.action.VIEW \
  -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A42%2C%22tags%22%3A%5B%5D%7D' \
  --es type sign_event \
  --es id malformed-content \
  --es current_user <active-pubkey> \
  io.threenine.diogel
```

Expected:

- Diogel shows/rejects the invalid signing request safely.
- External caller receives non-OK/safe failure.
- The failed NIP-55 request does not block later active requests.

## 7. Event `pubkey` mismatch

```bash
adb shell am start \
  -a android.intent.action.VIEW \
  -d 'nostrsigner:%7B%22kind%22%3A1%2C%22pubkey%22%3A%22bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb%22%2C%22content%22%3A%22bad%20pubkey%22%2C%22tags%22%3A%5B%5D%7D' \
  --es type sign_event \
  --es id pubkey-mismatch \
  --es current_user <active-pubkey> \
  io.threenine.diogel
```

Expected:

- Diogel rejects the request before signing.
- External caller receives non-OK/safe failure.

## 8. `current_user` mismatch

```bash
adb shell am start \
  -a android.intent.action.VIEW \
  -d 'nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A%22wrong%20account%22%2C%22tags%22%3A%5B%5D%7D' \
  --es type sign_event \
  --es id current-user-mismatch \
  --es current_user bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  io.threenine.diogel
```

Expected:

- Diogel rejects with “Requested account does not match active identity.”
- No signing occurs.

## 9. Second native intent while first is active

Diogel is strict single-flight for interactive NIP-55 requests. `Nip55BridgeActivity` owns each caller result, so a second native caller can be rejected as busy without finishing or poisoning the active caller.

Expected current behavior:

- First request remains protected and can complete normally with its original `id`/result pairing.
- Second request receives a deterministic busy rejection: “Diogel is already reviewing another NIP-55 request”.
- No `results` batch array is returned because true batching is intentionally unsupported for now.

See `documentation/nip55-batch-and-single-flight-decision.md` for the WP10 decision.
