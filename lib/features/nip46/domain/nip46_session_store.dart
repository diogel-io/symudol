import 'nip46_session.dart';

abstract interface class Nip46SessionStore {
  Future<List<Nip46Session>> listSessions();
  Future<void> saveSession(Nip46Session session);
  Future<void> deleteSession(String id);
  Future<void> clearAll();

  /// Whether the user wants remote signing kept running while Symudol is in
  /// the background (#29). False until set; [clearAll] resets it.
  Future<bool> getRunInBackground();
  Future<void> setRunInBackground(bool value);
}
