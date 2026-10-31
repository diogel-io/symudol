import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bech32/bech32.dart' as bech32;
import 'package:pointycastle/export.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// NIP-49 private key encryption (`ncryptsec`), for the vault backup
/// (diogel-io/symudol#25): scrypt derives a key from the passphrase, and
/// XChaCha20-Poly1305 encrypts the 32-byte private key.

/// The only NIP-49 version.
const int nip49Version = 0x02;

/// The scrypt cost Symudol writes: NIP-49's minimum recommendation.
const int nip49DefaultLogN = 16;

/// The largest scrypt cost a backup may ask for: `log_n` 20 is 1 GiB, which
/// NIP-49 lists as its highest example; more could exhaust a phone.
const int maxNip49LogN = 20;

/// How the key was handled before it was encrypted.
enum Nip49KeySecurity {
  /// Known to have been handled insecurely, such as stored unencrypted.
  knownInsecure(0x00),

  /// Not known to have been handled insecurely.
  notKnownInsecure(0x01),

  /// Not tracked.
  unknown(0x02);

  const Nip49KeySecurity(this.byte);

  final int byte;
}

/// An `ncryptsec` that could not be decrypted: a wrong passphrase, or one
/// that is not valid NIP-49.
class Nip49Exception implements Exception {
  const Nip49Exception(this.message);

  final String message;

  @override
  String toString() => 'Nip49Exception: $message';
}

/// A passphrase-derived key, kept so several keys can share one scrypt run.
class Nip49Key {
  const Nip49Key(this.logN, this.salt, this.symmetricKey);

  final int logN;
  final Uint8List salt;
  final Uint8List symmetricKey;
}

/// The bech32 prefix of an encrypted private key.
const String _hrp = 'ncryptsec';

/// version, log_n, salt, nonce, key security, ciphertext with its tag.
const int _payloadLength = 1 + 1 + 16 + 24 + 1 + 48;

/// Derives the key for [passphrase] with [salt] (16 random bytes when
/// omitted). Slow on purpose: about 64 MB and seconds at `log_n` 16.
Nip49Key nip49DeriveKey(
  String passphrase, {
  int logN = nip49DefaultLogN,
  Uint8List? salt,
}) {
  final usedSalt = salt ?? nip49RandomSalt();
  if (usedSalt.length != 16) {
    throw const Nip49Exception('The salt must be 16 bytes.');
  }
  final scrypt = Scrypt()
    ..init(ScryptParameters(1 << logN, 8, 1, 32, usedSalt));
  final password = Uint8List.fromList(utf8.encode(unorm.nfkc(passphrase)));
  return Nip49Key(logN, usedSalt, scrypt.process(password));
}

/// Encrypts the 32-byte [privateKey] with [key] as an `ncryptsec`.
String nip49Encrypt(
  Uint8List privateKey,
  Nip49Key key, {
  Nip49KeySecurity keySecurity = Nip49KeySecurity.unknown,
  Uint8List? nonce,
}) {
  if (privateKey.length != 32) {
    throw const Nip49Exception('A private key is 32 bytes.');
  }
  final usedNonce = nonce ?? _randomBytes(24);
  final ciphertext = _xChaCha20Poly1305(
    forEncryption: true,
    key: key.symmetricKey,
    nonce: usedNonce,
    associatedData: Uint8List.fromList([keySecurity.byte]),
    input: privateKey,
  );
  final payload = Uint8List.fromList([
    nip49Version,
    key.logN,
    ...key.salt,
    ...usedNonce,
    keySecurity.byte,
    ...ciphertext,
  ]);
  return bech32.bech32.encode(
    bech32.Bech32(_hrp, _convertBits(payload, 8, 5, pad: true)),
    200,
  );
}

/// The parts of an `ncryptsec`, before decryption.
class Nip49Payload {
  const Nip49Payload(
    this.logN,
    this.salt,
    this.nonce,
    this.keySecurity,
    this.ciphertext,
  );

  final int logN;
  final Uint8List salt;
  final Uint8List nonce;
  final int keySecurity;
  final Uint8List ciphertext;
}

/// Reads [ncryptsec] without decrypting it. Throws [Nip49Exception].
Nip49Payload nip49Parse(String ncryptsec) {
  final bech32.Bech32 decoded;
  try {
    decoded = bech32.bech32.decode(ncryptsec.trim(), 200);
  } catch (_) {
    throw const Nip49Exception('This is not an ncryptsec.');
  }
  if (decoded.hrp != _hrp) {
    throw const Nip49Exception('This is not an ncryptsec.');
  }
  final payload = Uint8List.fromList(
    _convertBits(decoded.data, 5, 8, pad: false),
  );
  if (payload.length != _payloadLength || payload[0] != nip49Version) {
    throw const Nip49Exception('This ncryptsec version is not supported.');
  }
  return Nip49Payload(
    payload[1],
    payload.sublist(2, 18),
    payload.sublist(18, 42),
    payload[42],
    payload.sublist(43),
  );
}

