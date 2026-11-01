import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diogel_log.dart';

/// The channel MainActivity answers sensitive copies on.
const sensitiveClipboardChannel = MethodChannel('io.diogel.symudol/clipboard');

/// The pending clear of an earlier copy off Android; a newer copy cancels it.
Timer? _pendingClear;

/// Bumped by every copy off Android, so a clear that was already running
/// when a newer copy landed leaves that copy alone.
int _copyGeneration = 0;

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
    await Clipboard.setData(ClipboardData(text: text));
    // Only a copy that happened replaces the earlier one, and its clear.
    _pendingClear?.cancel();
    _pendingClear = null;
    final generation = ++_copyGeneration;
    if (clearAfter != null) {
      _pendingClear = Timer(clearAfter, () async {
        _pendingClear = null;
        String? current;
        try {
          current = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        } catch (_) {
          // Unreadable: clear anyway rather than leave a key behind.
          current = text;
        }
        if (generation != _copyGeneration || current != text) return;
        try {
          await Clipboard.setData(const ClipboardData(text: ''));
        } catch (e, stack) {
          diogelLog(
            'copySensitiveText: clipboard clear failed',
            error: e,
            stackTrace: stack,
          );
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
