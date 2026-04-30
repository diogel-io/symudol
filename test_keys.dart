// ignore_for_file: avoid_print
import 'package:dart_nostr/dart_nostr.dart';

void main() {
  final nostr = Nostr.instance;
  // Try to find where encodePrivateKeyToNsec is
  // It might be in utilsService or keys
  // Based on latest docs it should be in keysService (which is services.keys)
  try {
     final keyPair = nostr.services.keys.generateKeyPair();
     final nsec = nostr.services.bech32.encodePrivateKeyToNsec(keyPair.private);
     final npub = nostr.services.bech32.encodePublicKeyToNpub(keyPair.public);
     print('nsec: $nsec');
     print('npub: $npub');
  } catch (e) {
     print('Error: $e');
  }
}
