import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/route_pop.dart';

void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<BuildContext> pushScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Text('Root')),
    );
    late BuildContext screenContext;
    navigatorKey.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (context) {
          screenContext = context;
          return const Text('Pushed');
        },
      ),
    );
    await tester.pumpAndSettle();
    return screenContext;
  }

  testWidgets('pops the route while it is on top', (tester) async {
    final context = await pushScreen(tester);

    popIfCurrent(context, true);
    await tester.pumpAndSettle();

    expect(find.text('Pushed'), findsNothing);
    expect(find.text('Root'), findsOneWidget);
  });

  testWidgets('leaves the root alone once the route was popped (#123)', (
    tester,
  ) async {
    final context = await pushScreen(tester);
    final work = Completer<void>();

    // A lock pops everything above the root while the screen awaits work.
    navigatorKey.currentState!.popUntil((route) => route.isFirst);
    work.complete();
    await work.future;
    expect(context.mounted, isTrue, reason: 'still animating out');
    popIfCurrent(context, true);
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsOneWidget);
  });
}
