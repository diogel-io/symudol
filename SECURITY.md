# Security Policy

Symudol holds Nostr private keys on the phone and signs, encrypts and decrypts with them for the
apps and remote clients the user allows. This file explains how to report a vulnerability and what
counts as one. The threat model behind it, with Symudol's assets, trust boundaries, controls and
known limits, is [documentation/threat-model.md](documentation/threat-model.md).

## Reporting a vulnerability

**Do not open a public issue, discussion, or pull request for a suspected vulnerability.**

Report it privately:

1. **Preferred:** use GitHub private vulnerability reporting. Open the repository's
   [Security tab](https://github.com/diogel-io/symudol/security) and choose **Report a
   vulnerability**.
2. **Alternative:** email support@threenine.co.uk with "Symudol security" in the subject.

Please include:

- the Symudol version or commit, the build type (release, profile or debug), and the device and
  Android version;
- the steps to reproduce, and what you expected to happen instead;
- the impact: what an attacker gains and what they need first, such as an installed app, physical
  access, or a relay;
- a proof of concept if you have one. Never use a real private key in a report; generate a
  throwaway identity.

What to expect:

| Step | Target |
|------|--------|
| Acknowledgement | Within 3 working days |
| Triage | Within 10 working days: we confirm or decline, and agree a severity |
| Fix and release | As fast as the severity needs; we keep you informed until it ships |
| Disclosure | A GitHub security advisory when the fix is released, by default within 90 days of the report |

We credit reporters in the advisory unless you ask us not to. Please give us the chance to release a
fix before you disclose publicly.

## Supported versions

Symudol has not been released yet: until `v1.0.0`, fixes land on `master`. From the first release
on, only the newest release receives security fixes, as a new release; see
[documentation/releasing.md](documentation/releasing.md).

| Version | Supported |
|---------|-----------|
| Newest release (from `v1.0.0`) | Yes |
| `master`, before the first release | Yes |
| Any earlier release | No |

## Scope

In scope: anything that defeats a Symudol control in the threat model, for example

- a private key, the PIN, or vault contents leaving the vault, the app, or the device;
- a signature, encryption or decryption without the user's decision or a remembered one;
- one app, or one remote client, acting as another, or using a decision made for another;
- what the approval screen shows differing from what is signed, encrypted or decrypted;
- a remembered decision outliving its scope, its timeframe, or the vault lock;
- secrets reaching logs, the clipboard beyond its limits, backups, or the network;
- getting past the PIN lockout or biometric unlock rules.

Out of scope:

- a device that is rooted, or whose owner has already unlocked Symudol for the attacker;
- the known limits and accepted risks in the threat model, unless you show they are worse than
  stated;
- iOS, which is not released and not yet modelled (threat model, section 9);
- vulnerabilities in relays or Nostr apps themselves, rather than in how Symudol uses them.

If you are unsure, report it anyway.

## Security review guidelines

A pull request that touches a sensitive path must pass this review before it merges. T and B
numbers refer to [the threat model](documentation/threat-model.md).

### Sensitive paths

A change to any of these needs the security review:

- `android/app/src/main/kotlin/io/diogel/symudol/`, all of it: the NIP-55 bridge, ContentProvider, handoff, router, permission mirror,
  native crypto, NIP-46 links and service, biometric vault, logging and clipboard
- `lib/features/vault/`, `lib/features/unlock/`, `lib/features/backup/` and
  `lib/features/accounts/` (key export)
- `lib/features/nip55/`, `lib/features/nip46/`, `lib/features/signing/` and
  `lib/features/requests/`, which decide, present and carry out requests
- `lib/app/diogel_log.dart`, `lib/app/sensitive_selection.dart` and `lib/app/system_picker.dart`
- `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/`,
  `android/app/proguard-rules.pro` and `android/app/build.gradle.kts`
- `pubspec.yaml`, `pubspec.lock` and `.github/workflows/*`
- `SECURITY.md`, `documentation/threat-model.md` and `documentation/releasing.md`, which define the
  controls, this review, and the release steps
- anything else that touches cryptography, key material, persistence, or what another app or
  client may ask for

### Checklist

**Caller identity**

- [ ] A NIP-55 caller is identified only by what Android attests, its calling package and signing
      certificate, never by anything the calling app supplies (B1, B2).
- [ ] A remembered decision matches only the package, certificate, identity, method and kind it was
      saved for, and only within its timeframe (T1–T5).
- [ ] An answer goes only to the request that asked for it (B3).
- [ ] A NIP-46 request is accepted only from its session's client, and a session is created only
      after the user approves it (T17–T21).

**Consent**

- [ ] Nothing is signed, encrypted or decrypted without the user's decision on the approval screen
      or a remembered decision, and never while the vault is locked.
- [ ] What is signed is exactly what the approval screen showed, for the identity it showed.
- [ ] A broad "allow everything" grant still approves nothing by itself.

**Secrets**

- [ ] No key or PIN reaches logs, crash reports, the network, or a backup. Plaintext, event
      content and ciphertext reach none of these either, except the network for the operation the
      user approved (such as a signed event or NIP-46 response sent to its relays). Logging goes
      only through `DiogelLog` and `diogelLog` (T11).
- [ ] The native key copy is cleared on lock and never outlives the unlock (T6).
- [ ] Secrets copied to the clipboard are marked sensitive, and a copied nsec is cleared (T13).
- [ ] Backup and device transfer stay off for app data (B5, T12).

**Manifest and permissions**

- [ ] No new exported component, intent filter, provider authority or permission without a
      recorded decision linked from the pull request.

**Dependencies and build**

- [ ] Every new dependency is justified in the pull request and the `pubspec.lock` change is
      reviewed.
- [ ] Release builds still strip debug logging (`proguard-rules.pro`), and workflow changes keep
      secrets out of logs.

**Tests**

- [ ] Each new or changed control has a negative test: another caller or certificate, a locked
      vault, an expired or unknown request, a kind not granted, or a secret that must not appear.

**Threat model**

- [ ] [documentation/threat-model.md](documentation/threat-model.md) is updated in the same pull
      request when the change adds or changes an asset, a trust boundary, or a control. An open,
      exploitable weakness appears there only after its fix ships; until then it is reported
      privately, as above.

### Recording the review

1. The pull request description has a **Security review** section. For a change to a sensitive
   path, it works through this checklist, marking any item that does not apply. A change that
   touches no sensitive path says so instead.
2. The reviewer confirms the checklist. Any item the change cannot meet needs a recorded decision
   linked from the pull request, and the decision comes first.
3. Agents apply the same checklist: the Diogel workspace's `review-pr` and `diogel-code-review`
   skills check it for any Symudol pull request that touches a sensitive path.
4. A release pull request is the exception: its **Security review** section records only that the
   release's security review is complete, at which head commit, and its outcome, as
   [documentation/releasing.md](documentation/releasing.md#cutting-a-release) describes. The
   checklist evidence for a release is in that private review.

Each release also has a security review before its release PR merges; see
[documentation/releasing.md](documentation/releasing.md#cutting-a-release).
