import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  group('Android manifest for NIP-46 pairing (#31)', () {
    test('nostrconnect: links reach MainActivity through an alias that starts off', () {
      final alias = RegExp(
        r'<activity-alias[^>]*android:name="\.Nip46LinkAlias"[\s\S]*?</activity-alias>',
      ).stringMatch(manifest);

      expect(alias, isNotNull);
      expect(alias, contains('android:targetActivity=".MainActivity"'));
      // Dart turns it on only in a build that shows NIP-46 (#26).
      expect(alias, contains('android:enabled="false"'));
      expect(alias, contains('android:exported="true"'));
      expect(alias, contains('android.intent.action.VIEW'));
      expect(alias, contains('android.intent.category.BROWSABLE'));
      expect(alias, contains('android:scheme="nostrconnect"'));
    });

    test('asks for the camera only, and runs without one', () {
      expect(manifest, contains('android.permission.CAMERA'));
      // The camera plugin's own permissions are never used.
      expect(
        manifest,
        contains(
          '"android.permission.RECORD_AUDIO" tools:node="remove"',
        ),
      );
      expect(
        manifest,
        contains(
          '"android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove"',
        ),
      );
      expect(
        manifest,
        contains(
          '"android.permission.READ_EXTERNAL_STORAGE" tools:node="remove"',
        ),
      );
      expect(
        manifest,
        matches(
          RegExp(
            r'android\.hardware\.camera\.any"\s+android:required="false"',
          ),
        ),
      );
    });
  });
}
