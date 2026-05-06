# Development Guidelines - Android Diogel

This document provides project-specific information for advanced developers working on the Android Diogel project.

## Build and Configuration

### Environment Setup
- **Flutter SDK**: Ensure you have the Flutter SDK installed (compatible with version defined in `pubspec.yaml`).
- **Dependencies**: Run `flutter pub get` to fetch all necessary packages.
- **Android/iOS Setup**: Standard Flutter platform setup applies. Note that this project uses `flutter_secure_storage` which may require specific platform-level configurations for Keychain (iOS) or Keystore (Android).

### Key Dependencies
- **Riverpod**: Used for state management and dependency injection.
- **dart_nostr**: Core library for Nostr protocol interactions.
- **flutter_secure_storage**: Used for sensitive data storage (Vault).

## Testing

### Running Tests
To run all tests:
```bash
flutter test
```

To run a specific test file:
```bash
flutter test test/features/identity/domain/vault_identity_test.dart
```

### Test Structure
- **Unit Tests**: Located in `test/`, mirroring the `lib/` structure.
- **Widget Tests**: Located alongside feature tests, using `flutter_test`.
- **Fakes**: Located in `test/fakes/` for mocking dependencies like `VaultStore`.

### Adding New Tests
When adding new features, follow the existing pattern of creating a corresponding test file in the `test/` directory. For features involving the Vault, use `FakeVaultStore` to avoid side effects and platform dependencies.

### Demonstration Test Example
A simple unit test for `VaultIdentity`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:android_diogel/features/identity/domain/vault_identity.dart';

