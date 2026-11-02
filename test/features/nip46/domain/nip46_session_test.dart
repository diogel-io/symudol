import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/domain/nip46_permission_grant.dart';
import 'package:symudol/features/nip46/domain/nip46_permission_scope.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';

void main() {
  final session = Nip46Session(
    id: 'session-1',
    clientPubkey: 'client',
    remoteSignerPubkey: 'signer',
    remoteSignerPrivkey: 'secret-key',
    relays: const ['wss://relay.example.com'],
    status: Nip46SessionStatus.pending,
    createdAt: DateTime.utc(2026, 10, 24),
    pendingSecret: 's3cr3t',
    initiatedBy: Nip46ConnectionInitiator.nostrconnect,
  );

  test('keeps who initiated the connection through storage', () {
    final restored = Nip46Session.fromJson(session.toJson());

    expect(restored.initiatedBy, Nip46ConnectionInitiator.nostrconnect);
  });

  test('a session stored before the field existed reads as bunker', () {
    final json = session.toJson()..remove('initiatedBy');

    expect(
      Nip46Session.fromJson(json).initiatedBy,
      Nip46ConnectionInitiator.bunker,
    );
  });

  test('copyWith keeps the initiator', () {
    expect(
      session.copyWith(status: Nip46SessionStatus.active).initiatedBy,
      Nip46ConnectionInitiator.nostrconnect,
    );
  });

  // Remembered decisions are stored with the session (#28).
  group('grants (#28)', () {
    final grant = Nip46PermissionGrant(
      scope: const Nip46SignEventScope(1),
      decision: Nip55PermissionDecision.allow,
      identityPubkey: 'identity',
      createdAt: DateTime.utc(2026, 11, 2),
      expiresAt: DateTime.utc(2026, 11, 2, 8),
    );

    test('grants and requested scopes round-trip through storage', () {
      final restored = Nip46Session.fromJson(
        session
            .copyWith(
              grants: [grant],
              requestedScopes: const [Nip46Nip44EncryptScope()],
            )
            .toJson(),
      );

      final kept = restored.grants.single;
      expect(kept.scope.wire, 'sign_event:1');
      expect(kept.decision, Nip55PermissionDecision.allow);
      expect(kept.identityPubkey, 'identity');
      expect(kept.expiresAt, DateTime.utc(2026, 11, 2, 8));
      expect(restored.requestedScopes.single.wire, 'nip44_encrypt');
    });

    test('a grant whose expiry cannot be read is dropped, not kept', () {
      Nip46Session withExpiry(Object? expiresAt) => Nip46Session.fromJson(
        session.toJson()
          ..['grants'] = [
            {...grant.toJson(), 'expiresAt': expiresAt},
          ],
      );

      expect(withExpiry('not a date').grants, isEmpty);
      expect(withExpiry(1793638471).grants, isEmpty);
      expect(withExpiry(null).grants.single.expiresAt, isNull);
    });

    test('a stored broad allow is dropped when read', () {
      final json = session.toJson()
        ..['grants'] = [
          {
            ...grant.toJson(),
            'scope': const Nip46SignEventScope().toJson(),
          },
        ];

      expect(Nip46Session.fromJson(json).grants, isEmpty);
    });

    test('old grantedScopes: requested while pending, dropped once active', () {
      Map<String, Object?> legacy(Nip46SessionStatus status) => session
          .copyWith(status: status)
          .toJson()
        ..remove('requestedScopes')
        ..remove('grants')
        ..['grantedScopes'] = [const Nip46SignEventScope(1).toJson()];

      final pending = Nip46Session.fromJson(
        legacy(Nip46SessionStatus.pending),
      );
      final active = Nip46Session.fromJson(legacy(Nip46SessionStatus.active));

      expect(pending.requestedScopes.single.wire, 'sign_event:1');
      expect(pending.grants, isEmpty);
      expect(active.requestedScopes, isEmpty);
      expect(active.grants, isEmpty);
    });
  });
}
