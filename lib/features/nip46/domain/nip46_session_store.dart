import 'dart:typed_data';

import 'nip46_session.dart';

abstract interface class Nip46SessionStore {
  /// Every stored session, with its keys.
  ///
  /// Throws [Nip46StoreLockedException] while sessions are stored and no key
  /// has been given with [useStorageKey]. So do [saveSession] and
  /// [deleteSession].
  Future<List<Nip46Session>> listSessions();
  Future<void> saveSession(Nip46Session session);
  Future<void> deleteSession(String id);

  /// Deletes every session and the setting below, and forgets the key.
  Future<void> clearAll();

  /// How many sessions are stored. Needs no key, so it works while the vault
  /// is locked, as on the Forgot PIN screen.
  Future<int> countSessions();

  /// The key that session keys are encrypted with at rest, from
  /// `VaultService.nip46StorageKey` (#32). The store keeps its own copy for
  /// the life of the process, so sessions can still be saved after the vault
  /// locks, until [clearAll].
  void useStorageKey(Uint8List key);

  /// Whether the user wants remote signing kept running while Symudol is in
  /// the background (#29). False until set; [clearAll] resets it.
  Future<bool> getRunInBackground();
  Future<void> setRunInBackground(bool value);
}

/// The sessions' keys can't be read yet: the vault hasn't been unlocked in
/// this process (#32).
class Nip46StoreLockedException implements Exception {
  const Nip46StoreLockedException();

  @override
  String toString() =>
      'Nip46StoreLockedException: unlock the vault to read NIP-46 sessions';
}
