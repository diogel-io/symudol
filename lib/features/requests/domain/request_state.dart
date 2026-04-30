import 'request_failure.dart';
import 'signing_request.dart';

class RequestState {
  final List<SigningRequest> requests;
  final bool isLoading;
  final RequestFailure? failure;

  const RequestState({
    required this.requests,
    this.isLoading = false,
    this.failure,
  });

  RequestState copyWith({
    List<SigningRequest>? requests,
    bool? isLoading,
    RequestFailure? failure,
    bool clearFailure = false,
  }) {
    return RequestState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}
