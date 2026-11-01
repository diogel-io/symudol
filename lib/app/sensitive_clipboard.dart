import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel MainActivity answers sensitive copies on.
const sensitiveClipboardChannel = MethodChannel('io.diogel.symudol/clipboard');

/// The pending clear of an earlier copy off Android; a newer copy cancels it.
Timer? _pendingClear;

/// Puts [text] on the clipboard, marked sensitive (diogel-io/symudol#94).
///
/// On Android the copy goes through the native side, which flags the clip so
/// Android 13+ shows a redacted preview and keyboards are asked not to keep
/// it; Flutter's [Clipboard.setData] cannot set that flag. A failure is
/// thrown, never retried as an unmarked copy. Other platforms have no such
/// flag here and use [Clipboard.setData].
///
/// With [clearAfter], the clipboard is cleared after that delay, unless a
/// newer copy replaced the text (#24).
Future<void> copySensitiveText(
  String text, {
  required String label,
  Duration? clearAfter,
  MethodChannel channel = sensitiveClipboardChannel,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    _pendingClear?.cancel();
    _pendingClear = null;
    await Clipboard.setData(ClipboardData(text: text));
    if (clearAfter != null) {
      _pendingClear = Timer(clearAfter, () async {
        _pendingClear = null;
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      });
    }
    return;
  }
  await channel.invokeMethod<void>('copySensitiveText', {
    'label': label,
    'text': text,
    if (clearAfter != null) 'clearAfterMs': clearAfter.inMilliseconds,
  });
}
