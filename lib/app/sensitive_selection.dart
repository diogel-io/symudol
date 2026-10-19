import 'package:flutter/material.dart';

import 'sensitive_clipboard.dart';

/// Selectable text whose Copy is marked sensitive (diogel-io/symudol#96).
///
/// [SelectableText]'s own Copy puts the text on the clipboard inside the
/// framework, which skips [copySensitiveText], so Android 13+ would show it in
/// the clipboard preview. Here the toolbar Copy and the keyboard shortcut both
/// copy through [copySensitiveText]. A failed copy copies nothing.
class SensitiveSelectableText extends StatelessWidget {
  const SensitiveSelectableText(
    this.data, {
    super.key,
    this.style,
    this.label = 'Request payload',
  });

  final String data;
  final TextStyle? style;

  /// The clip label Android shows with the copy.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {CopySelectionTextIntent: _SensitiveCopyAction(label)},
      child: SelectableText(
        data,
        style: style,
        contextMenuBuilder: (context, state) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: [
              for (final item in state.contextMenuButtonItems)
                if (item.type == ContextMenuButtonType.copy)
                  item.copyWith(
                    onPressed: () {
                      state.hideToolbar();
                      _copySelection(state, label);
                    },
                  )
                else if (item.type != ContextMenuButtonType.cut)
                  item,
            ],
          );
        },
      ),
    );
  }
}

/// Context menu for a field that holds a secret, such as a private key
/// (diogel-io/symudol#96).
///
/// It offers only Paste and Select all. Copy and Cut would put the secret on
/// the clipboard unmarked, and Share or text-processing actions would hand it
/// to another app. Pair it with [NoSelectionCopy] to block the keyboard
/// shortcuts too.
Widget noCopyContextMenuBuilder(BuildContext context, EditableTextState state) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: state.contextMenuButtonItems
        .where(
          (item) =>
              item.type == ContextMenuButtonType.paste ||
              item.type == ContextMenuButtonType.selectAll,
        )
        .toList(),
  );
}

/// Turns off the copy and cut keyboard shortcuts for the text fields below it
/// (diogel-io/symudol#96).
class NoSelectionCopy extends StatelessWidget {
  const NoSelectionCopy({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (_) => null,
        ),
      },
      child: child,
    );
  }
}

/// Copies the keyboard selection through [copySensitiveText]. It overrides the
/// [EditableText] default, which copies unmarked.
class _SensitiveCopyAction extends ContextAction<CopySelectionTextIntent> {
  _SensitiveCopyAction(this.label);

  final String label;

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final state = context?.findAncestorStateOfType<EditableTextState>();
    if (state != null) _copySelection(state, label);
    return null;
  }
}

Future<void> _copySelection(EditableTextState state, String label) async {
  final value = state.textEditingValue;
  if (!value.selection.isValid || value.selection.isCollapsed) return;
  try {
    await copySensitiveText(value.selection.textInside(value.text), label: label);
  } catch (_) {
    // Never retried unmarked; the user can copy again.
  }
}
