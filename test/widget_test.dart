import 'package:flutter_test/flutter_test.dart';
import 'package:android_diogel/app/app.dart';

void main() {
  testWidgets('app smoke test renders Android Diogel unlock screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DiogelApp());

    expect(find.text('Android Diogel'), findsOneWidget);
    expect(find.text('Unlock Vault'), findsWidgets);
    expect(find.text('Enter security PIN to continue'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
  });
}
