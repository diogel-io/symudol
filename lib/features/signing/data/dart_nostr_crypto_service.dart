import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:symudol/features/requests/domain/nostr_event_draft.dart';
import 'package:symudol/features/requests/domain/signed_nostr_event.dart';
import 'package:symudol/features/signing/domain/nostr_crypto_service.dart';
import 'package:symudol/features/signing/domain/nostr_event_serialisation.dart';
import 'package:bech32/bech32.dart' as bech32;
import 'package:crypto/crypto.dart' as crypto;
import 'package:dart_nostr/dart_nostr.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/api.dart'
    show KeyParameter, PaddedBlockCipherParameters, ParametersWithIV;
import 'package:pointycastle/export.dart'
    show PaddedBlockCipherImpl, PKCS7Padding;
import 'package:pointycastle/stream/chacha7539.dart';

class DartNostrCryptoService implements NostrCryptoService {
  static final ECDomainParameters _secp256k1 = ECDomainParameters('secp256k1');
  static final BigInt _curveP = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );
  static final BigInt _curveN = _secp256k1.n;

  final Uint8List Function(int length) _randomBytes;

  const DartNostrCryptoService({Uint8List Function(int length)? randomBytes})
    : _randomBytes = randomBytes ?? _secureRandomBytes;

  @override
  String derivePublicKey(String privateKeyHex) {
    return NostrKeyPairs(private: privateKeyHex).public;
  }

  @override
  SignedNostrEvent signEvent({
    required String privateKeyHex,
    required NostrEventDraft draft,
  }) {
    final keyPairs = NostrKeyPairs(private: privateKeyHex);
    final event = NostrEvent.fromPartialData(
      kind: draft.kind,
      content: draft.content,
      keyPairs: keyPairs,
      tags: draft.tags,
      createdAt: draft.createdAt,
    );

    final sig = event.sig;
    if (sig == null || sig.isEmpty) {
      throw const NostrCryptoException('DartNostr returned an empty signature');
    }

    final signed = SignedNostrEvent(
      id: event.id!,
      pubkey: event.pubkey,
      createdAt: event.createdAt!.millisecondsSinceEpoch ~/ 1000,
      kind: event.kind!,
      tags: event.tags ?? const [],
      content: event.content ?? '',
      sig: sig,
    );

    if (!verifySignedEvent(signed)) {
      throw const NostrCryptoException(
        'Produced signature failed verification',
      );
    }

    return signed;
  }

  @override
  String signMessage({required String privateKeyHex, required String message}) {
    // Its hash would be an event id: never sign one as a message (#8).
    if (isNostrEventSerialisation(message)) {
      throw const NostrCryptoException(refusedEventSerialisationMessage);
    }
    final digest = crypto.sha256.convert(utf8.encode(message)).toString();
    final keyPairs = NostrKeyPairs(private: privateKeyHex);
    final signature = keyPairs.sign(digest);
    if (!NostrKeyPairs.verify(keyPairs.public, digest, signature)) {
      throw const NostrCryptoException(
        'Produced message signature failed verification',
      );
    }
    return signature;
  }

  @override
  String nip04Encrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String plaintext,
  }) {
    _validatePlaintext(plaintext);
    final sharedX = _sharedSecretX(privateKeyHex, peerPubkeyHex);
    final iv = _randomBytes(16);
    final encrypted = _aes256Cbc(true, sharedX, iv, utf8.encode(plaintext));
    return '${base64Encode(encrypted)}?iv=${base64Encode(iv)}';
  }

  @override
  String nip04Decrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String ciphertext,
  }) {
    final match = RegExp(r'^(.*)\?iv=([^&]+)$').firstMatch(ciphertext);
    if (match == null) {
      throw const NostrCryptoException('Malformed NIP-04 ciphertext');
    }
    final encrypted = base64Decode(match.group(1)!);
    final iv = base64Decode(match.group(2)!);
    if (iv.length != 16) {
      throw const NostrCryptoException('Malformed NIP-04 IV');
    }
    final sharedX = _sharedSecretX(privateKeyHex, peerPubkeyHex);
    final decrypted = _aes256Cbc(false, sharedX, iv, encrypted);
    return utf8.decode(decrypted);
  }

  @override
  String nip44Encrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String plaintext,
  }) {
    final conversationKey = _nip44ConversationKey(privateKeyHex, peerPubkeyHex);
    return _nip44EncryptWithConversationKey(
      conversationKey: conversationKey,
      nonce: _randomBytes(32),
      plaintext: plaintext,
    );
  }

  @override
  String nip44Decrypt({
    required String privateKeyHex,
    required String peerPubkeyHex,
    required String ciphertext,
  }) {
    final conversationKey = _nip44ConversationKey(privateKeyHex, peerPubkeyHex);
    return _nip44DecryptWithConversationKey(
      conversationKey: conversationKey,
      payload: ciphertext,
    );
  }

  @override
  String decryptZapEvent({
    required String privateKeyHex,
    required Map<String, Object?> eventJson,
  }) {
    final anonPayload = _anonTagPayload(eventJson);
    if (anonPayload == null) {
      return _decryptLegacyZapContent(
        privateKeyHex: privateKeyHex,
        eventJson: eventJson,
      );
    }

    final eventPubkey = eventJson['pubkey'];
    if (eventPubkey is! String || !_isHex64(eventPubkey)) {
      throw const NostrCryptoException('Zap event pubkey is invalid');
    }

    final recipientPubkey = _firstTagValue(eventJson, 'p');
    if (!_isHex64(recipientPubkey)) {
      throw const NostrCryptoException('Private zap recipient pubkey missing');
    }

    final signerPubkey = derivePublicKey(privateKeyHex);
    final decryptKey = recipientPubkey!.toLowerCase() == signerPubkey
        ? privateKeyHex
        : _senderPrivateZapKey(
            privateKeyHex: privateKeyHex,
            eventJson: eventJson,
            recipientPubkey: recipientPubkey,
            eventPubkey: eventPubkey,
          );
    final peerPubkey = recipientPubkey.toLowerCase() == signerPubkey
        ? eventPubkey
        : recipientPubkey;

    final decrypted = anonPayload.contains('?iv=')
        ? nip04Decrypt(
            privateKeyHex: decryptKey,
            peerPubkeyHex: peerPubkey,
            ciphertext: anonPayload,
          )
        : _decryptPrivateZapMessage(
            encryptedPayload: anonPayload,
            privateKeyHex: decryptKey,
            peerPubkeyHex: peerPubkey,
          );

    final decoded = jsonDecode(decrypted);
    if (decoded is! Map<String, Object?> || decoded['kind'] != 9733) {
      throw const NostrCryptoException('Decrypted event is not a private zap');
    }
    return jsonEncode(decoded);
  }

  @override
  bool verifySignedEvent(SignedNostrEvent event) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      event.createdAt * 1000,
      isUtc: true,
    );
    final expectedId = NostrEvent.getEventId(
      kind: event.kind,
      content: event.content,
      createdAt: createdAt,
      tags: event.tags,
      pubkey: event.pubkey,
    );

    if (expectedId != event.id) return false;

    return NostrKeyPairs.verify(event.pubkey, event.id, event.sig);
  }

  String _decryptLegacyZapContent({
    required String privateKeyHex,
    required Map<String, Object?> eventJson,
  }) {
    final content = eventJson['content'];
    final pubkey = eventJson['pubkey'];
    if (content is! String || content.trim().isEmpty) {
      throw const NostrCryptoException('Zap event content is missing');
    }
    if (pubkey is! String || !_isHex64(pubkey)) {
      throw const NostrCryptoException('Zap event pubkey is invalid');
    }
    return nip44Decrypt(
      privateKeyHex: privateKeyHex,
      peerPubkeyHex: pubkey,
      ciphertext: content,
    );
  }

  String _senderPrivateZapKey({
    required String privateKeyHex,
    required Map<String, Object?> eventJson,
    required String recipientPubkey,
    required String eventPubkey,
  }) {
    final createdAt = _eventCreatedAt(eventJson);
    final zappedPost = _firstTagValue(eventJson, 'e');
    final idToGeneratePrivateKey = zappedPost ?? recipientPubkey;
    final altPrivateKey = crypto.sha256
        .convert(utf8.encode('$privateKeyHex$idToGeneratePrivateKey$createdAt'))
        .toString();
    final altPubkey = derivePublicKey(altPrivateKey);
    if (altPubkey != eventPubkey.toLowerCase()) {
      throw const NostrCryptoException(
        'This private zap cannot be decrypted by this key',
      );
    }
    return altPrivateKey;
  }

  String _decryptPrivateZapMessage({
    required String encryptedPayload,
    required String privateKeyHex,
    required String peerPubkeyHex,
  }) {
    final parts = encryptedPayload.split('_');
    if (parts.length != 2) {
      throw const NostrCryptoException('Invalid private zap payload format');
    }
    final encrypted = _bech32PayloadBytes(parts[0], expectedHrp: 'pzap');
    final iv = _bech32PayloadBytes(parts[1], expectedHrp: 'iv');
    if (iv.length != 16) {
      throw const NostrCryptoException('Invalid private zap IV length');
    }
    final sharedX = _sharedSecretX(privateKeyHex, peerPubkeyHex);
    final decrypted = _aes256Cbc(false, sharedX, iv, encrypted);
    return utf8.decode(decrypted);
  }

  String? _anonTagPayload(Map<String, Object?> eventJson) =>
      _firstTagValue(eventJson, 'anon');

  String? _firstTagValue(Map<String, Object?> eventJson, String tagName) {
    final tags = eventJson['tags'];
    if (tags is! List) return null;
    for (final tag in tags) {
      if (tag is List && tag.length > 1 && tag.first == tagName) {
        final value = tag[1];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  int _eventCreatedAt(Map<String, Object?> eventJson) {
    final createdAt = eventJson['created_at'];
    if (createdAt is int) return createdAt;
    if (createdAt is num) return createdAt.toInt();
    throw const NostrCryptoException('Private zap created_at is missing');
  }

  Uint8List _bech32PayloadBytes(String payload, {required String expectedHrp}) {
    final decoded = bech32.bech32.decode(payload, payload.length + 1);
    if (decoded.hrp != expectedHrp) {
      throw NostrCryptoException('Expected $expectedHrp bech32 payload');
    }
    return Uint8List.fromList(_convertBits(decoded.data, 5, 8, pad: false));
  }

  List<int> _convertBits(
    List<int> data,
    int fromBits,
    int toBits, {
    required bool pad,
  }) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;
    final maxAcc = (1 << (fromBits + toBits - 1)) - 1;
    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw const NostrCryptoException('Invalid bech32 payload bits');
      }
      acc = ((acc << fromBits) | value) & maxAcc;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) result.add((acc << (toBits - bits)) & maxv);
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw const NostrCryptoException('Invalid bech32 payload padding');
    }
    return result;
  }

  String _nip44EncryptWithConversationKey({
    required Uint8List conversationKey,
    required Uint8List nonce,
    required String plaintext,
  }) {
    if (nonce.length != 32) {
      throw const NostrCryptoException('Invalid NIP-44 nonce length');
    }
    final keys = _nip44MessageKeys(conversationKey, nonce);
    final padded = _nip44Pad(plaintext);
    final ciphertext = _chacha20(keys.chachaKey, keys.chachaNonce, padded);
    final mac = _hmacSha256(
      keys.hmacKey,
      Uint8List.fromList(nonce + ciphertext),
    );
    return base64Encode(Uint8List.fromList([2] + nonce + ciphertext + mac));
  }

  String _nip44DecryptWithConversationKey({
    required Uint8List conversationKey,
    required String payload,
  }) {
    if (payload.isEmpty || payload.startsWith('#')) {
      throw const NostrCryptoException('Unsupported NIP-44 payload version');
    }
    if (payload.length < 132 || payload.length > 87472) {
      throw const NostrCryptoException('Invalid NIP-44 payload size');
    }
    final data = base64Decode(payload);
    if (data.length < 99 || data.length > 65603) {
      throw const NostrCryptoException('Invalid NIP-44 data size');
    }
    if (data.first != 2) {
      throw const NostrCryptoException('Unsupported NIP-44 payload version');
    }
    final nonce = Uint8List.fromList(data.sublist(1, 33));
    final ciphertext = Uint8List.fromList(data.sublist(33, data.length - 32));
    final mac = Uint8List.fromList(data.sublist(data.length - 32));
    final keys = _nip44MessageKeys(conversationKey, nonce);
    final calculatedMac = _hmacSha256(
      keys.hmacKey,
      Uint8List.fromList(nonce + ciphertext),
    );
    if (!_constantTimeEquals(mac, calculatedMac)) {
      throw const NostrCryptoException('Invalid NIP-44 MAC');
    }
    final padded = _chacha20(keys.chachaKey, keys.chachaNonce, ciphertext);
    return _nip44Unpad(padded);
  }

  Uint8List _nip44ConversationKey(String privateKeyHex, String peerPubkeyHex) {
    final sharedX = _sharedSecretX(privateKeyHex, peerPubkeyHex);
    return _hkdfExtract(utf8.encode('nip44-v2'), sharedX);
  }

  _Nip44MessageKeys _nip44MessageKeys(
    Uint8List conversationKey,
    Uint8List nonce,
  ) {
    if (conversationKey.length != 32 || nonce.length != 32) {
      throw const NostrCryptoException('Invalid NIP-44 key material');
    }
    final expanded = _hkdfExpand(conversationKey, nonce, 76);
    return _Nip44MessageKeys(
      chachaKey: Uint8List.fromList(expanded.sublist(0, 32)),
      chachaNonce: Uint8List.fromList(expanded.sublist(32, 44)),
      hmacKey: Uint8List.fromList(expanded.sublist(44, 76)),
    );
  }

  Uint8List _nip44Pad(String plaintext) {
    final bytes = utf8.encode(plaintext);
    final length = bytes.length;
    if (length < 1 || length > 65535) {
      throw const NostrCryptoException('Invalid NIP-44 plaintext length');
    }
    final paddedLength = _nip44PaddedLength(length);
    return Uint8List.fromList([
      (length >> 8) & 0xff,
      length & 0xff,
      ...bytes,
      ...List<int>.filled(paddedLength - length, 0),
    ]);
  }

  String _nip44Unpad(Uint8List padded) {
    if (padded.length < 34) {
      throw const NostrCryptoException('Invalid NIP-44 padding');
    }
    final length = (padded[0] << 8) | padded[1];
    if (length < 1 || length > 65535) {
      throw const NostrCryptoException('Invalid NIP-44 plaintext length');
    }
    if (padded.length != 2 + _nip44PaddedLength(length)) {
      throw const NostrCryptoException('Invalid NIP-44 padding length');
    }
    return utf8.decode(padded.sublist(2, 2 + length));
  }

  int _nip44PaddedLength(int unpaddedLength) {
    if (unpaddedLength <= 32) return 32;
    final nextPower = 1 << (unpaddedLength - 1).bitLength;
    final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
    return chunk * (((unpaddedLength - 1) ~/ chunk) + 1);
  }

  Uint8List _sharedSecretX(String privateKeyHex, String peerPubkeyHex) {
    final privateScalar = _privateScalar(privateKeyHex);
    final peerPoint = _xOnlyPublicKeyToPoint(peerPubkeyHex);
    final sharedPoint = (peerPoint * privateScalar)!;
    if (sharedPoint.isInfinity) {
      throw const NostrCryptoException('Invalid shared secret');
    }
    return _bigIntTo32Bytes(sharedPoint.x!.toBigInteger()!);
  }

  BigInt _privateScalar(String privateKeyHex) {
    if (!_isHex64(privateKeyHex)) {
      throw const NostrCryptoException('Invalid private key');
    }
    final scalar = BigInt.parse(privateKeyHex, radix: 16);
    if (scalar < BigInt.one || scalar >= _curveN) {
      throw const NostrCryptoException('Invalid private key');
    }
    return scalar;
  }

  ECPoint _xOnlyPublicKeyToPoint(String publicKeyHex) {
    if (!_isHex64(publicKeyHex)) {
      throw const NostrCryptoException('Invalid public key');
    }
    final x = BigInt.parse(publicKeyHex, radix: 16);
    if (x >= _curveP) {
      throw const NostrCryptoException('Invalid public key');
    }
    final ySq = (x.modPow(BigInt.from(3), _curveP) + BigInt.from(7)) % _curveP;
    final y = ySq.modPow((_curveP + BigInt.one) ~/ BigInt.from(4), _curveP);
    if (y.modPow(BigInt.two, _curveP) != ySq) {
      throw const NostrCryptoException('Invalid public key');
    }
    final evenY = y.isEven ? y : _curveP - y;
    return _secp256k1.curve.createPoint(x, evenY);
  }

  Uint8List _aes256Cbc(
    bool forEncryption,
    Uint8List key,
    Uint8List iv,
    List<int> input,
  ) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            forEncryption,
            PaddedBlockCipherParameters<
              ParametersWithIV<KeyParameter>,
              KeyParameter
            >(ParametersWithIV<KeyParameter>(KeyParameter(key), iv), null),
          );
    return cipher.process(Uint8List.fromList(input));
  }

  Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List input) {
    final cipher = ChaCha7539Engine()
      ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), nonce));
    return cipher.process(input);
  }

  Uint8List _hkdfExtract(List<int> salt, List<int> ikm) {
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, salt).convert(ikm).bytes,
    );
  }

  Uint8List _hkdfExpand(List<int> prk, List<int> info, int length) {
    final result = <int>[];
    var previous = <int>[];
    var counter = 1;
    while (result.length < length) {
      previous = crypto.Hmac(
        crypto.sha256,
        prk,
      ).convert([...previous, ...info, counter]).bytes;
      result.addAll(previous);
      counter += 1;
    }
    return Uint8List.fromList(result.take(length).toList());
  }

  Uint8List _hmacSha256(List<int> key, List<int> message) {
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, key).convert(message).bytes,
    );
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i += 1) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Uint8List _bigIntTo32Bytes(BigInt value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  void _validatePlaintext(String plaintext) {
    if (plaintext.isEmpty) {
      throw const NostrCryptoException('Plaintext must not be empty');
    }
  }

  bool _isHex64(String? value) =>
      value != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}

class _Nip44MessageKeys {
  final Uint8List chachaKey;
  final Uint8List chachaNonce;
  final Uint8List hmacKey;

  const _Nip44MessageKeys({
    required this.chachaKey,
    required this.chachaNonce,
    required this.hmacKey,
  });
}

class NostrCryptoException implements Exception {
  final String message;

  const NostrCryptoException(this.message);

  @override
  String toString() => 'NostrCryptoException: $message';
}
