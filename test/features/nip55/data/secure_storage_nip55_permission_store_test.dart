import 'dart:convert';

import 'package:android_diogel/features/nip55/data/secure_storage_nip55_permission_store.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_decision.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// A broad allow (sign any kind) is never kept (diogel-io/symudol#5).
const _key = 'nip55_permission_grants_v1';

Nip55PermissionGrant _grant(
  String id,
  Nip55PermissionScope scope,
  Nip55PermissionDecision decision,
) => Nip55PermissionGrant(
  id: id,
  identityPubkey: 'pk',
  packageName: 'com.example.app',
  scope: scope,
  decision: decision,
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'drops broad allows saved before #5, and rewrites storage without them',
    () async {
      final stored = [
        _grant(
          'broad-allow',
          const SignEventScope(),
          Nip55PermissionDecision.allow,
        ),
        _grant(
          'kind-1',
          const SignEventScope(1),
          Nip55PermissionDecision.allow,
        ),
        _grant(
          'broad-reject',
          const SignEventScope(),
          Nip55PermissionDecision.reject,
        ),
      ];
      FlutterSecureStorage.setMockInitialValues({
        _key: jsonEncode(stored.map((grant) => grant.toJson()).toList()),
      });
      const storage = FlutterSecureStorage();
      final store = SecureStorageNip55PermissionStore(storage: storage);

      final grants = await store.listGrants();

      expect(grants.map((grant) => grant.id), ['kind-1', 'broad-reject']);
      final rewritten = jsonDecode((await storage.read(key: _key))!) as List;
      expect(rewritten.map((item) => (item as Map)['id']), [
        'kind-1',
        'broad-reject',
      ]);
    },
  );

  test('refuses to save a broad allow, and keeps a broad reject', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureStorageNip55PermissionStore(
      storage: const FlutterSecureStorage(),
    );

    await store.saveGrant(
      _grant(
        'broad-allow',
        const SignEventScope(),
        Nip55PermissionDecision.allow,
      ),
    );
    await store.saveGrant(
      _grant(
        'broad-reject',
        const SignEventScope(),
        Nip55PermissionDecision.reject,
      ),
    );
    await store.saveGrant(
      _grant('kind-1', const SignEventScope(1), Nip55PermissionDecision.allow),
    );

    final ids = (await store.listGrants()).map((grant) => grant.id);
    expect(ids, ['broad-reject', 'kind-1']);
  });
}
