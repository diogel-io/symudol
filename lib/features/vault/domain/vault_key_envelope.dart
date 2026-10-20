import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/features/vault/domain/vault_crypto_service.dart';

/// Everything needed to turn the PIN back into the DEK: the Argon2id salt and
/// parameters, and the DEK wrapped with the resulting KEK.
///
/// It is stored as one value so a re-wrap (a KDF upgrade, or a PIN change) is
/// a single write: there is never a salt from one wrap beside a DEK from
/// another (#16).
class VaultKeyEnvelope {
  final Uint8List salt;
  final VaultKdfParams params;
  final String wrappedDek;

  const VaultKeyEnvelope({
    required this.salt,
    required this.params,
    required this.wrappedDek,
  });

  Map<String, dynamic> toJson() => {
    'salt': base64Encode(salt),
    'params': params.toJson(),
    'wrappedDek': wrappedDek,
  };

  factory VaultKeyEnvelope.fromJson(Map<String, dynamic> json) =>
      VaultKeyEnvelope(
        salt: base64Decode(json['salt'] as String),
        params: VaultKdfParams.fromJson(json['params'] as Map<String, dynamic>),
        wrappedDek: json['wrappedDek'] as String,
      );
}
