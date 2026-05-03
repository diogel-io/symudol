import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares NIP-55 ContentProvider authorities', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".Nip55ContentProvider"'));
    expect(manifest, contains('android:exported="true"'));
    expect(manifest, contains('io.threenine.androidiogel.SIGN_EVENT'));
    expect(manifest, contains('io.threenine.androidiogel.NIP44_ENCRYPT'));
    expect(manifest, contains('io.threenine.androidiogel.NIP44_DECRYPT'));
    expect(manifest, contains('io.threenine.androidiogel.NIP04_ENCRYPT'));
    expect(manifest, contains('io.threenine.androidiogel.NIP04_DECRYPT'));
    expect(manifest, contains('io.threenine.androidiogel.DECRYPT_ZAP_EVENT'));
  });

  test(
    'ContentProvider returns null rather than launching UI or cold signing',
    () {
      final provider = File(
        'android/app/src/main/kotlin/io/threenine/androidiogel/Nip55ContentProvider.kt',
      ).readAsStringSync();

      expect(
        provider,
        contains('class Nip55ContentProvider : ContentProvider()'),
      );
      expect(provider, contains('return null'));
      expect(provider, isNot(contains('startActivity')));
      expect(provider, contains('no remembered permission'));
    },
  );

  test('NIP-55 codec uses lowercase event result column', () {
    final codec = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/Nip55RequestCodec.kt',
    ).readAsStringSync();

    expect(codec, contains('MatrixCursor(arrayOf("result", "event"))'));
    expect(codec, contains('MatrixCursor(arrayOf("rejected"))'));
    expect(codec, contains('AUTHORITY_SIGN_EVENT'));
  });

  test('ContentProvider MVP deferral is documented', () {
    final doc = File(
      'documentation/nip55-contentprovider-mvp.md',
    ).readAsStringSync();

    expect(doc, contains('Provider auto-signing is not enabled yet'));
    expect(doc, contains('deferred safe stub'));
    expect(doc, contains('does not read that store'));
    expect(doc, contains('headless Flutter engine'));
    expect(doc, contains('return `null`'));
  });
}
