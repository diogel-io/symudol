import 'signing_request.dart';

class RequestState {
  final List<SigningRequest> requests;
  final bool isLoading;

  const RequestState({
    required this.requests,
    this.isLoading = false,
  });

  RequestState copyWith({
    List<SigningRequest>? requests,
    bool? isLoading,
  }) {
    return RequestState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
