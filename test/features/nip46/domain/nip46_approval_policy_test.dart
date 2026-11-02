import 'package:symudol/features/nip46/domain/nip46_approval_policy.dart';
import 'package:symudol/features/nip46/domain/nip46_method.dart';
import 'package:symudol/features/nip46/domain/nip46_permission_grant.dart';
import 'package:symudol/features/nip46/domain/nip46_permission_scope.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = Nip46ApprovalPolicy();
  const pubkey =
      'a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1';
  const clientPubkey =
      'b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2';

  final now = DateTime.utc(2026, 11, 2, 12);

  /// A remembered decision on [scope] for [identity] (the active one).
  Nip46PermissionGrant grant(
    Nip46PermissionScope scope, {
    Nip55PermissionDecision decision = Nip55PermissionDecision.allow,
    String identity = pubkey,
    DateTime? expiresAt,
  }) => Nip46PermissionGrant(
    scope: scope,
    decision: decision,
    identityPubkey: identity,
    createdAt: now,
    expiresAt: expiresAt,
  );

  /// [scopes] become allow grants for the active identity.
  Nip46Session activeSession({
    List<Nip46PermissionScope> scopes = const [],
    List<Nip46PermissionGrant> grants = const [],
    Nip46SessionStatus status = Nip46SessionStatus.active,
  }) {
    return Nip46Session(
      id: 'sess-1',
      clientPubkey: clientPubkey,
      remoteSignerPubkey: pubkey,
      remoteSignerPrivkey: '0' * 64,
      relays: const ['wss://relay.example.com'],
      grants: [...grants, for (final scope in scopes) grant(scope)],
      status: status,
      createdAt: DateTime(2026),
    );
  }

  Nip46ApprovalDecision signKind(Nip46Session session, int? kind) =>
      policy.decide(
        method: Nip46Method.signEvent,
        session: session,
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: pubkey,
        signEventKind: kind,
        now: now,
      );

  group('vault gate', () {
    test('locked vault → RequireUnlock regardless of method', () {
      expect(
        policy.decide(
          method: Nip46Method.getPublicKey,
          session: activeSession(),
          vaultState: const VaultLocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46RequireUnlock>(),
      );
    });

    test('no active identity → RequireUnlock', () {
      expect(
        policy.decide(
          method: Nip46Method.ping,
          session: activeSession(),
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
          session: activeSession(status: Nip46SessionStatus.revoked),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46AutoReject>(),
      );
    });

    test('pending session + non-connect method → AutoReject', () {
      expect(
        policy.decide(
          method: Nip46Method.signEvent,
          session: activeSession(status: Nip46SessionStatus.pending),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
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
            session: activeSession(),
            vaultState: const VaultUnlocked(),
            activeIdentityPubkey: pubkey,
          ),
          isA<Nip46AutoAllow>(),
        );
      });
    }
  });

  // Grants match by kind, and a broad request is reviewed before any grant
  // is looked at (#28, the #5 and #6 rule).
  group('sign_event (#28)', () {
    test('a kind grant allows only its own kind', () {
      final session = activeSession(scopes: [const Nip46SignEventScope(1)]);

      expect(signKind(session, 1), isA<Nip46AutoAllow>());
      expect(signKind(session, 7), isA<Nip46RequireReview>());
    });

    test('a broad allow grant never auto-approves', () {
      // Never saved, but one in storage must still not sign anything.
      final session = activeSession(scopes: [const Nip46SignEventScope()]);

      expect(signKind(session, 1), isA<Nip46RequireReview>());
      final broad = signKind(session, null);
      expect(broad, isA<Nip46RequireReview>());
      expect((broad as Nip46RequireReview).canRemember, isFalse);
    });

    test('a broad reject refuses every kind', () {
      final session = activeSession(
        grants: [
          grant(
            const Nip46SignEventScope(),
            decision: Nip55PermissionDecision.reject,
          ),
        ],
      );

      expect(signKind(session, 1), isA<Nip46AutoReject>());
      expect(signKind(session, 30023), isA<Nip46AutoReject>());
    });

    test('a reject wins over an allow for the same kind', () {
      final session = activeSession(
        grants: [
          grant(const Nip46SignEventScope(1)),
          grant(
            const Nip46SignEventScope(1),
            decision: Nip55PermissionDecision.reject,
          ),
        ],
      );

      expect(signKind(session, 1), isA<Nip46AutoReject>());
    });

    test('an expired grant is ignored', () {
      final session = activeSession(
        grants: [
          grant(
            const Nip46SignEventScope(1),
            expiresAt: now.subtract(const Duration(minutes: 1)),
          ),
        ],
      );

      expect(signKind(session, 1), isA<Nip46RequireReview>());
    });

    test('a grant made under another identity does not apply', () {
      final session = activeSession(
        grants: [grant(const Nip46SignEventScope(1), identity: clientPubkey)],
      );

      expect(signKind(session, 1), isA<Nip46RequireReview>());
    });

    test('with no grant, a kind is reviewed and can be remembered', () {
      final result = signKind(activeSession(), 1);

      expect(result, isA<Nip46RequireReview>());
      expect((result as Nip46RequireReview).canRemember, isTrue);
    });
  });

  group('decrypt operations', () {
    test('nip04_decrypt without grant → RequireReview', () {
      expect(
        policy.decide(
          method: Nip46Method.nip04Decrypt,
          session: activeSession(),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46RequireReview>(),
      );
    });

    test('nip04_decrypt with matching grant → AutoAllow', () {
      expect(
        policy.decide(
          method: Nip46Method.nip04Decrypt,
          session: activeSession(scopes: [const Nip46Nip04DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip44_decrypt grant satisfies decrypt_zap_event', () {
      expect(
        policy.decide(
          method: Nip46Method.decryptZapEvent,
          session: activeSession(scopes: [const Nip46Nip44DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip04_decrypt grant satisfies decrypt_zap_event', () {
      expect(
        policy.decide(
          method: Nip46Method.decryptZapEvent,
          session: activeSession(scopes: [const Nip46Nip04DecryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });

    test('nip44_encrypt without grant → RequireReview', () {
      expect(
        policy.decide(
          method: Nip46Method.nip44Encrypt,
          session: activeSession(),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46RequireReview>(),
      );
    });

    test('nip44_encrypt with grant → AutoAllow', () {
      expect(
        policy.decide(
          method: Nip46Method.nip44Encrypt,
          session: activeSession(scopes: [const Nip46Nip44EncryptScope()]),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: pubkey,
        ),
        isA<Nip46AutoAllow>(),
      );
    });
  });
}
