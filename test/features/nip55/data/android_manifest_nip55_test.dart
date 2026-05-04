import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest exposes nostrsigner scheme via bridge activity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, isNot(contains('android:taskAffinity=""')));
    expect(manifest, contains('android:name=".Nip55BridgeActivity"'));
    expect(manifest, contains('android:exported="true"'));
    expect(
      manifest,
      contains(
        'android:name=".Nip55BridgeActivity"\n            android:exported="true"\n            android:launchMode="singleTop"',
      ),
    );
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android:scheme="nostrsigner"'));
    expect(manifest, contains('android:theme="@style/Nip55BridgeTheme"'));

    final lightStyles = File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsStringSync();
    final nightStyles = File(
      'android/app/src/main/res/values-night/styles.xml',
    ).readAsStringSync();
    expect(lightStyles, contains('style name="Nip55BridgeTheme"'));
    expect(lightStyles, contains('android:windowIsTranslucent'));
    expect(nightStyles, contains('style name="Nip55BridgeTheme"'));
    expect(nightStyles, contains('android:windowIsTranslucent'));
  });
}
