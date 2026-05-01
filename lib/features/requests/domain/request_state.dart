import 'request_failure.dart';
import 'signed_nostr_event.dart';
import 'signing_request.dart';

class RequestState {
  final List<SigningRequest> requests;
  final bool isLoading;
  final RequestFailure? failure;
  final Map<String, SignedNostrEvent> signedEvents;

  const RequestState({
    required this.requests,
    this.isLoading = false,
    this.failure,
    this.signedEvents = const {},
  });

  RequestState copyWith({
    List<SigningRequest>? requests,
    bool? isLoading,
    RequestFailure? failure,
    bool clearFailure = false,
    Map<String, SignedNostrEvent>? signedEvents,
  }) {
    return RequestState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
      signedEvents: signedEvents ?? this.signedEvents,
    );
  }
}
