import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip55/domain/nip55_approval_policy.dart';
import 'package:symudol/features/nip55/domain/nip55_client.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/nip55/domain/nip55_incoming_request.dart';
import 'package:symudol/features/nip55/domain/nip55_method.dart';
import 'package:symudol/features/nip55/domain/symudol_package.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';

/// Runs the shared NIP-55 permission cases through [Nip55ApprovalPolicy]. The
/// Kotlin Nip55PermissionMirror runs the same file (Nip55PermissionParityTest),
/// so a change to one matcher without the other fails one of the two
/// (diogel-io/symudol#17).
void main() {
  final table =
      jsonDecode(
            File(
              'test/features/nip55/fixtures/permission_matching_cases.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final identity = table['activeIdentity'] as String;
  final cases = (table['cases'] as List).cast<Map<String, Object?>>();

  test('the table is for this app', () {
    expect(table['ownPackage'], symudolPackageName);
  });

  test('case ids are unique and outcomes known', () {
    final ids = cases.map((c) => c['id']).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final c in cases) {
      expect(['allow', 'reject', 'none'], contains(c['expected']), reason: '${c['id']}');
    }
  });

  test('every scope type has a case', () {
    final covered = {
      for (final c in cases)
        for (final g in (c['grants'] as List).cast<Map<String, Object?>>())
          (g['scope'] as Map)['type'],
    };
    // Every type Nip55PermissionScope.fromJson reads, from its source, so a
    // new scope fails here until the table has cases for it. Anything else is
    // read as unsupported.
    final source = File(
      'lib/features/nip55/domain/nip55_permission_scope.dart',
    ).readAsStringSync();
    final fromJson = source.substring(
      source.indexOf('static Nip55PermissionScope fromJson'),
      source.indexOf('_ => UnsupportedScope('),
    );
    final types = {
      for (final m in RegExp(r"'([a-z0-9_]+)' =>").allMatches(fromJson))
        m.group(1),
      'unsupported',
    };
    expect(types, hasLength(greaterThan(5)));
    expect(covered, types);
  });

  group('certificate in stored grants', () {
    Map<String, Object?> json() => {
      'id': 'g',
      'identityPubkey': identity,
      'packageName': 'com.example.client',
      'scope': {'type': 'get_public_key'},
      'decision': 'allow',
      'createdAt': '2026-01-01T00:00:00.000Z',
    };

    test('a missing certificate key reads as any caller', () {
      expect(Nip55PermissionGrant.fromJson(json()).certificateSha256, isNull);
    });

    test('a null certificate reads as unresolved, and stays so', () {
      final grant = Nip55PermissionGrant.fromJson({
        ...json(),
        'certificateSha256': null,
      });
      expect(grant.certificateSha256, nip55UnresolvedCertificate);
      expect(
        Nip55PermissionGrant.fromJson(grant.toJson()).certificateSha256,
        nip55UnresolvedCertificate,
      );
    });
  });

  group('Nip55ApprovalPolicy', () {
    const policy = Nip55ApprovalPolicy();
    for (final c in cases) {
      test(c['id'] as String, () {
        final request = c['request'] as Map<String, Object?>;
        final grants = (c['grants'] as List)
            .cast<Map<String, Object?>>()
            .map(Nip55PermissionGrant.fromJson)
            .toList();
        final decision = policy.decide(
          request: _incoming(request),
          vaultState: const VaultUnlocked(),
          activeIdentityPubkey: identity,
          grants: grants,
        );
        final outcome = switch (decision) {
          AutoAllow() => 'allow',
          AutoReject() => 'reject',
          RequireReview() || RequireUnlock() => 'none',
        };
        expect(outcome, c['expected'], reason: c['note'] as String?);
      });
    }
  });
}

Nip55IncomingRequest _incoming(Map<String, Object?> request) {
  final wire = request['method'] as String;
  return Nip55IncomingRequest(
    localId: 'parity',
    requestToken: 'parity',
    method: Nip55Method.values.firstWhere(
      (m) => m.wireName == wire,
      orElse: () => Nip55Method.unsupported,
    ),
    receivedAt: DateTime.utc(2026, 1, 1),
    pubkey: request['peerPubkey'] as String?,
    eventJson: (request['eventJson'] as Map?)?.cast<String, Object?>(),
    clientIdentity: Nip55ClientIdentity(
      packageName: request['packageName'] as String?,
      certificateSha256: request['certificateSha256'] as String?,
      provenanceVerified: true,
    ),
  );
}
