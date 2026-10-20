import 'dart:io';

import 'package:flutter/services.dart';
import 'package:symudol/features/vault/domain/monotonic_clock.dart';

/// [MonotonicClock] over Android's `elapsedRealtime` and boot count, read
/// through `MainActivity` (#16).
///
/// Other platforms fall back to wall time with a fixed boot id, so changing
/// the clock there can still shorten a lockout. Symudol ships on Android
/// only; iOS needs its own clock before it ships.
class PlatformMonotonicClock implements MonotonicClock {
  static const MethodChannel _channel = MethodChannel('io.diogel.symudol/clock');

  const PlatformMonotonicClock();

  @override
  Future<MonotonicInstant> now() async {
    if (!Platform.isAndroid) {
      return MonotonicInstant(
        elapsedMs: DateTime.now().millisecondsSinceEpoch,
        bootCount: 0,
      );
    }
    // No fallback to wall time on Android: a lockout started on one clock
    // cannot be measured on the other.
    final reading = await _channel.invokeMapMethod<String, Object?>('now');
    return MonotonicInstant(
      elapsedMs: reading!['elapsedRealtimeMs'] as int,
      bootCount: reading['bootCount'] as int,
    );
  }
}
