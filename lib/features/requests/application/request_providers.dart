import 'package:android_diogel/features/requests/application/request_controller.dart';
import 'package:android_diogel/features/requests/data/fake_signer_service.dart';
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
  // In a real app, this might be a production implementation
  return FakeSignerService();
});

/// Provider for the [RequestController].
final requestControllerProvider = StateNotifierProvider<RequestController, RequestState>((ref) {
  final vaultController = ref.watch(vaultControllerProvider.notifier);
  final signerService = ref.watch(signerServiceProvider);
  return RequestController(vaultController, signerService);
});

/// Provider for the current pending request.
final pendingRequestProvider = Provider<SigningRequest?>((ref) {
  final state = ref.watch(requestControllerProvider);
  try {
    return state.requests.firstWhere(
      (r) => r.status == SigningRequestStatus.pending || r.status == SigningRequestStatus.failed,
    );
  } catch (_) {
    return null;
  }
});

  /// Provider for the typed failure of the [RequestController].
final requestFailureProvider = Provider<RequestFailure?>((ref) {
  return ref.watch(requestControllerProvider).failure;
});
