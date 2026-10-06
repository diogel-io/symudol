import 'dart:typed_data';

import 'package:android_diogel/app/app.dart';
import 'package:android_diogel/app/utils/concurrency_utils.dart';
import 'package:android_diogel/features/nip55/application/nip55_providers.dart';
import 'package:android_diogel/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:android_diogel/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_store.dart';
import 'package:android_diogel/features/profile/application/profile_providers.dart';
import 'package:android_diogel/features/profile/data/relay_profile_service.dart';
import 'package:android_diogel/features/profile/domain/nostr_profile.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:android_diogel/features/vault/domain/vault_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_vault_store.dart';

/// Records what Dart asks of the native key bridge.
class RecordingNativeSync extends Nip55NativeMirrorSync {
  final deadlines = <Duration>[];
  int deadlinesCleared = 0;
  int keysCleared = 0;

  @override
  Future<void> setLockDeadline(Duration delay) async => deadlines.add(delay);

  @override
  Future<void> clearLockDeadline() async => deadlinesCleared++;

  @override
  Future<void> clearActiveKey() async => keysCleared++;

  @override
  Future<void> setActiveKey({
    required String privateKey,
    required String publicKey,
    required String localId,
  }) async {}

  @override
  Future<void> setActiveIdentityPubkey(String? pubkey) async {}

  @override
  Future<void> syncGrants(List<Nip55PermissionGrant> grants) async {}
}

class _Gateway implements Nip55Gateway {
  final rejectedErrors = <String?>[];

  @override
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  ) {}

  @override
  void setProviderQueryHandler(
    Future<Map<String, Object?>?> Function(Map<String, Object?> raw)? handler,
  ) {}

  @override
  Future<Map<String, Object?>?> getInitialNip55Intent() async => null;

  @override
  Future<Map<String, Object?>?> consumeLatestNip55Intent() async => null;

  @override
  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  }) async {}

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
  }) async => rejectedErrors.add(error);

  @override
  Future<Uint8List?> getAppIcon(String packageName) async => null;
}

/// Avoids real relay connections from the identity's avatar.
class _RelayProfileService extends RelayProfileService {
  @override
  Future<NostrProfile?> fetchProfile(String pubkeyHex) async => null;
}

class _PermissionStore implements Nip55PermissionStore {
  @override
  Future<List<Nip55PermissionGrant>> listGrants() async => const [];

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {}

  @override
  Future<void> deleteGrant(String id) async {}

  @override
  Future<void> deleteAllForPackage(String packageName) async {}

  @override
  Future<void> clearAll() async {}
}

void main() {
  late RecordingNativeSync nativeSync;
  late _Gateway gateway;

  setUp(() {
    nativeSync = RecordingNativeSync();
    gateway = _Gateway();
    // Unlocking and key generation stay inside the test's fake time.
    ConcurrencyUtils.useSynchronousTasks = true;
  });

  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  Future<ProviderContainer> pumpUnlockedApp(
    WidgetTester tester,
    FakeVaultStore store,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(store),
          nip55NativeSyncProvider.overrideWithValue(nativeSync),
          nip55GatewayProvider.overrideWithValue(gateway),
          nip55PermissionStoreProvider.overrideWithValue(_PermissionStore()),
          relayProfileServiceProvider.overrideWithValue(_RelayProfileService()),
        ],
        child: const DiogelApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Diogel'), findsOneWidget);

    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsWidgets);
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('background delay 0 locks immediately', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultLocked>());
  });

  testWidgets('background delay 5 does not lock before delay', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 4, seconds: 59));

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('background delay 5 expires session after delay', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5, seconds: 1));
    await tester.pumpAndSettle();

    final state = container.read(vaultStateProvider);
    expect(state, isA<SessionExpired>());
  });

  testWidgets('hidden schedules background lock', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultLocked>());
  });

  testWidgets('background delay -1 does not lock on background', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(-1);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 2));
    await tester.pumpAndSettle();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('resume before delay cancels background lock timer', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  testWidgets('inactive alone does not immediately lock', (tester) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    final state = container.read(vaultStateProvider);
    expect(state, isA<VaultUnlocked>());
  });

  // ── The native key and pending reviews (#9) ──────────────────────────────

  /// Opens a sign_message review, as a client app would.
  Future<void> openReview(WidgetTester tester, ProviderContainer container) async {
    await container
        .read(vaultControllerProvider.notifier)
        .createIdentity(displayName: 'Test');
    await tester.pump();
    final pubkey = container.read(vaultControllerProvider).activeIdentity!.publicKey;
    await container.read(nip55ControllerProvider.notifier).handleRawIntent({
      'requestToken': 'review-token',
      'type': 'sign_message',
      'content': 'hello',
      'currentUser': pubkey,
      'callingPackage': 'com.example.client',
    });
    await tester.pump();
    expect(container.read(nip55ControllerProvider).pendingCryptoRequest, isNotNull);
  }

  testWidgets('background gives the native key a deadline; resume removes it', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(5);
    await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(nativeSync.deadlines, [const Duration(minutes: 5)]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(nativeSync.deadlinesCleared, greaterThan(0));
  });

  testWidgets('never locking in the background sets no native deadline', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(-1);
    await pumpUnlockedApp(tester, store);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(nativeSync.deadlines, isEmpty);
  });

  testWidgets('detaching locks the vault and clears the native key', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(-1);
    final container = await pumpUnlockedApp(tester, store);
    final clearedBefore = nativeSync.keysCleared;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpAndSettle();

    expect(container.read(vaultStateProvider), isA<VaultLocked>());
    expect(nativeSync.keysCleared, greaterThan(clearedBefore));
  });

  testWidgets('a pending review defers the lock until it is settled', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);
    await openReview(tester, container);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(container.read(vaultStateProvider), isA<VaultUnlocked>());
    // The review's remaining time plus the (zero) lock delay.
    expect(nativeSync.deadlines.single.inSeconds, inInclusiveRange(290, 300));

    await container.read(nip55ControllerProvider.notifier).rejectCryptoRequest();
    await tester.pumpAndSettle();

    expect(container.read(vaultStateProvider), isA<VaultLocked>());
  });

  testWidgets('an abandoned review times out, then the vault locks', (
    tester,
  ) async {
    final store = FakeVaultStore();
    await store.setBackgroundLockDelayMinutes(0);
    final container = await pumpUnlockedApp(tester, store);
    await openReview(tester, container);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(container.read(vaultStateProvider), isA<VaultUnlocked>());

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      gateway.rejectedErrors,
      contains('NIP-55 request timed out waiting for review'),
    );
    expect(container.read(vaultStateProvider), isA<VaultLocked>());
  });
}
