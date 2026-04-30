class RequestFailure {
  final String message;
  final Object? originalError;

  const RequestFailure(this.message, [this.originalError]);

  @override
  String toString() => 'RequestFailure: \$message';
}
