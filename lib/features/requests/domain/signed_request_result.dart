import 'request_failure.dart';
import 'signed_nostr_event.dart';

sealed class SignedRequestResult {
  const SignedRequestResult();
}

class SignedRequestSuccess extends SignedRequestResult {
  final String signature;
  final Map<String, Object?> signedPayload;
  final SignedNostrEvent? event;

  const SignedRequestSuccess({
    required this.signature,
    required this.signedPayload,
    this.event,
  });

  factory SignedRequestSuccess.fromEvent(SignedNostrEvent event) {
    return SignedRequestSuccess(
      signature: event.sig,
      signedPayload: event.toJson(),
      event: event,
    );
  }
}

class SignedRequestFailure extends SignedRequestResult {
  final RequestFailure failure;

  const SignedRequestFailure(this.failure);
}
