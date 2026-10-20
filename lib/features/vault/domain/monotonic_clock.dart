/// A reading of a clock that the user cannot change (#16).
///
/// [elapsedMs] only counts up within one boot, so [bootCount] says which boot
/// the reading belongs to. Readings from different boots cannot be compared.
class MonotonicInstant {
  final int elapsedMs;
  final int bootCount;

  const MonotonicInstant({required this.elapsedMs, required this.bootCount});

  Map<String, dynamic> toJson() => {
    'elapsedMs': elapsedMs,
    'bootCount': bootCount,
  };

  factory MonotonicInstant.fromJson(Map<String, dynamic> json) =>
      MonotonicInstant(
        elapsedMs: json['elapsedMs'] as int,
        bootCount: json['bootCount'] as int,
      );

  @override
  String toString() =>
      'MonotonicInstant(elapsedMs: $elapsedMs, bootCount: $bootCount)';
}

/// Times PIN lockouts without the wall clock, so changing the date or time in
/// Settings cannot shorten them (#16).
abstract interface class MonotonicClock {
  Future<MonotonicInstant> now();
}
