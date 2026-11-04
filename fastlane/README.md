# Google Play listing

`metadata/android/en-GB/` is Symudol's Google Play store listing (#39). See
`documentation/releasing.md` for what each file is and its Play Console limit.

## Screenshots

`metadata/android/en-GB/images/phoneScreenshots/` holds six screens, captured 2026-11-04 on the
`Pixel_Stable_API35` emulator (1080×2400) in dark mode, with the status bar in demo mode.

| File | Shows |
| --- | --- |
| `1-approval.png` | A kind-1 `sign_event` request |
| `2-approval-details.png` | The same request with **Show details** expanded |
| `3-accounts.png` | Accounts, with two sample identities |
| `4-trusted-apps.png` | Trusted Nostr apps, with one remembered decision |
| `5-unlock.png` | Unlock Vault |
| `6-settings.png` | Settings: Security |

How they were taken, and the rules for a recapture:

- **Real screens only**, from a release build (`flutter build apk --release`) of the listing branch.
  Nothing is mocked or edited, except that each side is widened by 60 pixels of the screen's own
  edge colour. Play rejects a screenshot whose long side is more than twice its short side, and
  1080×2400 is 2.22.
- **`FLAG_SECURE` was off for the capture only.** Symudol blanks every screenshot
  (`documentation/backup-and-screen-capture-decision.md`), so the capture build had the
  `window.setFlags(... FLAG_SECURE ...)` line in `MainActivity.onCreate` commented out. That change
  was never committed, and the capture build was uninstalled afterwards.
- **Throwaway identities and PIN.** Both identities were created for the capture and discarded.
- **Requests from `tools/nip55-test-client`**, not a third-party app, so that the listing shows no
  other app's name or icon. The request was signed for the test client only; nothing was published.

Export each screen as a 24-bit PNG without transparency:

```bash
magick \( shot.png -crop 1x2400+0+0 +repage -scale 60x2400! \) shot.png \
  \( shot.png -crop 1x2400+1079+0 +repage -scale 60x2400! \) +append \
  -alpha off -define png:color-type=2 N-name.png
```
