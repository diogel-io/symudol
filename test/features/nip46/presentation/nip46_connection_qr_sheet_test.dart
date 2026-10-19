import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/nip46/presentation/nip46_connection_qr_sheet.dart';

void main() {
  testWidgets('the nostrconnect:// field offers no Copy or Cut (#96)', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Nip46ConnectionQrSheet())),
      ),
    );
    await tester.tap(find.text('Import nostrconnect://'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nostrconnect://abc?secret=xyz');

    // Select the URI and open the toolbar; the sheet sits in a small test view.
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    field.userUpdateTextEditingValue(
      field.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 29),
      ),
      SelectionChangedCause.longPress,
    );
    field.showToolbar();
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });
}
