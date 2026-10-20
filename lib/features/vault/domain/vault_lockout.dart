import 'package:symudol/features/vault/domain/monotonic_clock.dart';

/// A PIN lockout timed on the monotonic clock (#16).
///
/// It starts at [startElapsedMs] on boot [bootCount] and lasts [durationMs].
class VaultLockout {
  final int bootCount;
  final int startElapsedMs;
  final int durationMs;

  const VaultLockout({
    required this.bootCount,
    required this.startElapsedMs,
    required this.durationMs,
  });

  /// A lockout of [duration] starting at [now].
  factory VaultLockout.startingAt(MonotonicInstant now, Duration duration) =>
      VaultLockout(
        bootCount: now.bootCount,
        startElapsedMs: now.elapsedMs,
        durationMs: duration.inMilliseconds,
      );

  Duration get duration => Duration(milliseconds: durationMs);

  /// Whether [now] can be measured against this lockout: the same boot, and
  /// the elapsed clock has not gone backwards.
  bool isComparableWith(MonotonicInstant now) =>
      now.bootCount == bootCount && now.elapsedMs >= startElapsedMs;

  /// The time left at [now], clamped to `[0, duration]`.
  ///
  /// After a reboot (or if the clock went backwards) the time already served
  /// cannot be known, so the whole [duration] is left: a reboot restarts the
  /// lockout rather than ending it.
  Duration remainingAt(MonotonicInstant now) {
    if (!isComparableWith(now)) return duration;
    final remainingMs = durationMs - (now.elapsedMs - startElapsedMs);
    return Duration(milliseconds: remainingMs.clamp(0, durationMs));
  }

  Map<String, dynamic> toJson() => {
    'bootCount': bootCount,
    'startElapsedMs': startElapsedMs,
    'durationMs': durationMs,
  };

  factory VaultLockout.fromJson(Map<String, dynamic> json) => VaultLockout(
    bootCount: json['bootCount'] as int,
    startElapsedMs: json['startElapsedMs'] as int,
    durationMs: json['durationMs'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is VaultLockout &&
      other.bootCount == bootCount &&
      other.startElapsedMs == startElapsedMs &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(bootCount, startElapsedMs, durationMs);
}
