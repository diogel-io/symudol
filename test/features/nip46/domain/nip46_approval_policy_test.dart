import 'package:android_diogel/features/nip46/domain/nip46_approval_policy.dart';
import 'package:android_diogel/features/nip46/domain/nip46_method.dart';
import 'package:android_diogel/features/nip46/domain/nip46_permission_scope.dart';
import 'package:android_diogel/features/nip46/domain/nip46_session.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = Nip46ApprovalPolicy();
  const _pubkey =
      'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';
  const _clientPubkey =
      'b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2';

  Nip46Session _activeSession({
    List<Nip46PermissionScope> scopes = const [],
    Nip46SessionStatus status = Nip46SessionStatus.active,
  }) {
    return Nip46Session(
      id: 'sess-1',
      clientPubkey: _clientPubkey,
      remoteSignerPubkey: _pubkey,
      remoteSignerPrivkey: '0' * 64,
      relays: const ['wss://relay.example.com'],
      grantedScopes: scopes,
      status: status,
      createdAt: DateTime(2026),
    );
  }

  group('vault gate', () {
    test('locked vault → RequireUnlock regardless of method', () {
      expect(
        policy.decide(
          method: Nip46Method.getPublicKey,
          session: _activeSession(),
          vaultState: const VaultLocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46RequireUnlock>(),
      );
    });

    test('no active identity → RequireUnlock', () {
      expect(
        policy.decide(
          method: Nip46Method.ping,
          session: _activeSession(),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: null,
        ),
        isA<Nip46RequireUnlock>(),
      );
    });
  });

  group('session status', () {
    test('revoked session → AutoReject', () {
      expect(
        policy.decide(
          method: Nip46Method.getPublicKey,
          session: _activeSession(status: Nip46SessionStatus.revoked),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoReject>(),
      );
    });

    test('pending session + non-connect method → AutoReject', () {
      expect(
        policy.decide(
          method: Nip46Method.signEvent,
          session: _activeSession(status: Nip46SessionStatus.pending),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoReject>(),
      );
    });
  });

  group('auto-allowed methods on active session', () {
    for (final method in [
      Nip46Method.ping,
      Nip46Method.getPublicKey,
      Nip46Method.getRelays,
      Nip46Method.switchRelays,
      Nip46Method.logout,
    ]) {
      test('${method.wireName} is always auto-allowed', () {
        expect(
          policy.decide(
            method: method,
            session: _activeSession(),
            vaultState: const VaultUnlocked(),
            activeIdentityPubkey: _pubkey,
          ),
          isA<Nip46AutoAllow>(),
        );
      });
    }
  });

  group('sign_event', () {
    test('broad grant (sign_event, kind=null) → AutoAllow', () {
      // User explicitly pre-approved all event kinds; policy auto-allows.
      final result = policy.decide(
        method: Nip46Method.signEvent,
        session: _activeSession(scopes: [const Nip46SignEventScope()]),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: _pubkey,
      );
      expect(result, isA<Nip46AutoAllow>());
    });

    test(
        'kind-scoped grant only → RequireReview without canRemember '
        '(policy cannot verify kind without event template)', () {
      // A kind-1 grant cannot be matched at policy level because the policy
      // receives the method only, not the event template. The controller
      // handles kind-specific checks at dispatch time.
      final result = policy.decide(
        method: Nip46Method.signEvent,
        session: _activeSession(scopes: [const Nip46SignEventScope(1)]),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: _pubkey,
      );
      expect(result, isA<Nip46RequireReview>());
      expect((result as Nip46RequireReview).canRemember, isFalse);
    });

    test('no sign_event grant → RequireReview without canRemember', () {
      final result = policy.decide(
        method: Nip46Method.signEvent,
        session: _activeSession(),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: _pubkey,
      );
      expect(result, isA<Nip46RequireReview>());
      expect((result as Nip46RequireReview).canRemember, isFalse);
    });
  });

  group('decrypt operations', () {
    test('nip04_decrypt without grant → RequireReview', () {
      expect(
        policy.decide(
          method: Nip46Method.nip04Decrypt,
          session: _activeSession(),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46RequireReview>(),
      );
    });

    test('nip04_decrypt with matching grant → AutoAllow', () {
      expect(
        policy.decide(
          method: Nip46Method.nip04Decrypt,
          session: _activeSession(scopes: [const Nip46Nip04DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip44_decrypt grant satisfies decrypt_zap_event', () {
      expect(
        policy.decide(
          method: Nip46Method.decryptZapEvent,
          session: _activeSession(scopes: [const Nip46Nip44DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip04_decrypt grant satisfies decrypt_zap_event', () {
      expect(
        policy.decide(
          method: Nip46Method.decryptZapEvent,
          session: _activeSession(scopes: [const Nip46Nip04DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip44_encrypt without grant → RequireReview', () {
      expect(
        policy.decide(
          method: Nip46Method.nip44Encrypt,
          session: _activeSession(),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46RequireReview>(),
      );
    });

    test('nip44_encrypt with grant → AutoAllow', () {
      expect(
        policy.decide(
          method: Nip46Method.nip44Encrypt,
          session: _activeSession(scopes: [const Nip46Nip44EncryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: _pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });
  });
}
