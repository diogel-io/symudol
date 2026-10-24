import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this build shows NIP-46 remote signing (#26).
///
/// Android 1.0 hides it in release builds until review, saved permissions,
/// background running and vault-protected session keys land (#27, #28, #29,
/// #32). Debug and profile builds keep it for development. A release build
/// can opt in with `--dart-define=SYMUDOL_ENABLE_NIP46=true`.
const bool kNip46Enabled =
    !kReleaseMode || bool.fromEnvironment('SYMUDOL_ENABLE_NIP46');

/// [kNip46Enabled], as a provider so tests can check both states.
final nip46EnabledProvider = Provider<bool>((ref) => kNip46Enabled);
