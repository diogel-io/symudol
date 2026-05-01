enum Nip55Method {
  getPublicKey,
  signEvent,
  unsupported;

  static Nip55Method fromWire(String? value) {
    return switch (value) {
      'get_public_key' => Nip55Method.getPublicKey,
      'sign_event' => Nip55Method.signEvent,
      _ => Nip55Method.unsupported,
    };
  }
}
