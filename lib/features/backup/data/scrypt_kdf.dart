import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../app/utils/concurrency_utils.dart';
import '../domain/nip49.dart';

/// The channel MainActivity runs scrypt on (diogel-io/symudol#25).
const scryptChannel = MethodChannel('io.diogel.symudol/scrypt');

/// Derives NIP-49 keys from a passphrase.
abstract class Nip49KeyDeriver {
  /// The key for [passphrase] with [salt] (16 random bytes when omitted).
  Future<Nip49Key> derive(String passphrase, {int logN, Uint8List? salt});
}

/// [Nip49KeyDeriver] through Android's native scrypt, which takes a few
/// seconds where pure Dart takes 12 or more on a low-end phone. Where the
/// channel is missing (tests, other platforms), pointycastle's scrypt runs
/// off the UI isolate instead; both give the same key.
class PlatformNip49KeyDeriver implements Nip49KeyDeriver {
  const PlatformNip49KeyDeriver({MethodChannel channel = scryptChannel})
    : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<Nip49Key> derive(
    String passphrase, {
    int logN = nip49DefaultLogN,
    Uint8List? salt,
  }) async {
    final usedSalt = salt ?? nip49RandomSalt();
    final Uint8List? key;
    try {
      key = await _channel.invokeMethod<Uint8List>('derive', {
        'password': Uint8List.fromList(utf8.encode(unorm.nfkc(passphrase))),
        'salt': usedSalt,
        'n': 1 << logN,
        'r': 8,
        'p': 1,
        'dkLen': 32,
      });
    } on MissingPluginException {
      return ConcurrencyUtils.runTask(
        () => nip49DeriveKey(passphrase, logN: logN, salt: usedSalt),
      );
    } on PlatformException catch (e) {
      throw Nip49DerivationException("Couldn't derive the key: ${e.message}");
    }
    if (key == null || key.length != 32) {
      throw const Nip49DerivationException("Couldn't derive the key.");
    }
    return Nip49Key(logN, usedSalt, key);
  }
}

/// [Nip49KeyDeriver] with pointycastle's scrypt on the current isolate, for
/// tests that need it synchronous.
class DartNip49KeyDeriver implements Nip49KeyDeriver {
  const DartNip49KeyDeriver();

  @override
  Future<Nip49Key> derive(
    String passphrase, {
    int logN = nip49DefaultLogN,
    Uint8List? salt,
  }) async => nip49DeriveKey(passphrase, logN: logN, salt: salt);
}
