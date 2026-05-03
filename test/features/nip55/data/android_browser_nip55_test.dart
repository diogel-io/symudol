import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity uses shared parser for browser NIP-55 URL params', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
    ).readAsStringSync();
    final uriParser = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/Nip55UriParser.kt',
    ).readAsStringSync();

    expect(
      mainActivity,
      contains('Nip55UriParser.queryParameter(data, "callbackUrl")'),
    );
    expect(
      mainActivity,
      contains('Nip55UriParser.queryParameter(data, "returnType")'),
    );
    expect(
      mainActivity,
      contains('Nip55UriParser.queryParameter(data, "compressionType")'),
    );
    expect(
      mainActivity,
      contains('Nip55UriParser.queryParameter(data, "type")'),
    );
    expect(mainActivity, contains('Nip55UriParser.content(data)'));
    expect(uriParser, contains('if (uri.isHierarchical)'));
    expect(uriParser, contains('uri.schemeSpecificPart'));
    expect(uriParser, contains('substringBefore("?")'));
  });

  test('MainActivity supports callback launch and clipboard fallback', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('maybeLaunchCallback(extras)'));
    expect(mainActivity, contains('buildCallbackUri(callbackUrl, result, extras)'));
    expect(mainActivity, contains('callbackUrl.endsWith("=")'));
    expect(mainActivity, contains('Uri.encode(result)'));
    expect(mainActivity, contains('appendQueryParameter("result", result)'));
    expect(
      mainActivity,
      contains('Intent(Intent.ACTION_VIEW, callbackUri)'),
    );
    expect(mainActivity, contains('maybeCopyToClipboard(extras)'));
    expect(mainActivity, contains('ClipboardManager'));
    expect(mainActivity, contains('ClipData.newPlainText'));
  });
}
