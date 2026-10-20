import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/app.dart';
import 'package:symudol/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_lockout.dart';
import 'package:symudol/features/vault/presentation/vault_failure_messages.dart';

import '../../../fakes/fake_vault_store.dart';

/// The unlock screen's PIN lockout countdown and erase warning (#16).
void main() {
  late FakeVaultStore store;

  setUp(() async {
    // The countdown runs on fake time, which the tester's pumps advance.
    UnlockVaultScreen.stopwatchFactory = () => clock.stopwatch();
    store = FakeVaultStore();
    await store.setWrappedDek('wrapped-dek-placeholder');
  });

  tearDown(() => UnlockVaultScreen.stopwatchFactory = Stopwatch.new);

  /// Off Android the clock is wall time with boot 0, so a lockout starting
  /// now is one the app reads as running.
  Future<void> lockOutFor(Duration duration) => store.setLockout(
    VaultLockout(
      bootCount: 0,
      startElapsedMs: DateTime.now().millisecondsSinceEpoch,
      durationMs: duration.inMilliseconds,
    ),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultStoreProvider.overrideWithValue(store)],
        child: const DiogelApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  int filledDots(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            decoration.boxShadow != null;
      })
      .length;

  testWidgets('a lockout disables the PIN pad and counts down', (tester) async {
    await lockOutFor(const Duration(minutes: 15));
    await pumpApp(tester);

    expect(find.byType(UnlockVaultScreen), findsOneWidget);
    expect(
      find.text('Too many failed attempts. Try again in 15 minutes.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('unlockLockoutCountdown')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('unlockLockoutCountdown'))).data,
      anyOf('15:00', '14:59'),
    );

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(filledDots(tester), 0);
  });

  testWidgets('the pad comes back when the lockout ends', (tester) async {
    await lockOutFor(const Duration(seconds: 30));
    await pumpApp(tester);
    expect(find.byKey(const Key('unlockLockoutMessage')), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(
      find.text('Too many failed attempts. Try again in 1 second.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byKey(const Key('unlockLockoutMessage')), findsNothing);
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(filledDots(tester), 1);
  });

  testWidgets('warns from 3 attempts before an erase', (tester) async {
    await store.setWipeAfterFailures(10);
    await store.setFailedUnlockAttempts(7);
    await pumpApp(tester);

    expect(
      find.text('3 attempts left before Symudol erases all keys.'),
      findsOneWidget,
    );
  });

  testWidgets('no warning further from the limit, or with it off', (
    tester,
  ) async {
    await store.setWipeAfterFailures(10);
    await store.setFailedUnlockAttempts(6);
    await pumpApp(tester);

    expect(find.byKey(const Key('unlockWipeWarning')), findsNothing);
  });

  group('messages', () {
    test('round the wait up to a sensible unit', () {
      expect(formatLockoutWait(const Duration(seconds: 30)), '30 seconds');
      expect(formatLockoutWait(const Duration(milliseconds: 200)), '1 second');
      expect(formatLockoutWait(const Duration(seconds: 61)), '2 minutes');
      expect(formatLockoutWait(const Duration(minutes: 15)), '15 minutes');
      expect(
        formatLockoutWait(const Duration(minutes: 59, seconds: 58)),
        '1 hour',
      );
      expect(formatLockoutWait(const Duration(hours: 2)), '2 hours');
      expect(formatLockoutWait(const Duration(hours: 24)), '24 hours');
    });

    test('count down as m:ss or h:mm:ss', () {
      expect(formatLockoutCountdown(const Duration(seconds: 30)), '0:30');
      expect(formatLockoutCountdown(const Duration(minutes: 15)), '15:00');
      expect(
        formatLockoutCountdown(const Duration(hours: 1, seconds: 5)),
        '1:00:05',
      );
    });

    test('warn only from 3 attempts left', () {
      String? warn(int failed, int? limit) =>
          wipeWarningMessage(failedAttempts: failed, wipeAfterFailures: limit);
      expect(warn(7, null), isNull);
      expect(warn(6, 10), isNull);
      expect(warn(7, 10), '3 attempts left before Symudol erases all keys.');
      expect(warn(9, 10), '1 attempt left before Symudol erases all keys.');
      expect(warn(10, 10), isNull);
    });
  });
}
