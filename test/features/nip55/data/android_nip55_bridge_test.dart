import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NIP-55 bridge owns caller results and MainActivity settles by token', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/diogel/symudol/MainActivity.kt',
    ).readAsStringSync();
    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55BridgeActivity.kt',
    ).readAsStringSync();
    final registry = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55BridgeRegistry.kt',
    ).readAsStringSync();
    final uriParser = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55UriParser.kt',
    ).readAsStringSync();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(bridgeActivity, contains('class Nip55BridgeActivity : Activity()'));
    expect(
      bridgeActivity,
      contains('override fun onNewIntent(intent: Intent)'),
    );
    expect(bridgeActivity, contains('handleNip55Intent(intent)'));
    expect(
      bridgeActivity,
      contains('Nip55BridgeRegistry.register(token, this)'),
    );
    expect(
      bridgeActivity,
      contains('putExtra(getString(R.string.key_request_token), token)'),
    );
    expect(
      bridgeActivity,
      contains('original.getStringExtra(getString(R.string.key_pubkey_alt))'),
    );
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
        'Nip55UriParser.content(originalData, method, shouldUseControlQueryForContent)',
      ),
    );
    expect(uriParser, contains('controlQueryStart(raw)'));
    expect(uriParser, contains('rawQueryParameter(uri, "iv")'));
    expect(uriParser, contains(r'"$decodedPayload?iv=${Uri.decode(rawIv)}"'));
    expect(
      mainActivity,
      contains('fun deliverNip55BridgeIntent(intent: Intent)'),
    );
    expect(mainActivity, contains('private fun deliverNip55Payload'));
    expect(
      mainActivity,
      contains('deliverNip55Payload: Cancelling pending completion'),
    );
    final router = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55RequestRouter.kt',
    ).readAsStringSync();
    expect(router, contains('Nip55BridgeRegistry.complete'));
    expect(router, contains('Nip55BridgeRegistry.reject'));
    expect(mainActivity, contains('return CompletionAction.BACKGROUND'));
    expect(mainActivity, contains('CompletionAction.BACKGROUND'));
    expect(mainActivity, contains('moveTaskToBack(true)'));
    expect(mainActivity, contains('postDelayed(runnable, 150L)'));
    expect(registry, contains('ConcurrentHashMap'));
    expect(app, contains('hasPendingExternalRequest'));
    expect(
      app,
      contains('Deferring background lock while NIP-55 request is active'),
    );
  });

  // Active tokens, settling by token, and taking requests only from the bridge
  // handoff (#7) are tested on the real code in Nip55RequestRouterTest and
  // Nip55BridgeActivityTest (Robolectric, #68).
}
