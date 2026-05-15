import 'package:android_diogel/app/utils/concurrency_utils.dart';
import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:android_diogel/features/requests/domain/request_failure.dart';
import 'package:android_diogel/features/requests/domain/signed_request_result.dart';
import 'package:android_diogel/features/requests/domain/signer_service.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/vault/domain/vault_exceptions.dart';
import 'package:android_diogel/features/vault/domain/vault_service.dart';

class RealSignerService implements SignerService {
  final VaultService _vaultService;
  final NostrEventPayloadParser _parser;

  const RealSignerService(
    this._vaultService, {
    NostrEventPayloadParser parser = const NostrEventPayloadParser(),
  }) : _parser = parser;

  @override
  bool get isDemo => false;

  @override
  Future<SignedRequestResult> sign(SigningRequest request) async {
    try {
      final parser = _parser;
      final draft = await ConcurrencyUtils.runTask(() => parser.parse(request));
      final event = await _vaultService.signNostrEvent(
        identityLocalId: request.targetIdentityLocalId,
        draft: draft,
      );
      return SignedRequestSuccess.fromEvent(event);
    } on NostrEventPayloadParseException catch (error) {
      return SignedRequestFailure(
        InvalidRequestFailure(
          'Invalid signing request: ${error.message}',
          error,
        ),
      );
    } on VaultLockedException catch (error) {
      return SignedRequestFailure(VaultLockedRequestFailure(error.message));
    } on IdentityNotFoundException catch (error) {
      return SignedRequestFailure(MissingIdentityRequestFailure(error.message));
    } on IdentityMismatchException catch (error) {
      return SignedRequestFailure(
        IdentityMismatchRequestFailure(error.message),
      );
    } on VaultSigningException catch (error) {
      return SignedRequestFailure(
        SigningFailedRequestFailure('Signing failed: ${error.message}', error),
      );
    } on VaultException catch (error) {
      return SignedRequestFailure(
        SigningFailedRequestFailure('Signing failed: ${error.message}', error),
      );
    } catch (error) {
      return SignedRequestFailure(
        SigningFailedRequestFailure('Signing failed: Unexpected error', error),
      );
    }
  }
}
