import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';

void main() {
  group('VaultState', () {
    test('can instantiate NoVault', () {
      const state = NoVault();
      expect(state, isA<VaultState>());
      expect(state, isA<NoVault>());
    });

    test('can instantiate VaultLocked', () {
      const state = VaultLocked();
      expect(state, isA<VaultState>());
      expect(state, isA<VaultLocked>());
    });

    test('can instantiate VaultUnlocked', () {
      const state = VaultUnlocked();
      expect(state, isA<VaultState>());
      expect(state, isA<VaultUnlocked>());
    });

    test('can instantiate SessionExpired', () {
      const state = SessionExpired();
      expect(state, isA<VaultState>());
      expect(state, isA<SessionExpired>());
    });

    test('pattern matching works for VaultState', () {
      const VaultState state = VaultLocked();
      
      final message = switch (state) {
        NoVault() => 'none',
        VaultLocked() => 'locked',
        VaultUnlocked() => 'unlocked',
        SessionExpired() => 'expired',
      };

      expect(message, 'locked');
    });
  });
}
