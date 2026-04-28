import 'package:dart_nostr/dart_nostr.dart';

void main() {
  final nostr = Nostr.instance;

  // 1. Generating Nostr private keys & deriving public keys
  final keyPair = nostr.services.keys.generateKeyPair();
  final privateKey = keyPair.private;
  final publicKey = keyPair.public;
  print('Generated Private Key (Hex): $privateKey');
  print('Generated Public Key (Hex): $publicKey');

  // 2. Deriving public key from existing private key
  final derivedKeyPair = nostr.services.keys.generateKeyPairFromExistingPrivateKey(privateKey);
  print('Derived Public Key (Hex): ${derivedKeyPair.public}');
  if (derivedKeyPair.public == publicKey) {
    print('Public key derivation verified.');
  }

  // 3. Encoding nsec and npub
  final nsec = nostr.services.bech32.encodePrivateKeyToNsec(privateKey);
  final npub = nostr.services.bech32.encodePublicKeyToNpub(publicKey);
  print('Encoded nsec: $nsec');
  print('Encoded npub: $npub');

  // 4. Parsing nsec
  final decodedPrivateKey = nostr.services.bech32.decodeNsecKeyToPrivateKey(nsec);
  print('Decoded Private Key from nsec: $decodedPrivateKey');
  if (decodedPrivateKey == privateKey) {
    print('nsec parsing verified.');
  }

  // 5. Signing Nostr events
  const message = 'test message';
  final signature = nostr.services.keys.sign(
    privateKey: privateKey,
    message: message,
  );
  print('Signature: $signature');

  final isValid = nostr.services.keys.verify(
    publicKey: publicKey,
    message: message,
    signature: signature,
  );
  print('Is signature valid? $isValid');
}