/// Decrypts [payload] with [key], whose salt and `log_n` must match it.
/// Throws [Nip49Exception] for a wrong passphrase.
Uint8List nip49DecryptWith(Nip49Payload payload, Nip49Key key) {
  try {
    return _xChaCha20Poly1305(
      forEncryption: false,
      key: key.symmetricKey,
      nonce: payload.nonce,
      associatedData: Uint8List.fromList([payload.keySecurity]),
      input: payload.ciphertext,
    );
  } on InvalidCipherTextException {
    throw const Nip49Exception('The passphrase does not open this key.');
  } on ArgumentError {
    // pointycastle reports a failed Poly1305 tag as an ArgumentError.
    throw const Nip49Exception('The passphrase does not open this key.');
  }
}

/// Decrypts [ncryptsec] with [passphrase]. Throws [Nip49Exception].
Uint8List nip49Decrypt(String ncryptsec, String passphrase) {
  final payload = nip49Parse(ncryptsec);
  return nip49DecryptWith(
    payload,
    nip49DeriveKey(passphrase, logN: payload.logN, salt: payload.salt),
  );
}

/// XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha-03 §2.3): HChaCha20 makes a
/// subkey from the first 16 nonce bytes, then IETF ChaCha20-Poly1305 runs
/// with four zero bytes and the last 8 nonce bytes as its nonce.
Uint8List _xChaCha20Poly1305({
  required bool forEncryption,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List associatedData,
  required Uint8List input,
}) {
  final subkey = hChaCha20(key, nonce.sublist(0, 16));
  final ietfNonce = Uint8List(12)..setRange(4, 12, nonce, 16);
  final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
    ..init(
      forEncryption,
      AEADParameters(KeyParameter(subkey), 128, ietfNonce, associatedData),
    );
  final output = Uint8List(cipher.getOutputSize(input.length));
  final length = cipher.processBytes(input, 0, input.length, output, 0);
  final total = length + cipher.doFinal(output, length);
  return output.sublist(0, total);
}

/// HChaCha20 (draft-irtf-cfrg-xchacha-03 §2.2): the ChaCha20 block function
/// on [key] and a 16-byte [nonce], returning words 0–3 and 12–15 of the
/// state without the final addition.
Uint8List hChaCha20(Uint8List key, Uint8List nonce) {
  if (key.length != 32 || nonce.length != 16) {
    throw ArgumentError('HChaCha20 takes a 32-byte key and a 16-byte nonce.');
  }
  final keyWords = ByteData.sublistView(key);
  final nonceWords = ByteData.sublistView(nonce);
  final state = Uint32List(16)
    ..[0] = 0x61707865
    ..[1] = 0x3320646e
    ..[2] = 0x79622d32
    ..[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = keyWords.getUint32(i * 4, Endian.little);
  }
  for (var i = 0; i < 4; i++) {
    state[12 + i] = nonceWords.getUint32(i * 4, Endian.little);
  }

  int rotl(int value, int bits) =>
      ((value << bits) | (value >> (32 - bits))) & 0xffffffff;
  void quarterRound(int a, int b, int c, int d) {
    state[a] = state[a] + state[b];
    state[d] = rotl(state[d] ^ state[a], 16);
    state[c] = state[c] + state[d];
    state[b] = rotl(state[b] ^ state[c], 12);
    state[a] = state[a] + state[b];
    state[d] = rotl(state[d] ^ state[a], 8);
    state[c] = state[c] + state[d];
    state[b] = rotl(state[b] ^ state[c], 7);
  }

  for (var round = 0; round < 10; round++) {
    quarterRound(0, 4, 8, 12);
    quarterRound(1, 5, 9, 13);
    quarterRound(2, 6, 10, 14);
    quarterRound(3, 7, 11, 15);
    quarterRound(0, 5, 10, 15);
    quarterRound(1, 6, 11, 12);
    quarterRound(2, 7, 8, 13);
    quarterRound(3, 4, 9, 14);
  }

  final out = ByteData(32);
  for (var i = 0; i < 4; i++) {
    out.setUint32(i * 4, state[i], Endian.little);
    out.setUint32(16 + i * 4, state[12 + i], Endian.little);
  }
  return out.buffer.asUint8List();
}

final Random _random = Random.secure();

/// 16 random bytes for a new scrypt salt.
Uint8List nip49RandomSalt() => _randomBytes(16);

Uint8List _randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

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
      throw const Nip49Exception('This is not an ncryptsec.');
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
    throw const Nip49Exception('This is not an ncryptsec.');
  }
  return result;
}
