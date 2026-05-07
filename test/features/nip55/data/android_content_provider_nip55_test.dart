import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares NIP-55 ContentProvider authorities', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".Nip55ContentProvider"'));
    expect(manifest, contains('android:exported="true"'));
    expect(manifest, contains('io.threenine.diogel.SIGN_EVENT'));
    expect(manifest, contains('io.threenine.diogel.SIGN_MESSAGE'));
    expect(manifest, contains('io.threenine.diogel.NIP44_ENCRYPT'));
    expect(manifest, contains('io.threenine.diogel.NIP44_DECRYPT'));
    expect(manifest, contains('io.threenine.diogel.NIP04_ENCRYPT'));
    expect(manifest, contains('io.threenine.diogel.NIP04_DECRYPT'));
    expect(manifest, contains('io.threenine.diogel.DECRYPT_ZAP_EVENT'));
    expect(manifest, contains('io.threenine.diogel.GET_PUBLIC_KEY'));
    expect(manifest, contains('io.threenine.diogel.PING'));
  });

  test('ContentProvider bridges warm-session queries without launching UI', () {
    final provider = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55ContentProvider.kt',
    ).readAsStringSync();

    expect(
      provider,
      contains('class Nip55ContentProvider : ContentProvider()'),
    );
    expect(provider, contains('Nip55ProviderBridge.query'));
    expect(provider, contains('signEventCursor(operationResult, eventJson)'));
    expect(provider, contains('operationResultCursor(operationResult)'));
    expect(provider, contains('?: return null'));
    expect(provider, isNot(contains('Request timed out or Diogel is busy')));
    expect(provider, isNot(contains('startActivity')));
    expect(provider, contains('hasRequiredProjection(method, projection)'));
    expect(provider, contains('"nip44_encrypt"'));
    expect(provider, contains('"sign_message"'));
    expect(provider, contains('"nip04_decrypt"'));
    expect(provider, contains('"decrypt_zap_event"'));
  });

  test('MainActivity attaches provider bridge to Flutter channel', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/diogel/MainActivity.kt',
    ).readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55ProviderBridge.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('Nip55ProviderBridge.attach(it)'));
    expect(mainActivity, contains('Nip55ProviderBridge.detach(channel)'));
    expect(bridge, contains('handleNip55ProviderQuery'));
    expect(bridge, contains('QUERY_TIMEOUT_MS'));
  });

  test('NIP-55 codec uses lowercase event result column', () {
    final codec = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55RequestCodec.kt',
    ).readAsStringSync();

    expect(
      codec,
      contains('MatrixCursor(arrayOf("signature", "result", "event"))'),
    );
    expect(codec, contains('MatrixCursor(arrayOf("rejected"))'));
    expect(codec, contains('AUTHORITY_SIGN_EVENT'));
    expect(codec, contains('AUTHORITY_SIGN_MESSAGE'));
    expect(codec, contains('AUTHORITY_SIGN_MESSAGE -> "sign_message"'));
    expect(codec, contains('peerPubkeyFromProjection'));
    expect(codec, contains('zapCurrentUserFromProjection'));

    // Workstream E: Exact authority/mapping assertions
    expect(
      codec,
      contains(
        'const val AUTHORITY_GET_PUBLIC_KEY = "io.threenine.diogel.GET_PUBLIC_KEY"',
      ),
    );
    expect(codec, contains('AUTHORITY_GET_PUBLIC_KEY -> "get_public_key"'));
    expect(
      codec,
      contains('const val AUTHORITY_PING = "io.threenine.diogel.PING"'),
    );
    expect(codec, contains('AUTHORITY_PING -> "ping"'));
  });

  test('PING is treated as a capability probe and documented', () {
    final provider = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55ContentProvider.kt',
    ).readAsStringSync();

    expect(provider, contains('if (method == "ping")'));
    expect(provider, contains('operationResultCursor("pong")'));
    expect(
      provider,
      contains('PING is treated as a stateless capability probe'),
    );
  });

  test('ContentProvider MVP deferral is documented', () {
    final doc = File(
      'documentation/nip55-contentprovider-mvp.md',
    ).readAsStringSync();

    expect(doc, contains('warm-session ContentProvider support'));
    expect(doc, contains('not cold background signing'));
    expect(doc, contains('same parser, approval policy, vault'));
    expect(doc, contains('returns `null`'));
    expect(doc, contains('Projection shape validation'));
  });
}
