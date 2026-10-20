import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/app.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/biometric_vault.dart';
import 'package:symudol/features/vault/domain/monotonic_clock.dart';
import 'package:symudol/features/vault/domain/vault_exceptions.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_biometric_vault.dart';
import '../../../fakes/fake_nip46_session_store.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
import '../../../fakes/fake_vault_store.dart';
import '../../nip55/application/nip55_controller_test.dart'
    show FakeNip55Gateway;

/// Native mirror calls do nothing: in widget tests the real ones wait on a
/// platform channel that never answers in fake time.
class _QuietNativeSync extends Nip55NativeMirrorSync {
  @override
  Future<void> wipeNativeState() async {}

  @override
  Future<void> syncGrants(List<Nip55PermissionGrant> grants) async {}

  @override
  Future<void> setActiveIdentityPubkey(String? pubkey) async {}

  @override
  Future<void> setActiveKey({
    required String privateKey,
    required String publicKey,
    required String localId,
  }) async {}

  @override
  Future<void> clearActiveKey() async {}

  @override
  Future<void> setLockDeadline(Duration delay) async {}

  @override
  Future<void> clearLockDeadline() async {}
}

/// Biometric unlock on the unlock screen and in Settings (#23).
void main() {
  late FakeVaultStore store;
  late FakeBiometricVault biometric;

  VaultServiceImpl service() =>
      VaultServiceImpl(store, biometricVault: biometric);

  setUp(() async {
    store = FakeVaultStore();
    biometric = FakeBiometricVault();
    final setup = service();
    await setup.createVault('123456');
    await setup.createIdentity(displayName: 'Alice');
  });

  Future<void> turnOn() async {
    final setup = service();
    await setup.unlock('123456');
    await setup.enableBiometricUnlock('123456');
    await setup.lock();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(store),
          vaultServiceProvider.overrideWithValue(service()),
          nip55GatewayProvider.overrideWithValue(FakeNip55Gateway()),
          nip55PermissionStoreProvider.overrideWithValue(
            FakeNip55PermissionStore(),
          ),
          nip46SessionStoreProvider.overrideWithValue(FakeNip46SessionStore()),
          nip55NativeSyncProvider.overrideWithValue(_QuietNativeSync()),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Finder fingerprintButton() =>
      find.byKey(const Key('biometricUnlockButton'));

  group('unlock screen', () {
    testWidgets('prompts by itself and unlocks', (tester) async {
      await turnOn();
      final promptsBefore = biometric.prompts;

      await pumpApp(tester);

      expect(biometric.prompts, promptsBefore + 1);
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('a cancelled prompt leaves the PIN pad and the button', (
      tester,
    ) async {
      await turnOn();
      biometric.nextPromptError = const BiometricCancelledException();

      await pumpApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
      expect(find.text('Biometric unlock cancelled'), findsNothing);
      await tester.tap(fingerprintButton());
      await tester.pumpAndSettle();
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('after a restart it asks for the PIN, without a prompt', (
      tester,
    ) async {
      await turnOn();
      // The PIN was last checked on another boot.
      await store.setPinVerifiedAt(
        const MonotonicInstant(elapsedMs: 1, bootCount: -1),
      );
      final promptsBefore = biometric.prompts;

      await pumpApp(tester);

      expect(biometric.prompts, promptsBefore);
      expect(
        find.byKey(const Key('unlockBiometricPinRequired')),
        findsOneWidget,
      );
      expect(
        tester.widget<InkWell>(
          find.descendant(of: fingerprintButton(), matching: find.byType(InkWell)),
        ).onTap,
        isNull,
      );
      await enterPin(tester, '123456');
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('an invalidated key turns it off and says so', (tester) async {
      await turnOn();
      biometric.invalidated = true;

      await pumpApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
      expect(
        find.textContaining('fingerprints or face changed'),
        findsOneWidget,
      );
      expect(await store.getBiometricWrap(), isNull);
      await enterPin(tester, '123456');
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('with no fingerprint left it says it was turned off', (
      tester,
    ) async {
      await turnOn();
      biometric.availabilityValue = BiometricAvailability.noneEnrolled;
      final promptsBefore = biometric.prompts;

      await pumpApp(tester);

      expect(biometric.prompts, promptsBefore);
      expect(find.textContaining('was turned off'), findsOneWidget);
      expect(await store.getBiometricWrap(), isNull);
      await enterPin(tester, '123456');
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets("says when the phone can't use it right now", (tester) async {
      await turnOn();
      biometric.availabilityValue = BiometricAvailability.unavailable;

      await pumpApp(tester);

      expect(
        find.byKey(const Key('unlockBiometricUnavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unlockBiometricPinRequired')),
        findsNothing,
      );
      expect(await store.getBiometricWrap(), isNotNull);
    });

    testWidgets("Android's biometric lockout sends the user to the PIN (#108)", (
      tester,
    ) async {
      await turnOn();
      biometric.nextPromptError = const BiometricLockedOutException();

      await pumpApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
      expect(
        find.text('Too many biometric attempts. Unlock with your PIN.'),
        findsOneWidget,
      );
      expect(await store.getBiometricWrap(), isNotNull);
      await enterPin(tester, '123456');
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('a failed biometric check says to use the PIN (#108)', (
      tester,
    ) async {
      await turnOn();
      biometric.nextPromptError = const BiometricFailedException('vendor');

      await pumpApp(tester);

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
      expect(
        find.text('The biometric check did not work. Unlock with your PIN.'),
        findsOneWidget,
      );
      expect(await store.getBiometricWrap(), isNotNull);
    });

    testWidgets('on resume it re-reads the sensor and prompts (#108)', (
      tester,
    ) async {
      await turnOn();
      biometric.availabilityValue = BiometricAvailability.unavailable;
      await pumpApp(tester);
      final promptsBefore = biometric.prompts;
      expect(
        find.byKey(const Key('unlockBiometricUnavailable')),
        findsOneWidget,
      );

      biometric.availabilityValue = BiometricAvailability.available;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(biometric.prompts, promptsBefore + 1);
      expect(find.byType(UnlockVaultScreen), findsNothing);
    });

    testWidgets('off: no prompt, and the fingerprint key does nothing', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(biometric.prompts, 0);
      expect(find.byKey(const Key('unlockBiometricPinRequired')), findsNothing);
      expect(
        tester.widget<InkWell>(
          find.descendant(of: fingerprintButton(), matching: find.byType(InkWell)),
        ).onTap,
        isNull,
      );
    });
  });

  group('Settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await pumpApp(tester);
      await enterPin(tester, '123456');
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
    }

    Switch biometricSwitch(WidgetTester tester) =>
        tester.widget<Switch>(find.byKey(const Key('biometricUnlockSwitch')));

    testWidgets('turning it on asks for the PIN, then the prompt', (
      tester,
    ) async {
      await openSettings(tester);
      expect(biometricSwitch(tester).value, isFalse);

      await tester.tap(find.byKey(const Key('biometricUnlockSwitch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('biometricPinField')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(biometric.prompts, 1);
      expect(biometricSwitch(tester).value, isTrue);
      expect(find.text('Biometric unlock is on'), findsOneWidget);
    });

    testWidgets('a wrong PIN turns nothing on', (tester) async {
      await openSettings(tester);

      await tester.tap(find.byKey(const Key('biometricUnlockSwitch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('biometricPinField')),
        '000000',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(biometric.prompts, 0);
      expect(biometricSwitch(tester).value, isFalse);
      expect(find.text('Invalid PIN. Please try again.'), findsOneWidget);
    });

    testWidgets('turning it off needs no prompt', (tester) async {
      await turnOn();
      // Unlock with the PIN pad: the automatic prompt is cancelled.
      biometric.nextPromptError = const BiometricCancelledException();
      await openSettings(tester);
      expect(biometricSwitch(tester).value, isTrue);
      final promptsBefore = biometric.prompts;

      await tester.tap(find.byKey(const Key('biometricUnlockSwitch')));
      await tester.pumpAndSettle();

      expect(biometric.prompts, promptsBefore);
      expect(biometricSwitch(tester).value, isFalse);
      expect(biometric.hasKey, isFalse);
    });

    testWidgets("on but unavailable: says so, and can be turned off", (
      tester,
    ) async {
      await turnOn();
      biometric.availabilityValue = BiometricAvailability.unavailable;
      await openSettings(tester);

      expect(biometricSwitch(tester).value, isTrue);
      expect(biometricSwitch(tester).onChanged, isNotNull);
      expect(
        find.text("On, but this phone can't use it right now; the PIN still works"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('biometricUnlockSwitch')));
      await tester.pumpAndSettle();
      expect(biometricSwitch(tester).value, isFalse);
    });

    testWidgets('on resume it shows a fingerprint added meanwhile (#108)', (
      tester,
    ) async {
      biometric.availabilityValue = BiometricAvailability.noneEnrolled;
      await openSettings(tester);
      expect(biometricSwitch(tester).onChanged, isNull);

      // Added in Android settings while Symudol was in the background.
      biometric.availabilityValue = BiometricAvailability.available;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(biometricSwitch(tester).onChanged, isNotNull);
      expect(
        find.textContaining('Unlock with your fingerprint or face'),
        findsOneWidget,
      );
    });

    testWidgets('with no fingerprint enrolled the switch is disabled', (
      tester,
    ) async {
      biometric.availabilityValue = BiometricAvailability.noneEnrolled;
      await openSettings(tester);

      expect(biometricSwitch(tester).onChanged, isNull);
      expect(
        find.text('Add a fingerprint or face in Android settings first'),
        findsOneWidget,
      );
    });
  });
}
