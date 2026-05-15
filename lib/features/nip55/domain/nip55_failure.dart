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
