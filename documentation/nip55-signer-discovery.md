# NIP-55 Signer Discovery — Engineering Decision Record

## Status

Approved. This record supersedes the impossible acceptance criteria in
`requirements/functional/nip55-signer-discovery.md` and documents the
platform-correct engineering interpretation.

---

## 1. NIP-55 Intended Discovery Flow

NIP-55 defines a two-step discovery contract for Android clients:

1. **Intent query** — the client calls
   `PackageManager.queryIntentActivities(Intent(ACTION_VIEW, Uri.parse("nostrsigner:")), 0)`
   to find all installed NIP-55 signers. Each result includes the signer's
   `applicationInfo.packageName`.

2. **Provider URI construction** — the client builds ContentProvider URIs using
   the resolved package name: `content://<signerPackage>.<METHOD>`. For example,
   after discovering `io.threenine.diogel`, the client uses
   `content://io.threenine.diogel.SIGN_EVENT`.

This flow means **neither the signer nor the client needs to know each other's
package name in advance**. The client discovers it at runtime.

---

## 2. Diogel Production Identity

| Property | Value |
|----------|-------|
| Application ID | `io.threenine.diogel` |
| Provider authority prefix | `io.threenine.diogel.` |
| Method authorities | `io.threenine.diogel.SIGN_EVENT`, `io.threenine.diogel.GET_PUBLIC_KEY`, etc. |
| `nostrsigner:` intent filter | Declared in `Nip55BridgeActivity`, exported, with `DEFAULT` and `BROWSABLE`. |

The production application ID must remain `io.threenine.diogel`. It is not
negotiable. Diogel is a distinct app with its own identity, security model, and
update channel.

---

## 3. Platform Constraints — Why Amber Aliases Cannot Work in Production

### 3a. Provider Authority Aliases Do Not Satisfy PackageManager Package Checks

Android ContentProvider authorities are routing strings, not package identifiers.
Declaring `com.greenart7c3.nostrsigner.SIGN_EVENT` as an authority in Diogel's
manifest makes `ContentResolver.query(Uri.parse("content://com.greenart7c3.nostrsigner.SIGN_EVENT"), ...)` route to Diogel's `Nip55ContentProvider`. However:

- `PackageManager.getPackageInfo("com.greenart7c3.nostrsigner", 0)` still fails
  (throws `NameNotFoundException`) because **provider authorities are not package
  names**. Android resolves `getPackageInfo` by application ID, not by content
  authority strings.
- Any client that first checks whether Amber is installed via `getPackageInfo`
  before building provider URIs will never reach the alias provider in Diogel.

**Primal's `ClientSignerUtils.isCompatibleAmberVersionInstalled()`** does exactly
this — it calls `getPackageInfo("com.greenart7c3.nostrsigner", 0)`. This check
will fail for Diogel regardless of which provider authorities Diogel declares.

### 3b. Package-Targeted Intents Cannot Resolve to Diogel's Normal Package

When a client issues `intent.package = "com.greenart7c3.nostrsigner"`, Android's
intent resolution only searches for matching activities in the named package. An
activity in `io.threenine.diogel` cannot be found by a package-targeted intent
for `com.greenart7c3.nostrsigner`. There is no manifest declaration, alias, or
shim that can bridge this — it is an Android platform invariant.

**Primal's `AmberLauncher.kt`** sets `intent.package = "com.greenart7c3.nostrsigner"`
on all its Intent-based flows (login picker, `sign_event` via Intent). These
intents will never resolve to Diogel in a normal install.

### 3c. Amber Authority Aliases Conflict with Amber When Both Apps Are Installed

Android enforces that each ContentProvider authority is globally unique across
all installed apps. If Diogel declares `com.greenart7c3.nostrsigner.SIGN_EVENT`
and the real Amber is also installed, Android's package installer will refuse to
install one of them (the second installer raises an `INSTALL_FAILED_CONFLICTING_PROVIDER` error).

This means a build with Amber authority aliases is **mutually exclusive** with
the real Amber app. It cannot ship as the default production build because it
would break users who have both apps installed.

---

## 4. Primal Compatibility Matrix

