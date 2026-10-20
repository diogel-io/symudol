import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/settings/presentation/change_pin_screen.dart';
import 'package:symudol/features/settings/presentation/settings_screen.dart';
import 'package:symudol/features/unlock/presentation/pin_lockout_countdown.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';
import 'package:symudol/features/vault/domain/vault_state.dart';

import '../../../fakes/fake_vault_store.dart';

/// Settings → Change PIN (#21).
void main() {
  late FakeVaultStore store;
  late ProviderContainer container;

  setUp(() async {
    PinLockoutCountdown.stopwatchFactory = () => clock.stopwatch();
    store = FakeVaultStore();
    container = ProviderContainer(
      overrides: [vaultStoreProvider.overrideWithValue(store)],
    );
    await container.read(vaultControllerProvider.notifier).initialize();
    await container.read(vaultControllerProvider.notifier).createVault('123456');
  });

  tearDown(() {
    PinLockoutCountdown.stopwatchFactory = Stopwatch.new;
    container.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('changePinTile')));
    await tester.pumpAndSettle();
  }

  String title(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('changePinTitle'))).data!;

  /// Enters [pin]; the Argon2id work then runs for real, outside fake time.
  Future<void> enter(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('Changing PIN…').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the tile opens the screen at the current-PIN step', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.byType(ChangePinScreen), findsOneWidget);
    expect(title(tester), 'Enter your current PIN');
  });

  testWidgets('a full change pops with "PIN changed"', (tester) async {
    await pumpSettings(tester);

    await enter(tester, '123456');
    expect(title(tester), 'Enter a new PIN');
    await enter(tester, '654321');
    expect(title(tester), 'Confirm the new PIN');
    await enter(tester, '654321');

    expect(find.byType(ChangePinScreen), findsNothing);
    expect(find.text('PIN changed'), findsOneWidget);
    final service = container.read(vaultServiceProvider);
    await service.lock();
    await service.unlock('654321');
    expect(service.state, isA<VaultUnlocked>());
  });

  testWidgets('a mismatched confirmation starts the new PIN again', (
    tester,
  ) async {
    await pumpSettings(tester);

    await enter(tester, '123456');
    await enter(tester, '654321');
    await enter(tester, '111111');

    expect(title(tester), 'Enter a new PIN');
    expect(
      find.text('The PINs do not match. Enter the new PIN again.'),
      findsOneWidget,
    );
  });

  testWidgets('the current PIN cannot be the new one', (tester) async {
    await pumpSettings(tester);

    await enter(tester, '123456');
    await enter(tester, '123456');

    expect(title(tester), 'Enter a new PIN');
    expect(find.text('Choose a different PIN.'), findsOneWidget);
  });

  testWidgets('a wrong current PIN starts again and is counted', (
    tester,
  ) async {
    await pumpSettings(tester);

    await enter(tester, '000000');
    await enter(tester, '654321');
    await enter(tester, '654321');

    expect(find.byType(ChangePinScreen), findsOneWidget);
    expect(title(tester), 'Enter your current PIN');
    expect(find.text('That is not your current PIN.'), findsOneWidget);
    expect(await store.getFailedUnlockAttempts(), 1);
  });

  testWidgets('a lockout disables the pad and counts down', (tester) async {
    await store.setFailedUnlockAttempts(4);
    await pumpSettings(tester);

    await enter(tester, '000000');
    await enter(tester, '654321');
    await enter(tester, '654321');

    // Real Argon2id runs between the lockout starting and being read, so a
    // second or two of it may already be gone.
    expect(
      find.textContaining('Too many failed attempts. Try again in'),
      findsOneWidget,
    );
    await tester.tap(find.text('1').last);
    await tester.pump();
    expect(find.byKey(const ValueKey('changePinDots-0')), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    expect(find.byKey(const Key('changePinLockoutMessage')), findsNothing);
  });

  testWidgets('closes when the vault locks', (tester) async {
    await pumpSettings(tester);

    await container.read(vaultControllerProvider.notifier).lock();
    await tester.pumpAndSettle();

    expect(find.byType(ChangePinScreen), findsNothing);
  });

  test('the service is the real one, so the PIN check is real', () {
    expect(container.read(vaultServiceProvider), isA<VaultServiceImpl>());
  });
}
