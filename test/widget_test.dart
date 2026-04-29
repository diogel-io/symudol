import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_diogel/app/app.dart';

void main() {
  testWidgets('app smoke test renders Android Diogel setup screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DiogelApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Diogel'), findsOneWidget);
    expect(find.text('Local Encryption'), findsOneWidget);
    expect(find.text('No Cloud Sync'), findsOneWidget);
    expect(find.text('Create a security PIN'), findsOneWidget);
  });
}
