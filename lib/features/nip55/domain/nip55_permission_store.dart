import 'nip55_client_permission.dart';

abstract interface class Nip55PermissionStore {
  Future<List<Nip55PermissionGrant>> listGrants();

  Future<void> saveGrant(Nip55PermissionGrant grant);

  Future<void> deleteGrant(String id);

  Future<void> deleteAllForPackage(String packageName);

  Future<void> clearAll();
}
