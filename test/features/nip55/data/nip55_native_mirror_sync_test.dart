import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hexToKeyBytes (#9)', () {
    test('turns a hex private key into its 32 bytes', () {
      final bytes = hexToKeyBytes('${'00' * 31}ff');

      expect(bytes, hasLength(32));
      expect(bytes.take(31), everyElement(0));
      expect(bytes.last, 0xff);
    });

    test('refuses anything but a 64-character key', () {
      expect(() => hexToKeyBytes('abcd'), throwsArgumentError);
      expect(() => hexToKeyBytes('${'00' * 32}00'), throwsArgumentError);
    });
  });
}
