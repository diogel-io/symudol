/// How far ahead of this phone's clock an event can be dated: relays
/// commonly refuse events more than about 15 minutes in the future.
const Duration maxEventDateAhead = Duration(minutes: 10);

/// When to date a replaceable event that replaces one created at [current]:
/// now, or a second after [current] when that is not earlier, since relays
/// keep the old event unless the new one is newer. Throws
/// [ReplaceableEventDateException] when that would date the event further
/// ahead than relays accept, because then no update can replace [current]
/// (diogel-io/symudol#118 review, #88).
DateTime createdAfter(DateTime? current, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final seconds = DateTime.fromMillisecondsSinceEpoch(
    clock.millisecondsSinceEpoch ~/ 1000 * 1000,
  );
  if (current == null || seconds.isAfter(current)) return seconds;
  final next = current.add(const Duration(seconds: 1));
  if (next.isAfter(seconds.add(maxEventDateAhead))) {
    throw const ReplaceableEventDateException();
  }
  return next;
}

/// The event being replaced is dated too far ahead of this phone's clock to
/// be replaced.
class ReplaceableEventDateException implements Exception {
  const ReplaceableEventDateException();
}
