import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/data/real_signer_service.dart';
import 'package:android_diogel/features/requests/domain/request_state.dart';
import 'package:android_diogel/features/requests/domain/signer_service.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:android_diogel/features/requests/domain/request_failure.dart';

/// Provider for the [SignerService].
final signerServiceProvider = Provider<SignerService>((ref) {
  final vaultService = ref.watch(vaultServiceProvider);
  return RealSignerService(vaultService);
});

/// Provider for the [RequestController].
final requestControllerProvider =
    StateNotifierProvider<RequestController, RequestState>((ref) {
      final vaultController = ref.watch(vaultControllerProvider.notifier);
      final signerService = ref.watch(signerServiceProvider);
      return RequestController(vaultController, signerService);
    });

/// Provider for the current active request (pending or failed).
///
/// Failed requests are kept active so that the user can see the error
/// and either retry or dismiss them. Approved signed requests are completed
/// results, not active work items, so they must not block later pending requests.
final activeRequestProvider = Provider<SigningRequest?>((ref) {
  final state = ref.watch(requestControllerProvider);
  try {
    return state.requests.firstWhere(
      (r) =>
          r.status == SigningRequestStatus.pending ||
          r.status == SigningRequestStatus.failed,
    );
  } catch (_) {
    return null;
  }
});

/// Provider for the typed failure of the [RequestController].
final requestFailureProvider = Provider<RequestFailure?>((ref) {
  return ref.watch(requestControllerProvider).failure;
});
