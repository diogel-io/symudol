import 'package:android_diogel/features/nip55/domain/nip55_approval_policy.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_decision.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Nip55ApprovalPolicy', () {
    const policy = Nip55ApprovalPolicy();
    const identity =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final now = DateTime.utc(2026, 5, 3);

    test('locked vault requires unlock', () {
      final decision = policy.decide(
        request: _request(now: now),
        vaultState: const VaultLocked(),
        activeIdentityPubkey: identity,
        grants: const [],
      );

      expect(decision, isA<RequireUnlock>());
    });

    test('allow grant matches exact package identity and kind', () {
      final decision = policy.decide(
        request: _request(now: now),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<AutoAllow>());
    });

    test('grant does not match wrong identity', () {
      final decision = policy.decide(
        request: _request(now: now),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            packageName: 'com.example.client',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<RequireReview>());
    });

    test('expired grant is ignored', () {
      final decision = policy.decide(
        request: _request(now: now),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            now: now,
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ],
      );

      expect(decision, isA<RequireReview>());
    });

    test('reject grant returns auto-reject', () {
      final decision = policy.decide(
        request: _request(now: now),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.reject,
            now: now,
          ),
        ],
      );

      expect(decision, isA<AutoReject>());
    });

    test('nip04_decrypt grant auto-allows decrypt_zap_event', () {
      final zapRequest = Nip55IncomingRequest(
        localId: 'local',
        requestToken: 'token',
        method: Nip55Method.decryptZapEvent,
        receivedAt: now,
        clientIdentity: const Nip55ClientIdentity(
          packageName: 'com.example.client',
          certificateSha256: 'AA:BB',
          provenanceVerified: true,
        ),
        eventJson: const {'kind': 9734},
      );
      final decision = policy.decide(
        request: zapRequest,
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const Nip04DecryptScope(null),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<AutoAllow>());
    });

    test('nip44_decrypt grant auto-allows decrypt_zap_event', () {
      final zapRequest = Nip55IncomingRequest(
        localId: 'local',
        requestToken: 'token',
        method: Nip55Method.decryptZapEvent,
        receivedAt: now,
        clientIdentity: const Nip55ClientIdentity(
          packageName: 'com.example.client',
          certificateSha256: 'AA:BB',
          provenanceVerified: true,
        ),
        eventJson: const {'kind': 9734},
      );
      final decision = policy.decide(
        request: zapRequest,
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const Nip44DecryptScope(null),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<AutoAllow>());
    });

    test('decrypt_zap_event grant auto-allows decrypt_zap_event', () {
      final zapRequest = Nip55IncomingRequest(
        localId: 'local',
        requestToken: 'token',
        method: Nip55Method.decryptZapEvent,
        receivedAt: now,
        clientIdentity: const Nip55ClientIdentity(
          packageName: 'com.example.client',
          certificateSha256: 'AA:BB',
          provenanceVerified: true,
        ),
        eventJson: const {'kind': 9734},
      );
      final decision = policy.decide(
        request: zapRequest,
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const DecryptZapEventScope(),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<AutoAllow>());
    });

    test('current_user mismatch blocks auto signing', () {
      final decision = policy.decide(
        request: _request(
          now: now,
          currentUser:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
        vaultState: const VaultUnlocked(),
        activeIdentityPubkey: identity,
        grants: [
          _grant(
            identityPubkey: identity,
            packageName: 'com.example.client',
            scope: const SignEventScope(1),
            decision: Nip55PermissionDecision.allow,
            now: now,
          ),
        ],
      );

      expect(decision, isA<RequireReview>());
      expect((decision as RequireReview).canRemember, isFalse);
    });
  });
}

Nip55IncomingRequest _request({required DateTime now, String? currentUser}) {
  return Nip55IncomingRequest(
    localId: 'local',
    requestToken: 'token',
    method: Nip55Method.signEvent,
    receivedAt: now,
    currentUser: currentUser,
    clientIdentity: const Nip55ClientIdentity(
      packageName: 'com.example.client',
      certificateSha256: 'AA:BB',
      provenanceVerified: true,
    ),
    eventJson: const {'kind': 1, 'content': 'hello', 'tags': []},
  );
}

Nip55PermissionGrant _grant({
  required String identityPubkey,
  required String packageName,
  required Nip55PermissionScope scope,
  required Nip55PermissionDecision decision,
  required DateTime now,
  DateTime? expiresAt,
}) {
  return Nip55PermissionGrant(
    id: 'grant-${scope.wire}-$decision',
    identityPubkey: identityPubkey,
    packageName: packageName,
    certificateSha256: 'AA:BB',
    scope: scope,
    decision: decision,
    createdAt: now,
    expiresAt: expiresAt,
  );
}
