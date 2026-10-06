import 'dart:convert';

import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';
import 'package:symudol/features/signing/domain/nostr_crypto_service.dart';

import '../domain/nip46_request.dart';
import '../domain/nip46_response.dart';

class DartNip46Crypto {
  final NostrCryptoService _crypto;

  const DartNip46Crypto(this._crypto);

  /// Decrypts and parses an inbound NIP-46 request envelope.
  ///
  /// Tries NIP-44 first. If NIP-44 fails and the content looks like NIP-04
  /// (contains `?iv=`), falls back to NIP-04. Returns the parsed request and
  /// a flag indicating which cipher was used.
  Future<(Nip46Request, bool wasNip04)> decryptRequest({
    required String sessionPrivkey,
    required String clientPubkey,
    required String encryptedContent,
  }) async {
    // Try NIP-44 first.
    try {
      final plaintext = _crypto.nip44Decrypt(
        privateKeyHex: sessionPrivkey,
        peerPubkeyHex: clientPubkey,
        ciphertext: encryptedContent,
      );
      final request = _parseJson(plaintext);
      return (request, false);
    } catch (_) {
      // Intentionally swallow — try NIP-04 next if it looks like NIP-04.
    }

    if (!encryptedContent.contains('?iv=')) {
      throw Nip46CryptoException(
        'Failed to decrypt NIP-44 content and content does not look like NIP-04',
      );
    }

    try {
      final plaintext = _crypto.nip04Decrypt(
        privateKeyHex: sessionPrivkey,
        peerPubkeyHex: clientPubkey,
        ciphertext: encryptedContent,
      );
      final request = _parseJson(plaintext);
      return (request, true);
    } catch (e) {
      throw Nip46CryptoException('Failed to decrypt NIP-04 fallback: $e');
    }
  }

  /// Encrypts a NIP-46 response envelope using NIP-44 by default, or NIP-04
  /// if [useNip04] is true (for clients that spoke NIP-04).
  Future<String> encryptResponse({
    required String sessionPrivkey,
    required String clientPubkey,
    required Nip46Response response,
    required bool useNip04,
  }) async {
    final plaintext = jsonEncode(response.toJson());
    if (useNip04) {
      return _crypto.nip04Encrypt(
        privateKeyHex: sessionPrivkey,
        peerPubkeyHex: clientPubkey,
        plaintext: plaintext,
      );
    }
    return _crypto.nip44Encrypt(
      privateKeyHex: sessionPrivkey,
      peerPubkeyHex: clientPubkey,
      plaintext: plaintext,
    );
  }

  /// Derives the x-only Schnorr public key from a private key.
  String derivePublicKey(String privateKeyHex) =>
      _crypto.derivePublicKey(privateKeyHex);

  /// Builds a signed kind 24133 Nostr event for publishing a NIP-46 response.
  SignedNostrEvent buildSignedResponseEvent({
    required String sessionPrivkey,
    required String clientPubkey,
    required String encryptedContent,
  }) {
    final draft = NostrEventDraft(
      kind: 24133,
      content: encryptedContent,
      tags: [
        ['p', clientPubkey],
      ],
      createdAt: DateTime.now().toUtc(),
    );
    return _crypto.signEvent(privateKeyHex: sessionPrivkey, draft: draft);
  }

  Nip46Request _parseJson(String plaintext) {
    final Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (e) {
      throw Nip46CryptoException('Decrypted content is not valid JSON: $e');
    }
    if (decoded is! Map) {
      throw const Nip46CryptoException('Decrypted content must be a JSON object');
    }
    return Nip46Request.fromDecryptedJson(decoded.cast());
  }
}

class Nip46CryptoException implements Exception {
  final String message;
  const Nip46CryptoException(this.message);

  @override
  String toString() => 'Nip46CryptoException: $message';
}
