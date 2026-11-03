import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/data/secure_storage_nip46_session_store.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip46/domain/nip46_session_store.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';

const _v2 = 'nip46_sessions_v2';
const _v1 = 'nip46_sessions_v1';
const _privkey =
    'c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ff';

void main() {
  late _MemoryStorage storage;
  final key = Uint8List.fromList(List.generate(32, (i) => i));

  SecureStorageNip46SessionStore newStore() =>
      SecureStorageNip46SessionStore(storage: storage);

  setUp(() => storage = _MemoryStorage());

  group('SecureStorageNip46SessionStore (#32)', () {
    test('round-trips sessions, keys included, with the storage key', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a', pendingSecret: 'once'));

      final reopened = newStore()..useStorageKey(key);
      final [session] = await reopened.listSessions();

      expect(session.id, 'a');
      expect(session.remoteSignerPrivkey, _privkey);
      expect(session.pendingSecret, 'once');
      expect(session.clientName, 'Client a');
    });

    test('stores no session key or secret in the clear', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a', pendingSecret: 'once'));

      final raw = storage.values[_v2]!;
      expect(raw, isNot(contains(_privkey)));
      expect(raw, isNot(contains('once')));
      expect(raw, isNot(contains('remoteSignerPrivkey')));
      // The rest is stored as is.
      expect(raw, contains('Client a'));
    });

    test('counts sessions without a key, but reads none', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a'));
      await store.saveSession(_session('b'));

      final locked = newStore();
      expect(await locked.countSessions(), 2);
      await expectLater(
        locked.listSessions(),
        throwsA(isA<Nip46StoreLockedException>()),
      );
      await expectLater(
        locked.saveSession(_session('c')),
        throwsA(isA<Nip46StoreLockedException>()),
      );
    });

    test('with no sessions stored, needs no key', () async {
      final store = newStore();

      expect(await store.countSessions(), 0);
      expect(await store.listSessions(), isEmpty);
    });

    test('the wrong key reads nothing', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a'));

      final wrong = newStore()..useStorageKey(Uint8List(32));
      await expectLater(
        wrong.listSessions(),
        throwsA(isA<VaultCryptoTamperException>()),
      );
    });

    test('secrets moved to another session are refused', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a'));
      await store.saveSession(_session('b'));
      final entries = (jsonDecode(storage.values[_v2]!) as List)
          .cast<Map<String, Object?>>();
      final aSecrets = entries[0]['secrets'];
      entries[1]['secrets'] = aSecrets;
      storage.values[_v2] = jsonEncode(entries);

      await expectLater(
        (newStore()..useStorageKey(key)).listSessions(),
        throwsA(isA<VaultCryptoTamperException>()),
      );
    });

    test('keeps the key for saves after the vault locks', () async {
      final callerKey = Uint8List.fromList(key);
      final store = newStore()..useStorageKey(callerKey);
      // The caller zeroes its copy, as the controller does.
      callerKey.fillRange(0, callerKey.length, 0);

      await store.saveSession(_session('a'));

      final [session] = await (newStore()..useStorageKey(key)).listSessions();
      expect(session.id, 'a');
    });

    group('sessions stored before #32', () {
      setUp(() {
        storage.values[_v1] = jsonEncode([_session('a').toJson()]);
      });

      test('are counted, but not read, without a key', () async {
        final store = newStore();

        expect(await store.countSessions(), 1);
        await expectLater(
          store.listSessions(),
          throwsA(isA<Nip46StoreLockedException>()),
        );
        expect(storage.values[_v1], isNotNull);
      });

      test(
        'are encrypted on the first load, and the old value deleted',
        () async {
          final [session] = await (newStore()..useStorageKey(key))
              .listSessions();

          expect(session.remoteSignerPrivkey, _privkey);
          expect(storage.values[_v1], isNull);
          expect(storage.values[_v2], isNot(contains(_privkey)));
          final [again] = await (newStore()..useStorageKey(key)).listSessions();
          expect(again.id, 'a');
        },
      );

      test(
        'are kept when the encrypted write fails, and moved on the next save',
        () async {
          storage.failWrites = true;
          final store = newStore()..useStorageKey(key);

          final [session] = await store.listSessions();
          expect(session.id, 'a');
          expect(storage.values[_v1], isNotNull);
          expect(storage.values[_v2], isNull);

          storage.failWrites = false;
          await store.saveSession(_session('b'));
          expect(storage.values[_v1], isNull);
          final sessions = await (newStore()..useStorageKey(key))
              .listSessions();
          expect(sessions.map((s) => s.id), ['a', 'b']);
        },
      );
    });

    test('deletes old sessions left beside the encrypted ones', () async {
      final store = newStore()..useStorageKey(key);
      await store.saveSession(_session('a'));
      // As after a move whose delete failed or was cut short.
      storage.values[_v1] = jsonEncode([_session('a').toJson()]);

      final [session] = await (newStore()..useStorageKey(key)).listSessions();

      expect(session.id, 'a');
      expect(storage.values[_v1], isNull);
    });

    test(
      'clearAll deletes both formats and the setting, and drops the key',
      () async {
        final store = newStore()..useStorageKey(key);
        await store.saveSession(_session('a'));
        storage.values[_v1] = '[]';
        await store.setRunInBackground(true);

        await store.clearAll();

        expect(storage.values, isEmpty);
        expect(await store.listSessions(), isEmpty);
        await expectLater(
          store.saveSession(_session('b')),
          throwsA(isA<Nip46StoreLockedException>()),
        );
      },
    );
  });
}

Nip46Session _session(String id, {String? pendingSecret}) => Nip46Session(
  id: id,
  clientPubkey: 'a' * 64,
  remoteSignerPubkey: 'b' * 64,
  remoteSignerPrivkey: _privkey,
  relays: const ['wss://relay.example.com'],
  clientName: 'Client $id',
  status: Nip46SessionStatus.active,
  createdAt: DateTime.utc(2026),
  pendingSecret: pendingSecret,
);

/// Secure storage in memory. Only read, write and delete are used.
class _MemoryStorage implements FlutterSecureStorage {
  final values = <String, String>{};

  /// Makes writes fail, as a secure-storage error would.
  bool failWrites = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    final key = args[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        if (failWrites) return Future<void>.error(StateError('write failed'));
        values[key!] = args[#value] as String;
        return Future<void>.value();
      case #delete:
        values.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}
