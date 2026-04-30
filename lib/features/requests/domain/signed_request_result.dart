import 'request_failure.dart';

sealed class SignedRequestResult {
  const SignedRequestResult();
}

class SignedRequestSuccess extends SignedRequestResult {
  final String signature;
  final Map<String, dynamic> signedPayload;

  const SignedRequestSuccess({
    required this.signature,
    required this.signedPayload,
  });
}

class SignedRequestFailure extends SignedRequestResult {
  final RequestFailure failure;

  const SignedRequestFailure(this.failure);
}
