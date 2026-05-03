import 'package:state_notifier/state_notifier.dart';

import '../domain/nip55_client_permission.dart';
import '../domain/nip55_permission_store.dart';

class Nip55PermissionState {
  final List<Nip55PermissionGrant> grants;
  final bool isLoading;
  final Object? failure;

  const Nip55PermissionState({
    this.grants = const [],
    this.isLoading = false,
    this.failure,
  });

  Nip55PermissionState copyWith({
    List<Nip55PermissionGrant>? grants,
    bool? isLoading,
    Object? failure,
    bool clearFailure = false,
  }) {
    return Nip55PermissionState(
      grants: grants ?? this.grants,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class Nip55PermissionController extends StateNotifier<Nip55PermissionState> {
  final Nip55PermissionStore _store;

  Nip55PermissionController({required Nip55PermissionStore store})
    : _store = store,
      super(const Nip55PermissionState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      state = state.copyWith(
        grants: await _store.listGrants(),
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, failure: error);
    }
  }

  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    await _store.saveGrant(grant);
    await load();
  }

  Future<void> revokeGrant(String id) async {
    await _store.deleteGrant(id);
    await load();
  }

  Future<void> revokePackage(String packageName) async {
    await _store.deleteAllForPackage(packageName);
    await load();
  }

  Future<void> revokeAll() async {
    await _store.clearAll();
    state = const Nip55PermissionState();
  }
}
