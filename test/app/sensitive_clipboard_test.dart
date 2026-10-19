import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/sensitive_clipboard.dart';

/// Sensitive copies go to the native side on Android (diogel-io/symudol#94).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, null);
  });

  test('on Android the copy goes to the native clipboard channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, (call) async {
      calls.add(call);
      return null;
    });

    await copySensitiveText('bunker://abc?secret=xyz', label: 'bunker URI');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'copySensitiveText');
    expect(calls.single.arguments, {
      'label': 'bunker URI',
      'text': 'bunker://abc?secret=xyz',
    });
  });

  test('on Android a failed copy throws and is not retried unmarked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, (call) async {
      throw PlatformException(code: 'FAILED');
    });
    final plainCopies = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plainCopies.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await expectLater(
      copySensitiveText('secret', label: 'test'),
      throwsA(isA<PlatformException>()),
    );
    expect(plainCopies, isEmpty);
  });

  test('only sensitive_clipboard.dart calls Clipboard.setData under lib/', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('sensitive_clipboard.dart'))
        .where((f) => f.readAsStringSync().contains('Clipboard.setData'))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty, reason: 'call copySensitiveText instead');
  });

  // Framework selection copies unmarked; SensitiveSelectableText doesn't (#96).
  test('only sensitive_selection.dart builds selectable text under lib/', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('sensitive_selection.dart'))
        .where((f) => RegExp(r'\b(SelectableText|SelectionArea)\(').hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty, reason: 'use SensitiveSelectableText instead');
  });
}
