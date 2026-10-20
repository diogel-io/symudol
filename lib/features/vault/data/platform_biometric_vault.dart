import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';

/// [BiometricVault] over `BiometricVault.kt`, through `MainActivity` (#23).
///
/// Holds no state, so it is safe in the vault service that is copied into
/// background isolates. Off Android, biometric unlock is unavailable.
class PlatformBiometricVault implements BiometricVault {
  static const MethodChannel _channel = MethodChannel(
    'io.diogel.symudol/biometric',
  );

  const PlatformBiometricVault();

  @override
  Future<BiometricAvailability> availability() async {
    if (!Platform.isAndroid) return BiometricAvailability.unavailable;
    try {
      final value = await _channel.invokeMethod<String>('availability');
      return BiometricAvailability.values.firstWhere(
        (a) => a.name == value,
        orElse: () => BiometricAvailability.unavailable,
      );
    } on MissingPluginException {
      return BiometricAvailability.unavailable;
    }
  }

  @override
  Future<BiometricWrap> wrap(Uint8List dek) async {
    final result = await _call(
      () => _channel.invokeMapMethod<String, Object?>('wrap', {'dek': dek}),
    );
    return BiometricWrap(
      iv: base64Encode(result!['iv'] as Uint8List),
      ciphertext: base64Encode(result['ciphertext'] as Uint8List),
    );
  }

  @override
  Future<Uint8List> unwrap(BiometricWrap wrap) async {
    final dek = await _call(
      () => _channel.invokeMethod<Uint8List>('unwrap', {
        'iv': base64Decode(wrap.iv),
        'ciphertext': base64Decode(wrap.ciphertext),
      }),
    );
    return dek!;
  }

  @override
  Future<void> deleteKey() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('deleteKey');
    } on MissingPluginException {
      // No native side: no key.
    }
  }

  Future<T> _call<T>(Future<T> Function() call) async {
    if (!Platform.isAndroid) throw const BiometricUnavailableException();
    try {
      return await call();
    } on MissingPluginException {
      throw const BiometricUnavailableException();
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'cancelled' => const BiometricCancelledException(),
        'lockedOut' => const BiometricLockedOutException(),
        'keyInvalidated' => const BiometricKeyInvalidatedException(),
        'unavailable' => const BiometricUnavailableException(),
        _ => BiometricFailedException(e.message ?? e.code),
      };
    }
  }
}
