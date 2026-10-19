import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/sensitive_clipboard.dart';
import 'package:symudol/app/sensitive_selection.dart';

/// Text selection never puts sensitive text on the clipboard unmarked
/// (diogel-io/symudol#96).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> sensitiveCopies;
  late List<MethodCall> plainCopies;

  setUp(() {
    sensitiveCopies = [];
    plainCopies = [];
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, (call) async {
      sensitiveCopies.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plainCopies.add(call);
      if (call.method == 'Clipboard.hasStrings') return {'value': false};
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(sensitiveClipboardChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('SensitiveSelectableText', () {
    testWidgets('toolbar Copy goes through the sensitive helper', (tester) async {
      await tester.pumpWidget(app(const SensitiveSelectableText('SELECTMARKER96')));

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(sensitiveCopies, hasLength(1));
      expect(sensitiveCopies.single.arguments, {
        'label': 'Request payload',
        'text': 'SELECTMARKER96',
      });
      expect(plainCopies, isEmpty);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Ctrl+C goes through the sensitive helper', (tester) async {
      await tester.pumpWidget(app(const SensitiveSelectableText('SELECTMARKER96')));

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();
      await pressCtrl(tester, LogicalKeyboardKey.keyC);

      expect(sensitiveCopies, hasLength(1));
      expect(sensitiveCopies.single.arguments['text'], 'SELECTMARKER96');
      expect(plainCopies, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('noCopyContextMenuBuilder and NoSelectionCopy', () {
    Widget secretField(TextEditingController controller) => NoSelectionCopy(
      child: TextField(
        controller: controller,
        contextMenuBuilder: noCopyContextMenuBuilder,
      ),
    );

    testWidgets('a plain field offers Copy, so the checks below mean something', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'nsec1secret');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(TextField(controller: controller)));

      await tester.longPressAt(tester.getRect(find.byType(EditableText)).centerLeft + const Offset(16, 0));
      await tester.pumpAndSettle();

      expect(controller.selection.isCollapsed, isFalse);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('the toolbar offers no Copy, Cut or Share', (tester) async {
      final controller = TextEditingController(text: 'nsec1secret');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(secretField(controller)));

      await tester.longPressAt(tester.getRect(find.byType(EditableText)).centerLeft + const Offset(16, 0));
      await tester.pumpAndSettle();

      expect(controller.selection.isCollapsed, isFalse);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('Ctrl+C and Ctrl+X copy nothing', (tester) async {
      final controller = TextEditingController(text: 'nsec1secret');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(secretField(controller)));

      await tester.longPressAt(tester.getRect(find.byType(EditableText)).centerLeft + const Offset(16, 0));
      await tester.pumpAndSettle();
      expect(controller.selection.isCollapsed, isFalse);
      await pressCtrl(tester, LogicalKeyboardKey.keyC);
      await pressCtrl(tester, LogicalKeyboardKey.keyX);

      expect(plainCopies, isEmpty);
      expect(sensitiveCopies, isEmpty);
      expect(controller.text, 'nsec1secret');
    });
  });
}
