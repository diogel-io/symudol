import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // How the bridge parses browser requests (URL params, BROWSABLE) is tested on
  // the real activity in Nip55BridgeActivityTest (Robolectric, #68).
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
    // The copy is marked sensitive by SensitiveClipboard (#94).
    expect(mainActivity, contains('SensitiveClipboard.copy(this, label, result)'));
    final sensitiveClipboard = File(
      'android/app/src/main/kotlin/io/diogel/symudol/SensitiveClipboard.kt',
    ).readAsStringSync();
    expect(sensitiveClipboard, contains('ClipboardManager'));
    expect(sensitiveClipboard, contains('ClipData.newPlainText'));
  });
}
