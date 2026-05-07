enum Nip55Method {
  getPublicKey,
  signMessage,
  signEvent,
  nip04Encrypt,
  nip04Decrypt,
  nip44Encrypt,
  nip44Decrypt,
  decryptZapEvent,
  unsupported;

  String get wireName {
    return switch (this) {
      Nip55Method.getPublicKey => 'get_public_key',
      Nip55Method.signMessage => 'sign_message',
      Nip55Method.signEvent => 'sign_event',
      Nip55Method.nip04Encrypt => 'nip04_encrypt',
      Nip55Method.nip04Decrypt => 'nip04_decrypt',
      Nip55Method.nip44Encrypt => 'nip44_encrypt',
      Nip55Method.nip44Decrypt => 'nip44_decrypt',
      Nip55Method.decryptZapEvent => 'decrypt_zap_event',
      Nip55Method.unsupported => 'unsupported',
    };
  }

  String get label {
    return switch (this) {
      Nip55Method.getPublicKey => 'get_public_key',
      Nip55Method.signMessage => 'sign_message',
      Nip55Method.signEvent => 'sign_event',
      Nip55Method.nip04Encrypt => 'nip04_encrypt',
      Nip55Method.nip04Decrypt => 'nip04_decrypt',
      Nip55Method.nip44Encrypt => 'nip44_encrypt',
      Nip55Method.nip44Decrypt => 'nip44_decrypt',
      Nip55Method.decryptZapEvent => 'decrypt_zap_event',
      Nip55Method.unsupported => 'unsupported',
    };
  }

  bool get requiresPeerPubkey {
    return switch (this) {
      Nip55Method.nip04Encrypt ||
      Nip55Method.nip04Decrypt ||
      Nip55Method.nip44Encrypt ||
      Nip55Method.nip44Decrypt => true,
      _ => false,
    };
  }

  static Nip55Method fromWire(String? value) {
    return switch (value) {
      'get_public_key' => Nip55Method.getPublicKey,
      'sign_message' => Nip55Method.signMessage,
      'sign_event' => Nip55Method.signEvent,
      'nip04_encrypt' => Nip55Method.nip04Encrypt,
      'nip04_decrypt' => Nip55Method.nip04Decrypt,
      'nip44_encrypt' => Nip55Method.nip44Encrypt,
      'nip44_decrypt' => Nip55Method.nip44Decrypt,
      'decrypt_zap_event' => Nip55Method.decryptZapEvent,
      _ => Nip55Method.unsupported,
    };
  }
}