void main() {
  test('VaultIdentity equality is based on publicKey', () {
    final id1 = VaultIdentity(
      localId: '1',
      publicKey: 'pub-key-1',
      createdAt: DateTime.now(),
      origin: IdentityOrigin.generated,
    );
    final id2 = VaultIdentity(
      localId: '2',
      publicKey: 'pub-key-1',
      createdAt: DateTime.now(),
      origin: IdentityOrigin.imported,
    );

    expect(id1, equals(id2));
  });
}
```

## Development Information

### Code Style and Architecture
- **Feature-first Layered Architecture**: The project is organized by features (e.g., `identity`, `vault`, `unlock`). Each feature typically contains:
  - `domain/`: Entities and service interfaces.
  - `application/`: State management (Riverpod providers/controllers).
  - `data/`: Implementations of repository/store interfaces.
  - `presentation/`: UI components and screens.
- **Linting**: Follow the rules defined in `analysis_options.yaml`. Run `flutter analyze` to check for issues.
- **Immutability**: Prefer `const` constructors and immutable data classes (using `copyWith` patterns) where possible.
- **State Management**: Use `StateNotifier` (or `AsyncNotifier`) with Riverpod for predictable state transitions.

### Debugging Tips
- Check `flutter_secure_storage` logs if vault initialization fails.
- The `fix_emulators.sh` script is available in the root to troubleshoot Android emulator locking issues.

### NOS Protocol
- **Nostr Protocol**:  The project uses the `dart_nostr` library for Nostr interactions.
- **Nostr Event Handling**: Events are processed asynchronously to ensure smooth UI updates and prevent blocking the main thread.
- **Nostr Relay Management**: The application supports multiple Nostr relays for redundancy and load balancing.

The list of relevant NIPs:
- [NIP 01](https://github.com/nostr-protocol/nips/blob/master/01.md) - Basic protocol flow description
- [NIP- 55](https://github.com/nostr-protocol/nips/blob/master/55.md) - Android Signer Application

- [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md): Encrypted Payloads (Versioned), used by the signer for encryption/decryption operations.

- [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md): Nostr Remote Signing, which provides a remote signing protocol, though NIP-55 is the native Android local solution. 
    
- [NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md): Private Key Encryption, which may be relevant for key storage and management within the signer app.
  


### Core Android IPC docs

1.  Intents and intent filters
   - https://developer.android.com/guide/components/intents-filters
   - Key point: Android Intent is the normal message object for asking another app/component to do something.
   - Relevant to Diogel:
   - `nostrsigner`: is a custom URI scheme handled through an `ACTION_VIEW` intent.
   - Client App launches Diogel by intent.
   - Diogel returns data via activity result / result extras.
2. Get a result from an activity
   - https://developer.android.com/training/basics/intents/result
   - Key point: modern Android result flow uses registerForActivityResult / ActivityResultContracts.StartActivityForResult.
   - Relevant to Diogel:
   - This is the proper client-side model for “launch signer UI, wait for result”.
3. Deep links / custom URI schemes
   - https://developer.android.com/training/app-links/create-deeplinks
   - Key point: custom URI handling requires an intent filter with ACTION_VIEW, DEFAULT, usually BROWSABLE, and <data android:scheme="...">.
   - Relevant to Diogel:
   - Diogel’s nostrsigner intent filter is exactly this kind of deep-link/custom-scheme entry point.
4. Content provider basics
   - https://developer.android.com/guide/topics/providers/content-provider-basics
   - Key point: clients call ContentResolver.query(...); Android dispatches that IPC call to the matching app’s ContentProvider.query(...).
   - Relevant to Diogel:
   - NIP-55 uses this for background/warm-session signing/encryption/decryption when permission is already remembered.
   - This avoids launching UI for every operation.
5. ContentProvider API reference
   - https://developer.android.com/reference/android/content/ContentProvider
   - Key point: ContentProvider.getCallingPackage() identifies the package making the current provider call.
   - Relevant to Diogel:
   - Diogel should use caller package/certificate for permission decisions.
   - Provider calls are IPC; Android forwards calls across processes.
6. <provider> manifest element
   - https://developer.android.com/guide/topics/manifest/provider-element
   - Key point: provider authorities are declared in the manifest.
   - Relevant to Diogel:
   - io.threenine.diogel.SIGN_EVENT, ...GET_PUBLIC_KEY, ...PING, etc. are provider authorities.
   - If an authority is missing or mismatched, ContentResolver.query(content://...) won’t reach Diogel.
7. Package visibility filtering
   - https://developer.android.com/training/package-visibility
   - Key point: Android 11+ limits which other apps/packages a client can discover unless declared in <queries>.
   - Relevant to Diogel/clients:
   - NIP-55 clients need <queries> for nostrsigner if they want to detect installed signers with queryIntentActivities.
8. Background activity launch restrictions
   - https://developer.android.com/guide/components/activities/background-starts
   - Key point: Android 10+ restricts apps starting activities from the background; Android 14/15 tightened this further.
   - Relevant to our logcat:
   - The Background activity launch blocked / `BAL_BLOCK` entries are explained by this.
   - If Client App or Diogel tries to launch signer UI from an invalid background context, Android may block it, causing signer timeouts.

#### NIP-55-specific docs

9. NIP-55 — Android Signer Application
   - https://nips.nostr.com/55
   - This is the most directly relevant spec.
   - Key points:
   - NIP-55 explicitly says Android signers use:
   - Intents for manual accept/reject flows.
   - ContentResolver / ContentProvider for automatic/background decisions when already allowed.
   - get_public_key is the initial connection flow.
   - Client saves signer package + pubkey and should avoid repeating get_public_key.
   - Content resolver returns null when not remembered/allowed.
   - Rejected provider result uses a rejected column.
   - sign_event returns result and event.
   - Other crypto methods return result.
   - nostrsigner: intent = manual UI approval path.
   - content://io.threenine.diogel.GET_PUBLIC_KEY etc. = provider/warm-session path.
   - ContentProvider.getCallingPackage() = how Diogel identifies the calling app.
   - AndroidManifest.xml authorities = what clients can query.
   - BAL_BLOCK logs = Android refusing background UI launch.
   - Passing Flutter tests alone means little unless tests cover these exact IPC contracts.