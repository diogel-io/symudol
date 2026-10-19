import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/diogel_log.dart';

/// Symudol's Dart logging (SR-21, diogel-io/symudol#14): errors by type
/// only, and every log going through [diogelLog].
void main() {
  test('an error is logged by its type, never its message', () {
    const secret = 'SECRET-MARKER-7f3a';
    final line = diogelLogLine(
      'Nip46Controller: failed to decrypt',
      error: const FormatException('Unexpected character: $secret'),
    );

    expect(line, 'Nip46Controller: failed to decrypt (FormatException)');
    expect(line, isNot(contains(secret)));
  });

  test('a message with no error is logged as it is', () {
    expect(diogelLogLine('Vault locked'), 'Vault locked');
  });

  test('only diogelLog writes logs under lib/', () {
    final direct = RegExp(r'\b(debugPrint|print|dev\.log|log)\(');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('diogel_log.dart'))
        .where((f) => f.readAsLinesSync().any(
              (line) => !line.trimLeft().startsWith('//') && direct.hasMatch(line),
            ))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty, reason: 'call diogelLog instead');
  });
}