| Primal behaviour | Stock Diogel result | Root cause |
|------------------|---------------------|------------|
| `getPackageInfo("com.greenart7c3.nostrsigner")` | **Fails** (NameNotFoundException) | Diogel's application ID is `io.threenine.diogel`. Provider authorities are not package IDs. |
| `content://com.greenart7c3.nostrsigner.SIGN_EVENT` query | **Fails** in stock Diogel | Diogel does not declare Amber's provider authorities. |
| `intent.package = "com.greenart7c3.nostrsigner"` | **Does not resolve** to Diogel | Package-targeted intents only search the named package. |
| `queryIntentActivities(ACTION_VIEW, "nostrsigner:")` | **Finds Diogel** ✅ | Diogel exports `Nip55BridgeActivity` with the `nostrsigner:` intent filter. |
| `content://io.threenine.diogel.SIGN_EVENT` (post-discovery) | **Works** ✅ | Standard NIP-55 authority convention after intent discovery. |

**Conclusion**: stock Primal cannot discover stock Diogel through the current
Amber-specific path. Primal's integration is gated on three Amber-specific checks
(package name, authority prefix, package-targeted intent) that cannot be satisfied
by a differently-packaged app without impersonating Amber.

---

## 5. Optional Amber Provider Authority Compatibility Build

A separate build variant can declare Amber provider authorities. This build:

- Is gated behind a build flavor or source-set manifest overlay.
- Is documented as mutually exclusive with Amber being installed on the same device.
- Does not change the production application ID.
- Does not make `PackageManager.getPackageInfo("com.greenart7c3.nostrsigner")`
  succeed (that check still fails — only the ContentProvider routing changes).
- Does not make package-targeted intents resolve to Diogel.

This workstream is **not implemented in the default production build**. Product
approval is required before adding it to any release workflow. See the
implementation pack at
`../architecture/nip55-signer-discovery-implementation-pack.md` for the
technical approach.

---

## 6. Version Code Audit

Primal's `ClientSignerUtils` checks `packageInfo.longVersionCode >= 115`
(`COMPATIBLE_AMBER_VERSION_CODE`). This check:

- Is performed **after** `getPackageInfo("com.greenart7c3.nostrsigner")`.
- Has no bearing on Diogel's production versionCode because the package check
  already fails for `io.threenine.diogel`.
- Is relevant only if a compatibility build with `applicationId = "com.greenart7c3.nostrsigner"`
  is ever shipped — that build would need `versionCode >= 115`.

**Diogel's production versionCode must not be changed solely to satisfy Primal's
Amber version check.** Any versionCode changes are driven by normal release
management, not by Amber compatibility.

---

## 7. Upstream Recommendation for Primal

The following can be submitted as a GitHub issue or discussion to Primal:

> **Recommended change**: replace the Amber-specific signer detection in
> `ClientSignerUtils.isCompatibleAmberVersionInstalled()` and
> `AmberContentResolver`/`AmberLauncher` with standard NIP-55 signer discovery:
>
> 1. Query `PackageManager.queryIntentActivities(Intent(ACTION_VIEW, Uri.parse("nostrsigner:")), 0)`.
> 2. Present the user with all discovered signers (or use the previously selected one).
> 3. Store the selected signer's `packageName`.
> 4. Build ContentProvider URIs as `content://<signerPackage>.<METHOD>`.
> 5. Target Intents with `intent.package = signerPackage`.
> 6. Keep the Amber-specific default path (and version check) for the case where
>    the user has not selected a signer or where Amber is the only installed signer.
>
> This change enables Primal to work with any NIP-55-compliant signer, including
> Diogel, without any signer-specific code in Primal.

---

## 8. Manual Verification

After installing Diogel on a device or emulator, run these `adb` commands to
verify intent discovery works:

```sh
# List all apps that handle nostrsigner: — Diogel should appear
adb shell cmd package query-intent-activities -a android.intent.action.VIEW -d nostrsigner:

# Confirm Diogel resolves the nostrsigner: intent
adb shell cmd package resolve-activity -a android.intent.action.VIEW -d nostrsigner: -p io.threenine.diogel

# Test the PING capability probe via ContentProvider
adb shell content query --uri content://io.threenine.diogel.PING

# Confirm Amber package-targeted intent does NOT resolve to Diogel (negative check)
adb shell cmd package resolve-activity -a android.intent.action.VIEW -d nostrsigner: -p com.greenart7c3.nostrsigner
```

The positive checks pass when the resolved activity package is
`io.threenine.diogel` and the activity name is `Nip55BridgeActivity`.

The negative check passes when no activity is resolved (Diogel is not Amber).

---

## 9. Links

- Implementation pack: `../architecture/nip55-signer-discovery-implementation-pack.md`
- Functional requirement: `../requirements/functional/nip55-signer-discovery.md`
- Client discovery reference: `nip55-client-discovery-reference.md`
- ContentProvider MVP scope: `nip55-contentprovider-mvp.md`
- Compatibility report: `../../../../../30-research/nostr/reference-implementations/android/compatibility-report.md`
