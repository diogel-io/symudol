import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Utilities for offloading work from the main UI thread.
class ConcurrencyUtils {
  /// Whether to run tasks synchronously (primarily for tests).
  @visibleForTesting
  static bool useSynchronousTasks = false;

  /// Runs [task] in a background isolate using [Isolate.run].
  ///
  /// In tests, if [useSynchronousTasks] is true, it runs the task immediately
  /// on the current isolate to avoid issues with background isolates and mocks.
  static Future<T> runTask<T>(FutureOr<T> Function() task) async {
    if (useSynchronousTasks) {
      return await task();
    }
    return await Isolate.run(task);
  }
}
