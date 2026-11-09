// Prints the npub of the Zapstore publisher key in SIGN_WITH, so the release workflow can check it
// against the `pubkey` in zapstore.yaml before zsp publishes. zsp 2 ignores that field, so without
// this check a secret holding another key would publish under that key.
//
// Run from the repository root: dart run tools/zapstore_publisher_npub.dart
// Only the public key is printed. Errors never include the secret.
import 'dart:io';

import 'package:dart_nostr/dart_nostr.dart';

void main() {
  final nsec = (Platform.environment['SIGN_WITH'] ?? '').trim();
  if (!nsec.startsWith('nsec1')) {
    stderr.writeln('SIGN_WITH is not set to an nsec.');
    exit(1);
  }
  final String npub;
  try {
    final bech32 = Nostr.instance.services.bech32;
    final privateKey = bech32.decodeNsecKeyToPrivateKey(nsec);
    npub = bech32.encodePublicKeyToNpub(
      NostrKeyPairs(private: privateKey).public,
    );
  } catch (_) {
    stderr.writeln('SIGN_WITH is not a valid nsec.');
    exit(1);
  }
  stdout.writeln(npub);
}
