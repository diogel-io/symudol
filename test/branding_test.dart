import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is Symudol (#38). "Diogel" is the suite: it stays in identifiers
/// (`DiogelColors`, `DiogelApp`), the `io.diogel.symudol` id and log tags,
/// but never in text a user can see.
void main() {
  test('no string literal in lib/ names the app Diogel', () {
    final literal = RegExp(r'''('[^'\n]*'|"[^"\n]*")''');
    final offending = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('import ')) continue;
        for (final match in literal.allMatches(line)) {
          final text = match.group(0)!;
          if (!text.contains('Diogel') && !text.contains('diogel')) continue;
          // Log tags and the application id aren't shown to users.
          if (line.contains("name: 'Diogel'")) continue;
          if (text.contains('io.diogel.symudol')) continue;
          offending.add('${file.path}:${i + 1}: $text');
        }
      }
    }
    expect(offending, isEmpty);
  });

  test('the launcher label is Symudol', () {
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    expect(strings, contains('<string name="app_name">Symudol</string>'));
  });
}
