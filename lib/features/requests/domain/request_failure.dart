class RequestFailure {
  final String message;
  final Object? originalError;

  const RequestFailure(this.message, [this.originalError]);

  @override
  String toString() => 'RequestFailure: $message';
}

class InvalidRequestFailure extends RequestFailure {
  const InvalidRequestFailure(super.message, [super.originalError]);
}

class VaultLockedRequestFailure extends RequestFailure {
  const VaultLockedRequestFailure([
    super.message = 'Approval blocked: Vault is locked',
  ]);
}

class MissingIdentityRequestFailure extends RequestFailure {
  const MissingIdentityRequestFailure([
    super.message = 'Approval failed: Identity not found',
  ]);
}

class IdentityMismatchRequestFailure extends RequestFailure {
  const IdentityMismatchRequestFailure([
    super.message = 'Approval blocked: Identity mismatch',
  ]);
}

class SigningFailedRequestFailure extends RequestFailure {
  const SigningFailedRequestFailure(super.message, [super.originalError]);
}
