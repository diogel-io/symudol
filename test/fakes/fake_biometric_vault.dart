import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';

/// A [BiometricVault] the test drives by hand (#23). Each [wrap] and
/// [unwrap] stands for one system prompt.
class FakeBiometricVault implements BiometricVault {
  BiometricAvailability availabilityValue = BiometricAvailability.available;

  /// Thrown by the next prompt instead of succeeding, then cleared.
  VaultException? nextPromptError;

  /// Stands for a fingerprint added since the key was made.
  bool invalidated = false;

  bool hasKey = false;
  int prompts = 0;
  int deletes = 0;

  void _prompt() {
    prompts++;
    final error = nextPromptError;
    nextPromptError = null;
    if (error != null) throw error;
  }

  @override
  Future<BiometricAvailability> availability() async => availabilityValue;

  @override
  Future<BiometricWrap> wrap(Uint8List dek) async {
    _prompt();
    hasKey = true;
    invalidated = false;
    return BiometricWrap(iv: 'fake-iv', ciphertext: base64Encode(dek));
  }

  @override
  Future<Uint8List> unwrap(BiometricWrap wrap) async {
    if (!hasKey || invalidated) throw const BiometricKeyInvalidatedException();
    _prompt();
    return base64Decode(wrap.ciphertext);
  }

  @override
  Future<void> deleteKey() async {
    deletes++;
    hasKey = false;
  }
}
