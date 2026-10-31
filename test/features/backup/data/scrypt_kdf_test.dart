import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/backup/data/scrypt_kdf.dart';
import 'package:symudol/features/backup/domain/nip49.dart';

/// NIP-49 keys come from Android's native scrypt, or from Dart where it is
/// missing (diogel-io/symudol#25).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final salt = Uint8List.fromList(List.generate(16, (i) => i));

  setUp(() => ConcurrencyUtils.useSynchronousTasks = true);
  tearDown(() {
    ConcurrencyUtils.useSynchronousTasks = false;
    messenger.setMockMethodCallHandler(scryptChannel, null);
  });

  test(
    'asks the native side with NIP-49 parameters and an NFKC password',
    () async {
      late MethodCall call;
      messenger.setMockMethodCallHandler(scryptChannel, (c) async {
        call = c;
        return Uint8List(32)..[0] = 9;
      });

      final key = await const PlatformNip49KeyDeriver().derive(
        'ÅΩẛ̣',
        salt: salt,
      );

      expect(call.method, 'derive');
      final args = call.arguments as Map;
      expect(args['password'], utf8.encode('ÅΩṩ'));
      expect(args['salt'], salt);
      expect(
        [args['n'], args['r'], args['p'], args['dkLen']],
        [65536, 8, 1, 32],
      );
      expect(key.logN, 16);
      expect(key.salt, salt);
      expect(key.symmetricKey[0], 9);
    },
  );

  test(
    'falls back to Dart, with the same key, where there is no channel',
    () async {
      final key = await const PlatformNip49KeyDeriver().derive(
        'a long passphrase',
        logN: 4,
        salt: salt,
      );

      expect(
        key.symmetricKey,
        nip49DeriveKey('a long passphrase', logN: 4, salt: salt).symmetricKey,
      );
    },
  );

  test('a native failure is a NIP-49 failure', () async {
    messenger.setMockMethodCallHandler(
      scryptChannel,
      (_) async => throw PlatformException(code: 'OUT_OF_MEMORY'),
    );

    await expectLater(
      const PlatformNip49KeyDeriver().derive('a long passphrase', salt: salt),
      throwsA(isA<Nip49Exception>()),
    );
  });
}
