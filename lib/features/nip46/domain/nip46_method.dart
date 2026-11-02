enum Nip46Method {
  connect,
  getPublicKey,
  ping,
  signEvent,
  nip04Encrypt,
  nip04Decrypt,
  nip44Encrypt,
  nip44Decrypt,
  switchRelays,
  logout,
  getRelays,
  decryptZapEvent,
  unsupported;

  static Nip46Method fromWire(String? wire) {
    return switch (wire) {
      'connect' => connect,
      'get_public_key' => getPublicKey,
      'ping' => ping,
      'sign_event' => signEvent,
      'nip04_encrypt' => nip04Encrypt,
      'nip04_decrypt' => nip04Decrypt,
      'nip44_encrypt' => nip44Encrypt,
      'nip44_decrypt' => nip44Decrypt,
      'switch_relays' => switchRelays,
      'logout' => logout,
      'get_relays' => getRelays,
      'decrypt_zap_event' => decryptZapEvent,
      _ => unsupported,
    };
  }

  String get wireName => switch (this) {
    connect => 'connect',
    getPublicKey => 'get_public_key',
    ping => 'ping',
    signEvent => 'sign_event',
    nip04Encrypt => 'nip04_encrypt',
    nip04Decrypt => 'nip04_decrypt',
    nip44Encrypt => 'nip44_encrypt',
    nip44Decrypt => 'nip44_decrypt',
    switchRelays => 'switch_relays',
    logout => 'logout',
    getRelays => 'get_relays',
    decryptZapEvent => 'decrypt_zap_event',
    unsupported => 'unsupported',
  };

  /// The label the approval screen shows for a request to review.
  String get displayLabel => switch (this) {
    signEvent => 'Sign Event',
    nip04Encrypt => 'NIP-04 Encrypt',
    nip04Decrypt => 'NIP-04 Decrypt',
    nip44Encrypt => 'NIP-44 Encrypt',
    nip44Decrypt => 'NIP-44 Decrypt',
    decryptZapEvent => 'Decrypt Zap Event',
    _ => wireName,
  };

  bool get isDecrypt => switch (this) {
    nip04Decrypt || nip44Decrypt || decryptZapEvent => true,
    _ => false,
  };
}
