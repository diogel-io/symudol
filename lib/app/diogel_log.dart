import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// The only way Symudol's Dart code logs (SR-21, diogel-io/symudol#14).
///
/// Does nothing outside debug builds. [error] is logged by its type only,
/// because an exception's message can quote what it failed to parse or
/// decrypt. A [stackTrace] holds only code locations, so it is passed on.
/// Never put event content, plaintext, ciphertext, key material or
/// grant data in [message]; relay URLs, counts, methods and client package
/// names are fine, since none of this reaches a release build.
void diogelLog(String message, {Object? error, StackTrace? stackTrace}) {
  if (!kDebugMode) return;
  dev.log(
    diogelLogLine(message, error: error),
    name: 'Diogel',
    stackTrace: stackTrace,
  );
}

/// The logged text: [message], plus the type of [error] when there is one.
@visibleForTesting
String diogelLogLine(String message, {Object? error}) =>
    error == null ? message : '$message (${error.runtimeType})';
