import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_store.dart';

class FakeNip55PermissionStore implements Nip55PermissionStore {
  final grants = <Nip55PermissionGrant>[];

  /// When set, [listGrants] waits for it before answering.
  Future<void>? hold;

  @override
  Future<void> clearAll() async => grants.clear();

  @override
  Future<void> deleteAllForPackage(String packageName) async {
    grants.removeWhere((grant) => grant.packageName == packageName);
  }

  @override
  Future<void> deleteGrant(String id) async {
    grants.removeWhere((grant) => grant.id == id);
  }

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async {
    await hold;
    return List.of(grants);
  }

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    grants.removeWhere((existing) => existing.id == grant.id);
    grants.add(grant);
  }
}
