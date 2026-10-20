import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';

class FakeNip46SessionStore implements Nip46SessionStore {
  final List<Nip46Session> sessions;

  FakeNip46SessionStore([List<Nip46Session>? sessions])
    : sessions = sessions ?? [];

  @override
  Future<List<Nip46Session>> listSessions() async => List.of(sessions);

  @override
  Future<void> saveSession(Nip46Session session) async {
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx == -1) {
      sessions.add(session);
    } else {
      sessions[idx] = session;
    }
  }

  @override
  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> clearAll() async => sessions.clear();
}
