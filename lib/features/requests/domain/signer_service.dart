import 'signed_request_result.dart';
import 'signing_request.dart';

abstract interface class SignerService {
  Future<SignedRequestResult> sign(SigningRequest request);
}
