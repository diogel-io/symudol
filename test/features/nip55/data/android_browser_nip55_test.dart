import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The bridge parses the request, URL params included, and hands it to
  // MainActivity through Nip55Handoff; MainActivity reads no extras (#7).
  test('Bridge uses the shared parser for browser NIP-55 URL params', () {
    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55BridgeActivity.kt',
    ).readAsStringSync();
    final uriParser = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55UriParser.kt',
    ).readAsStringSync();

    for (final key in [
      'key_callback_url',
      'key_return_type',
      'key_compression_type',
      'key_id',
    ]) {
      expect(
        bridgeActivity,
        contains(
          'Nip55UriParser.queryParameter(originalData, getString(R.string.$key))',
        ),
      );
    }
    expect(
      bridgeActivity,
      contains('Nip55UriParser.queryParameter(originalData, getString(R.string.key_type))'),
    );
    expect(bridgeActivity, contains('Nip55UriParser.content(originalData'));
    expect(uriParser, contains('if (uri.isHierarchical)'));
    expect(uriParser, contains('uri.schemeSpecificPart'));
    expect(uriParser, contains('controlQueryStart(raw)'));
  });

  test('Bridge marks browsable nostrsigner URLs as browser flow', () {
    final bridgeActivity = File(
      'android/app/src/main/kotlin/io/diogel/symudol/Nip55BridgeActivity.kt',
    ).readAsStringSync();

    expect(
      bridgeActivity,
      contains(
        '"isBrowserFlow" to original.hasCategory(Intent.CATEGORY_BROWSABLE)',
      ),
    );
  });

  test('MainActivity supports callback launch and clipboard fallback', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/diogel/symudol/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('maybeLaunchCallback(extras)'));
    expect(
      mainActivity,
      contains('buildCallbackUri(callbackUrl, result, extras)'),
    );
    expect(mainActivity, contains('callbackUrl.endsWith("=")'));
    expect(mainActivity, contains('Uri.encode(result)'));
    expect(mainActivity, contains('appendQueryParameter("result", result)'));
    expect(mainActivity, contains('Intent(Intent.ACTION_VIEW, callbackUri)'));
    expect(mainActivity, contains('maybeCopyToClipboard(extras)'));
    expect(mainActivity, contains('ClipboardManager'));
    expect(mainActivity, contains('ClipData.newPlainText'));
  });
}
