import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity parses browser NIP-55 return URL params', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('data.getQueryParameter("callbackUrl")'));
    expect(mainActivity, contains('data.getQueryParameter("returnType")'));
    expect(mainActivity, contains('data.getQueryParameter("compressionType")'));
    expect(mainActivity, contains('data.getQueryParameter("type")'));
    expect(mainActivity, contains('substringBefore("?")'));
  });

  test('MainActivity supports callback launch and clipboard fallback', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/io/threenine/androidiogel/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('maybeLaunchCallback(extras)'));
    expect(mainActivity, contains('appendQueryParameter("result", result)'));
    expect(
      mainActivity,
      contains('Intent(Intent.ACTION_VIEW, uriBuilder.build())'),
    );
    expect(mainActivity, contains('maybeCopyToClipboard(extras)'));
    expect(mainActivity, contains('ClipboardManager'));
    expect(mainActivity, contains('ClipData.newPlainText'));
  });
}
