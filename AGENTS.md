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