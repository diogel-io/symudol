/// How every "unlock first" message starts. The controller recognises a
/// request held for unlock by this prefix, so the messages use it too.
const nip55UnlockMessagePrefix = 'Unlock Symudol';

class Nip55Failure {
  final String message;
  final Object? originalError;

  const Nip55Failure(this.message, [this.originalError]);

  @override
  String toString() => 'Nip55Failure: $message';
}

class Nip55ParseException implements Exception {
  final String message;

  const Nip55ParseException(this.message);

  @override
  String toString() => 'Nip55ParseException: $message';
}
