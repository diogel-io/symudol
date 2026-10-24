import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';

void main() {
  final session = Nip46Session(
    id: 'session-1',
    clientPubkey: 'client',
    remoteSignerPubkey: 'signer',
    remoteSignerPrivkey: 'secret-key',
    relays: const ['wss://relay.example.com'],
    grantedScopes: const [],
    status: Nip46SessionStatus.pending,
    createdAt: DateTime.utc(2026, 10, 24),
    pendingSecret: 's3cr3t',
    initiatedBy: Nip46ConnectionInitiator.nostrconnect,
  );

  test('keeps who initiated the connection through storage', () {
    final restored = Nip46Session.fromJson(session.toJson());

    expect(restored.initiatedBy, Nip46ConnectionInitiator.nostrconnect);
  });

  test('a session stored before the field existed reads as bunker', () {
    final json = session.toJson()..remove('initiatedBy');

    expect(
      Nip46Session.fromJson(json).initiatedBy,
      Nip46ConnectionInitiator.bunker,
    );
  });

  test('copyWith keeps the initiator', () {
    expect(
      session.copyWith(status: Nip46SessionStatus.active).initiatedBy,
      Nip46ConnectionInitiator.nostrconnect,
    );
  });
}
