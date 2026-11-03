import 'dart:async';
import 'dart:typed_data';

import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';

class FakeNip46SessionStore implements Nip46SessionStore {
  final List<Nip46Session> sessions;

  FakeNip46SessionStore([List<Nip46Session>? sessions])
    : sessions = sessions ?? [];

  /// When set, reading or writing sessions needs a key, as the real store
  /// does while sessions are stored (#32).
  bool requireKey = false;

  /// The key given with [useStorageKey], until [clearAll].
  Uint8List? storageKey;

  void _checkKey() {
    if (requireKey && storageKey == null && sessions.isNotEmpty) {
      throw const Nip46StoreLockedException();
    }
  }

  @override
  void useStorageKey(Uint8List key) => storageKey = Uint8List.fromList(key);

  @override
  Future<int> countSessions() async => sessions.length;

  @override
  Future<List<Nip46Session>> listSessions() async {
    _checkKey();
    return List.of(sessions);
  }

  /// Makes this many of the next saves fail, as a secure-storage write
  /// error would.
  int failNextSaves = 0;

  /// While set, each save waits for it before writing, as a slow secure
  /// storage write would.
  Completer<void>? holdSaves;

  /// Completes when a save first waits on [holdSaves].
  final saveHeld = Completer<void>();

  @override
  Future<void> saveSession(Nip46Session session) async {
    _checkKey();
    final hold = holdSaves;
    if (hold != null) {
      if (!saveHeld.isCompleted) saveHeld.complete();
      await hold.future;
    }
    if (failNextSaves > 0) {
      failNextSaves--;
      throw StateError('secure storage write failed');
    }
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx == -1) {
      sessions.add(session);
    } else {
      sessions[idx] = session;
    }
  }

  @override
  Future<void> deleteSession(String id) async {
    _checkKey();
    sessions.removeWhere((s) => s.id == id);
  }

  bool runInBackground = false;

  @override
  Future<void> clearAll() async {
    sessions.clear();
    storageKey = null;
    runInBackground = false;
  }

  @override
  Future<bool> getRunInBackground() async => runInBackground;

  @override
  Future<void> setRunInBackground(bool value) async => runInBackground = value;
}
