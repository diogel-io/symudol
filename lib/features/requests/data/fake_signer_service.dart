import '../domain/request_failure.dart';
import '../domain/signed_request_result.dart';
import '../domain/signer_service.dart';
import '../domain/signing_request.dart';

class FakeSignerService implements SignerService {
  final bool shouldFail;
  final String? customSignature;

  FakeSignerService({
    this.shouldFail = false,
    this.customSignature,
  });

  @override
  Future<SignedRequestResult> sign(SigningRequest request) async {
    await Future.delayed(const Duration(milliseconds: 100));

    if (shouldFail) {
      return const SignedRequestFailure(
        RequestFailure('Fake signer error: User cancelled or key not found'),
      );
    }

    final signature = customSignature ?? 'fake_signature_for_${request.id}';
    final signedPayload = Map<String, Object?>.from(request.eventPayload);
    signedPayload['sig'] = signature;

    return SignedRequestSuccess(
      signature: signature,
      signedPayload: signedPayload,
    );
  }
}
