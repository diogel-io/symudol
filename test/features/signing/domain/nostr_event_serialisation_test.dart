import 'package:android_diogel/features/signing/domain/nostr_event_serialisation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pubkey =
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';

  group('isNostrEventSerialisation (#8)', () {
    test('an event id serialisation counts', () {
      expect(
        isNostrEventSerialisation('[0,"$pubkey",1700000000,1,[],"hi"]'),
        isTrue,
      );
      expect(
        isNostrEventSerialisation(
          '[0,"$pubkey",1700000000,0,[["p","$pubkey"]],"{\\"name\\":\\"x\\"}"]',
        ),
        isTrue,
      );
    });

    test('with whitespace, or any field values, it still counts', () {
      expect(
        isNostrEventSerialisation(' [ 0 , "x" , 1 , 1 , [ ] , "" ] '),
        isTrue,
      );
      expect(isNostrEventSerialisation('[0,null,null,null,null,null]'), isTrue);
      expect(isNostrEventSerialisation('[0.0,1,2,3,4,5]'), isTrue);
    });

    test('anything else does not', () {
      for (final message in [
        '[]',
        '[1,"$pubkey",1700000000,1,[],"hi"]',
        '["0","$pubkey",1700000000,1,[],"hi"]',
        '[0,"$pubkey",1700000000,1,[]]',
        '[0,"$pubkey",1700000000,1,[],"hi","extra"]',
        '{"kind":1,"content":"hi"}',
        '[0,"$pubkey",1700000000,1,[],"hi"',
        'hello',
        '0',
        '',
        'gm 🌅',
      ]) {
        expect(isNostrEventSerialisation(message), isFalse, reason: message);
      }
    });
  });
}
