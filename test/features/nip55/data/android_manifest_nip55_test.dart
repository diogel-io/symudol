import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest exposes nostrsigner scheme via bridge activity', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, contains('android:name=".Nip55BridgeActivity"'));
    expect(manifest, contains('android:exported="true"'));
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android:scheme="nostrsigner"'));
  });
}
