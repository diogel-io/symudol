import 'package:androidiogel/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app smoke test renders Android Diogel unlock screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Android Diogel'), findsOneWidget);
    expect(find.text('Unlock Vault'), findsWidgets);
    expect(find.text('Enter security PIN to continue'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
