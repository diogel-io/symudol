import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NIP-55 bridge owns caller results and MainActivity settles by token', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
    ).readAsStringSync();
    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/Nip55BridgeActivity.kt',
    ).readAsStringSync();
    final registry = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/Nip55BridgeRegistry.kt',
    ).readAsStringSync();

    expect(bridgeActivity, contains('class Nip55BridgeActivity : Activity()'));
    expect(
      bridgeActivity,
      contains('Nip55BridgeRegistry.register(token, this)'),
    );
    expect(bridgeActivity, contains('putExtra("requestToken", token)'));
    expect(mainActivity, contains('Nip55BridgeRegistry.complete'));
    expect(mainActivity, contains('Nip55BridgeRegistry.reject'));
    expect(mainActivity, contains('CompletionAction.BACKGROUND'));
    expect(mainActivity, contains('moveTaskToBack(true)'));
    expect(mainActivity, contains('postDelayed(runnable, 500L)'));
    expect(registry, contains('ConcurrentHashMap'));
  });

  test(
    'busy NIP-55 bridge request is rejected without finishing MainActivity',
    () {
      final mainActivity = File(
        'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
      ).readAsStringSync();

      expect(mainActivity, contains('if (activeRequestToken != null)'));
      expect(
        mainActivity,
        contains('Diogel is already reviewing another NIP-55 request'),
      );
      expect(mainActivity, isNot(contains('finishing here can poison')));
    },
  );
}
