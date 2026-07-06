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
}
