import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dart_nostr capabilities', () {
    test('supports key generation, nsec round trip, signing, and verification', () {
      final nostr = Nostr.instance;

      final keyPair = nostr.services.keys.generateKeyPair();
      final privateKey = keyPair.private;
      final publicKey = keyPair.public;

      expect(privateKey, isNotEmpty);
      expect(publicKey, isNotEmpty);

      final derivedKeyPair = nostr.services.keys
          .generateKeyPairFromExistingPrivateKey(privateKey);
      expect(derivedKeyPair.public, publicKey);

      final nsec = nostr.services.bech32.encodePrivateKeyToNsec(privateKey);
      final npub = nostr.services.bech32.encodePublicKeyToNpub(publicKey);

      expect(nsec, startsWith('nsec'));
      expect(npub, startsWith('npub'));

      final decodedPrivateKey = nostr.services.bech32.decodeNsecKeyToPrivateKey(
        nsec,
      );
      expect(decodedPrivateKey, privateKey);

      const message = 'test message';
      final signature = nostr.services.keys.sign(
        privateKey: privateKey,
        message: message,
      );

      expect(signature, isNotEmpty);

      final isValid = nostr.services.keys.verify(
        publicKey: publicKey,
        message: message,
        signature: signature,
      );

      expect(isValid, isTrue);
    });
  });
}
