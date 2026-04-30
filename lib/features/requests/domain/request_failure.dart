class RequestFailure {
  final String message;
  final dynamic originalError;

  const RequestFailure(this.message, [this.originalError]);

  @override
  String toString() => 'RequestFailure: \$message';
}
