import 'package:symudol/features/vault/domain/monotonic_clock.dart';

/// A [MonotonicClock] the test moves by hand (#16).
class FakeMonotonicClock implements MonotonicClock {
  int elapsedMs;
  int bootCount;

  FakeMonotonicClock({this.elapsedMs = 1000000, this.bootCount = 1});

  void advance(Duration by) => elapsedMs += by.inMilliseconds;

  /// A reboot: the elapsed clock starts again near zero.
  void reboot({int elapsedMs = 5000}) {
    bootCount++;
    this.elapsedMs = elapsedMs;
  }

  @override
  Future<MonotonicInstant> now() async =>
      MonotonicInstant(elapsedMs: elapsedMs, bootCount: bootCount);
}
