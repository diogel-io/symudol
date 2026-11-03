# NIP-46 Client Interoperability

Status: active

Tracking issue: diogel-io/symudol#30

This is the repeatable procedure for checking Symudol as a NIP-46 remote signer against real
clients, and the record of the latest run. The unit tests in `test/features/nip46/` cover
Symudol's side of the protocol; this covers what only real clients and real relays can show.

NIP-46 is hidden in release builds for Android 1.0 (#26), so use a debug or profile build.

## What Symudol Does

Against the NIP-46 text in the Diogel workspace's NIPs reference (`46.md`):

| Behaviour | Symudol |
|---|---|
| Pairing (#31) | Shows the `bunker://` token as a QR code and as text. Scans a client's `nostrconnect://` QR code with the camera, or takes a pasted URI. On Android, opens from a tapped `nostrconnect:` link; a link that arrives while the vault is locked waits in memory for the unlock. Every route ends at the same approval. A `nostrconnect://` URI's relays must be `wss://` (`ws://` too in debug and profile builds), at most 8, and are opened only once the user approves, so a rejected or ignored link never reaches the network. A URI from a client that is already connected is refused. |
| `bunker://` connect | Checks the token's secret, asks the user, and replies `ack` to the client's request id. A secret is used once. |
| `nostrconnect://` connect | Asks the user, then sends a connect response whose `result` is the URI's `secret`, with a fresh request id. |
| `connect` from an approved client | Replies `ack` without asking again and keeps the session's grants. |
| Events from any other key | Dropped once the session knows its client. |
| `switch_relays` | Replies `null`: Symudol has no relay preference of its own yet, so the session's relays stand. |
| NIP-42 relay AUTH | Answered with a kind 22242 event signed by the session key, never the user's key. The subscription is renewed, and an event refused with `auth-required:` is sent again. |
| `auth_url` challenges | Not sent. They are for signers that authenticate the user elsewhere; Symudol asks in the app. |
| Subscriptions | The first subscription asks for kind 24133 events since five minutes before the session was last used (or connected, or created). Each refresh and reconnect closes the old subscription and asks since five minutes before it. After AUTH, the subscription starts again from the first cursor. |
| Lost connections | Reconnect with back-off from 2 s to 60 s, a 10 s connect timeout and 30 s pings, and at once when the app returns to the foreground. The back-off resets only after a connection stays up for 30 s. |
| Failing relays | Skipped for two minutes after ten refusals in a row, then tried again. |

Requests that need review still time out until the review screen lands (#27), so this run covers
pairing, reconnecting, `get_public_key` and `switch_relays`. Add signing to
the matrix when #27 ships.

## Set Up

Use the emulator from `nip55-client-interop.md` and install a debug build of the commit under test:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
git rev-parse --short HEAD
```

Create a vault with a throwaway identity. Never use a real key or a real account for these checks.

Use each client on the web, in a desktop browser, with a fresh profile.

## Checks

Run each check with each client, and record pass, fail or not supported.

1. **Bunker pairing.** In Symudol, open Remote Signing and create a `bunker://` token. Log in to
   the client with it. Approve the connection. The client shows the throwaway account's profile.
2. **Nostrconnect pairing.** Start the client's "log in with a remote signer" or `nostrconnect://`
   flow and paste its URI into Symudol. Approve. The client accepts the connection, which means it
   validated the secret.
3. **Reconnect after a client restart.** Reload the client, or close and reopen it. It reconnects
   without a new approval in Symudol and without an error.
4. **Reconnect after a network drop.** With a session open, turn on flight mode on the emulator
   for a minute, then turn it off. The client's next request is answered once the relay
   reconnects. Allow 70 seconds for the first attempt (up to 60 s of back-off and a 10 s connect
   timeout); a failed attempt adds another back-off.
5. **Reconnect on resume.** Put Symudol in the background for a few minutes, bring it back, and
   make a request from the client. It is answered.
6. **`switch_relays`.** If the client sends it after connecting, the session keeps working on the
   same relays.
7. **Relay AUTH.** Pair using a relay that requires NIP-42 AUTH for kind 24133. Pairing and
   requests work, and the relay sees the session key in the AUTH event.
8. **Logout.** Log out of the client. If it sends `logout`, the session disappears from Symudol.
9. **Scan a client's code.** These need a phone, since the emulator's camera can't see the
   desktop screen. Start the client's `nostrconnect://` flow so it shows a QR code. In Symudol,
   open Remote Signing, tap +, choose Connect to a client and tap Scan QR code. Allow the camera.
   Approve. The client accepts the connection.
10. **Client scans Symudol's code.** Create a `bunker://` token in Symudol, and scan its QR code
    with the client's "log in with a remote signer" scanner, on a phone client or a laptop camera.
    Approve. The client shows the throwaway account.
11. **Tap a link.** On the phone, open the client in a mobile browser and use its `nostrconnect:`
    link or button. Symudol opens on the approval. Repeat with Symudol locked: it asks for the PIN
    first, then shows the approval. Then refuse the camera permission and check that Scan
    explains it and pasting still works.

## Latest Run

Not yet run for the #30 changes.

| Check | Coracle | Nostrudel |
|---|---|---|
| Client version | | |
| Symudol commit | | |
| 1. Bunker pairing | | |
| 2. Nostrconnect pairing | | |
| 3. Reconnect after a client restart | | |
| 4. Reconnect after a network drop | | |
| 5. Reconnect on resume | | |
| 6. `switch_relays` | | |
| 7. Relay AUTH | | |
| 8. Logout | | |
| 9. Scan a client's code | | |
| 10. Client scans Symudol's code | | |
| 11. Tap a link | | |
