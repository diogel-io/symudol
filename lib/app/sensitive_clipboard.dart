import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel MainActivity answers sensitive copies on.
const sensitiveClipboardChannel = MethodChannel('io.diogel.symudol/clipboard');

/// Puts [text] on the clipboard, marked sensitive (diogel-io/symudol#94).
///
/// On Android the copy goes through the native side, which flags the clip so
/// Android 13+ shows a redacted preview and keyboards are asked not to keep
/// it; Flutter's [Clipboard.setData] cannot set that flag. A failure is
/// thrown, never retried as an unmarked copy. Other platforms have no such
/// flag here and use [Clipboard.setData].
Future<void> copySensitiveText(
  String text, {
  required String label,
  MethodChannel channel = sensitiveClipboardChannel,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    await Clipboard.setData(ClipboardData(text: text));
    return;
  }
  await channel.invokeMethod<void>('copySensitiveText', {
    'label': label,
    'text': text,
  });
}
