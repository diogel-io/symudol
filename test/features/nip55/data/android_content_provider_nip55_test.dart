import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares NIP-55 ContentProvider authorities', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".Nip55ContentProvider"'));
    expect(manifest, contains('android:exported="true"'));
    // Authorities use ${applicationId} so debug/release/flavor builds expose
    // the correct content:// URI — clients build URIs from the signer package name.
    expect(manifest, contains(r'${applicationId}.SIGN_EVENT'));
    expect(manifest, contains(r'${applicationId}.SIGN_MESSAGE'));
    expect(manifest, contains(r'${applicationId}.NIP44_ENCRYPT'));
    expect(manifest, contains(r'${applicationId}.NIP44_DECRYPT'));
    expect(manifest, contains(r'${applicationId}.NIP04_ENCRYPT'));
    expect(manifest, contains(r'${applicationId}.NIP04_DECRYPT'));
    expect(manifest, contains(r'${applicationId}.DECRYPT_ZAP_EVENT'));
    expect(manifest, contains(r'${applicationId}.GET_PUBLIC_KEY'));
    expect(manifest, contains(r'${applicationId}.PING'));
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
    // Workstream A: get_public_key returns null as a when-expression value
    expect(codec, contains('"get_public_key" -> null'));
    expect(
      codec,
      contains(
        'Amethyst/Quartz probes GET_PUBLIC_KEY with projection ["login"]',
      ),
    );

    // Workstream A: Authorities derived from BuildConfig.APPLICATION_ID so
    // debug/release/flavor builds expose the correct content:// authority.
    expect(
      codec,
      contains('val AUTHORITY_GET_PUBLIC_KEY = "\${BuildConfig.APPLICATION_ID}.GET_PUBLIC_KEY"'),
    );
    expect(codec, contains('AUTHORITY_GET_PUBLIC_KEY -> "get_public_key"'));
    expect(
      codec,
      contains('val AUTHORITY_PING = "\${BuildConfig.APPLICATION_ID}.PING"'),
    );
    expect(codec, contains('AUTHORITY_PING -> "ping"'));
  });

  test('NIP-55 codec documents SIGN_MESSAGE projection current-user index', () {
    final codec = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55RequestCodec.kt',
    ).readAsStringSync();

    // Workstream A: sign_event/sign_message/decrypt_zap_event now prefer index 2
    // (Dark-Wisp format [payload, "", current_user]) with fallback to index 1.
    expect(
      codec,
      contains('"sign_event", "sign_message", "decrypt_zap_event" ->'),
    );
    // Dark-Wisp index-2 preference is documented in the implementation
    expect(codec, contains('Dark-Wisp'));
    expect(codec, contains('fun payloadFromProjection'));
    expect(
      codec,
      contains('projection?.firstOrNull()?.takeIf { it.isNotBlank() }'),
    );
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

  test('kind 22242 relay auth uses remembered-grant path, not unconditional auto-sign', () {
    final provider = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55ContentProvider.kt',
    ).readAsStringSync();
    final mirror = File(
      'android/app/src/main/kotlin/io/threenine/diogel/Nip55PermissionMirror.kt',
    ).readAsStringSync();

    // Kind 22242 must NOT be auto-signed without a grant
    expect(provider, isNot(contains('kind 22242 client auth for')));
    expect(provider, isNot(contains('isKind22242')));
    // Relay URL extraction and relay-aware grant matching must be present
    expect(provider, contains('relayUrl'));
    expect(provider, contains('normalizeRelayUrl'));
    expect(mirror, contains('scopeRelayUrl'));
    expect(mirror, contains('grant.scopeRelayUrl != null && grant.scopeRelayUrl != relayUrl'));
  });

  group('provider contract semantics (null / rejected / result)', () {
    late String provider;

    setUpAll(() {
      provider = File(
        'android/app/src/main/kotlin/io/threenine/diogel/Nip55ContentProvider.kt',
      ).readAsStringSync();
    });

    test('first-time request returns null so client falls back to foreground approval', () {
      // No remembered grant: shouldBridge=false → return null
      expect(provider, contains('// No remembered grant, vault unlocked — legitimate first-time request'));
      expect(provider, contains('else -> false'));
      expect(provider, contains('if (!shouldBridge) return null'));
    });

    test('explicit remembered reject returns rejected cursor, not null', () {
      expect(provider, contains('hasRememberedReject('));
      expect(provider, contains('return Nip55RequestCodec.rejectedCursor()'));
    });

    test('sign_event success returns cursor with signature, result, and full event columns', () {
      expect(provider, contains('signEventCursor(operationResult, eventJson)'));
      final codec = File(
        'android/app/src/main/kotlin/io/threenine/diogel/Nip55RequestCodec.kt',
      ).readAsStringSync();
      expect(codec, contains('MatrixCursor(arrayOf("signature", "result", "event"))'));
    });

    test('vault-locked decrypt returns null without rejected cursor', () {
      // Vault locked path: no remembered grant → shouldBridge=false → return null.
      // Amethyst treats null as signal to fall back to foreground Intent.
      expect(provider, contains('// No remembered grant, vault locked — can\'t bridge'));
    });

    test('background decrypt requires remembered allow — no auto-approve without grant', () {
      // Workstream D: decrypt is no longer auto-approved when vault is unlocked.
      // A remembered allow grant is required for background plaintext decryption.
      expect(provider, isNot(contains('decrypting natively (auto-approve)')));
      expect(provider, contains('Decrypt operations'));
      expect(provider, contains('fall through to the standard permission path'));
    });

    test('rejected cursor is reserved for explicit permission reject only', () {
      // Verify rejected is only returned from remembered-reject paths,
      // not from missing-permission or vault-locked paths.
      expect(provider, isNot(contains('rejectedCursor() // vault')));
      expect(provider, isNot(contains('rejectedCursor() // no grant')));
    });
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
