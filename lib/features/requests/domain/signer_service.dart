import 'signed_request_result.dart';
import 'signing_request.dart';

abstract interface class SignerService {
  Future<SignedRequestResult> sign(SigningRequest request);

  /// Returns true if this is a demo/fake signer.
  bool get isDemo;
}
