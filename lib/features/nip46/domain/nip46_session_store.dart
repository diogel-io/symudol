import 'nip46_session.dart';

abstract interface class Nip46SessionStore {
  Future<List<Nip46Session>> listSessions();
  Future<void> saveSession(Nip46Session session);
  Future<void> deleteSession(String id);
  Future<void> clearAll();
}
