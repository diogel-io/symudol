import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NIP-55 bridge owns caller results and MainActivity settles by token', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/diogel/MainActivity.kt',
    ).readAsStringSync();
    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55BridgeActivity.kt',
    ).readAsStringSync();
    final registry = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55BridgeRegistry.kt',
    ).readAsStringSync();
    final uriParser = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55UriParser.kt',
    ).readAsStringSync();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(bridgeActivity, contains('class Nip55BridgeActivity : Activity()'));
    expect(
      bridgeActivity,
      contains('Nip55BridgeRegistry.register(token, this)'),
    );
    expect(bridgeActivity, contains('putExtra("requestToken", token)'));
    expect(bridgeActivity, contains('original.getStringExtra("pubKey")'));
    expect(mainActivity, contains('intent.getStringExtra("pubKey")'));
    expect(bridgeActivity, contains('Intent.FLAG_ACTIVITY_NEW_TASK'));
    expect(bridgeActivity, contains('Intent.FLAG_ACTIVITY_REORDER_TO_FRONT'));
    expect(bridgeActivity, isNot(contains('Intent.FLAG_ACTIVITY_CLEAR_TOP')));
    expect(bridgeActivity, contains('startActivity(mainIntent)'));
    expect(bridgeActivity, contains('postDelayed({'));
    expect(bridgeActivity, contains('MainActivity.deliverNip55BridgeIntent'));
    expect(bridgeActivity, contains('originalTypeExtra'));
    expect(bridgeActivity, contains('shouldUseControlQueryForContent'));
    expect(
      bridgeActivity,
      contains(
        'Nip55UriParser.content(originalData, originalType, shouldUseControlQueryForContent)',
      ),
    );
    expect(mainActivity, contains('parsedTypeExtra'));
    expect(uriParser, contains('controlQueryStart(raw)'));
    expect(uriParser, contains('rawQueryParameter(uri, "iv")'));
    expect(uriParser, contains(r'"$decodedPayload?iv=${Uri.decode(rawIv)}"'));
    expect(
      mainActivity,
      contains('fun deliverNip55BridgeIntent(intent: Intent)'),
    );
    expect(mainActivity, contains('private fun deliverNip55Payload'));
    expect(mainActivity, contains('Nip55BridgeRegistry.complete'));
    expect(mainActivity, contains('Nip55BridgeRegistry.reject'));
    expect(mainActivity, contains('CompletionAction.BACKGROUND'));
    expect(mainActivity, contains('moveTaskToBack(true)'));
    expect(mainActivity, contains('postDelayed(runnable, 150L)'));
    expect(registry, contains('ConcurrentHashMap'));
    expect(app, contains('hasPendingExternalRequest'));
    expect(
      app,
      contains('Skipping background lock while NIP-55 request is active'),
    );
  });

  test('NIP-55 bridge can keep multiple active tokens for burst requests', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/diogel/MainActivity.kt',
    ).readAsStringSync();

    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55BridgeActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('activeRequestTokens'));
    expect(mainActivity, contains('activeRequestTokens.add'));
    expect(mainActivity, contains('activeRequestTokens.contains'));
    expect(mainActivity, contains('clearActiveToken'));
    expect(
      bridgeActivity,
      contains('Keep this bridge activity alive because it owns the caller'),
    );
    expect(
      mainActivity,
      isNot(contains('Diogel is already reviewing another NIP-55 request')),
    );
    expect(mainActivity, isNot(contains('finishing here can poison')));
  });
}
