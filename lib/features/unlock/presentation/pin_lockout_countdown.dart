import 'dart:async';

import 'package:flutter/foundation.dart';

/// Shows a PIN lockout counting down (#16), for the unlock and Change PIN
/// screens (#21). The service enforces the lockout; this only displays it,
/// timed on a [Stopwatch] so it does not follow the wall clock.
class PinLockoutCountdown {
  /// Makes the stopwatch the countdown runs on. A real [Stopwatch] is
  /// monotonic; tests swap in one driven by fake time.
  @visibleForTesting
  static Stopwatch Function() stopwatchFactory = Stopwatch.new;

  /// Called every second while the countdown runs.
  final VoidCallback onTick;

  /// Called once when a running countdown reaches zero.
  final VoidCallback onEnd;

  final Stopwatch _watch = stopwatchFactory();
  Duration _lockout = Duration.zero;
  Timer? _timer;

  PinLockoutCountdown({required this.onTick, required this.onEnd});

  /// Time left, never negative.
  Duration get left {
    final left = _lockout - _watch.elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  bool get isActive => left > Duration.zero;

  /// Starts counting [remaining] down, replacing any running countdown.
  void start(Duration remaining) {
    _timer?.cancel();
    _timer = null;
    _lockout = remaining;
    _watch
      ..reset()
      ..start();
    if (remaining <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isActive) {
        timer.cancel();
        onEnd();
      }
      onTick();
    });
  }

  void dispose() => _timer?.cancel();
}
