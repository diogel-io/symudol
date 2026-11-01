import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a system screen the user opened from Symudol is over it: the
/// photo picker or camera (diogel-io/symudol#43), or the backup's document
/// picker or share sheet (#25). Opening one sends Symudol to the background,
/// so the background lock waits for it, up to a bound.
final systemPickerOpenProvider =
    NotifierProvider<SystemPickerOpenNotifier, bool>(
      SystemPickerOpenNotifier.new,
    );

class SystemPickerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Runs [pick] with the flag set.
  Future<T> during<T>(Future<T> Function() pick) async {
    state = true;
    try {
      return await pick();
    } finally {
      state = false;
    }
  }
}
