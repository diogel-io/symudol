/// Tells the user a NIP-46 request is waiting while the vault is locked
/// (diogel-io/symudol#29). Shows no client name, kind or content: the name is
/// unverified and the content is private, including on the lock screen.
abstract interface class Nip46Notifier {
  /// Shows, or keeps showing, the notice for [sessionId]'s held requests.
  Future<void> showHeldRequest(String sessionId);

  /// Removes it once that session has no held request left.
  Future<void> cancelHeldRequest(String sessionId);
}

/// Shows nothing: tests, and platforms without the Android service.
class NoopNip46Notifier implements Nip46Notifier {
  const NoopNip46Notifier();

  @override
  Future<void> showHeldRequest(String sessionId) async {}

  @override
  Future<void> cancelHeldRequest(String sessionId) async {}
}

/// The Android foreground service that keeps Symudol, and so its relay
/// connections, alive while it is in the background (#29). It holds no keys
/// and does no signing.
abstract interface class Nip46BackgroundService {
  Future<void> start();
  Future<void> stop();

  /// Fires when the user taps Stop on the service's notification.
  Stream<void> get stopRequests;
}

/// Does nothing: tests, and platforms without the Android service.
class NoopNip46BackgroundService implements Nip46BackgroundService {
  const NoopNip46BackgroundService();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<void> get stopRequests => const Stream.empty();
}
