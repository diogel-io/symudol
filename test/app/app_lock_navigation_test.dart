import 'dart:typed_data';

import 'package:symudol/app/app.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_nip55_permission_store.dart';
import '../fakes/fake_profile_network_store.dart';
import '../fakes/fake_vault_store.dart';

class _NativeSync extends Nip55NativeMirrorSync {
  @override
  Future<void> setLockDeadline(Duration delay) async {}

  @override
  Future<void> clearLockDeadline() async {}

  @override
  Future<void> clearActiveKey() async {}

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
    bool rejected = false,
  }) async {}

  @override
  Future<Uint8List?> getAppIcon(String packageName) async => null;
}

/// Avoids real relay connections from the identity's avatar.
class _RelayProfileService extends RelayProfileService {
  @override
  Future<ProfileLookup> fetchProfile(String pubkeyHex) async =>
      const ProfileLookup();
}

void main() {
  setUp(() => ConcurrencyUtils.useSynchronousTasks = true);
  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  Future<ProviderContainer> pumpUnlockedApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWithValue(FakeVaultStore()),
          nip55NativeSyncProvider.overrideWithValue(_NativeSync()),
          nip55GatewayProvider.overrideWithValue(_Gateway()),
          nip55PermissionStoreProvider.overrideWithValue(
            FakeNip55PermissionStore(),
          ),
          relayProfileServiceProvider.overrideWithValue(_RelayProfileService()),
          profileNetworkStoreProvider.overrideWithValue(
            FakeProfileNetworkStore(),
          ),
        ],
        child: const DiogelApp(),
      ),
    );
    await tester.pumpAndSettle();

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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container
        .read(vaultControllerProvider.notifier)
        .createIdentity(displayName: 'Test');
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openTrustedApps(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Trusted Nostr apps'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Trusted Nostr apps'));
    await tester.pumpAndSettle();
  }

  Future<void> sendPublicKeyRequest(ProviderContainer container) {
    return container.read(nip55ControllerProvider.notifier).handleRawIntent({
      'requestToken': 'pk-token',
      'type': 'get_public_key',
      'callingPackage': 'com.example.client',
    });
  }

  Future<void> enterPin(WidgetTester tester) async {
    for (var i = 1; i <= 6; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('Locking the vault (#123)', () {
    testWidgets('removes a pushed Settings screen', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Trusted Nostr apps'), findsNothing);
    });

    testWidgets('removes an open dialog', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In-app inactivity timeout'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
    });

    testWidgets('removes Edit profile while it asks to load', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      expect(find.text('Load profile from relays?'), findsOneWidget);

      // Closing the prompt must not also pop the unlock screen.
      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Load profile from relays?'), findsNothing);

      await enterPin(tester);

      expect(find.text('Accounts'), findsWidgets);
    });

    testWidgets('an expired session removes a pushed screen', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);

      await container.read(vaultControllerProvider.notifier).expireSession();
      await tester.pumpAndSettle();

      expect(find.text('Session Expired').hitTestable(), findsWidgets);
      expect(find.text('Trusted Nostr apps'), findsNothing);
    });

    testWidgets('unlocking again shows the home shell', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);
      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      await enterPin(tester);

      expect(find.text('Trusted Nostr apps'), findsNothing);
      expect(find.text('Accounts'), findsWidgets);
    });

    testWidgets('keeps a request under review for after the unlock', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);
      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();
      expect(find.text('Share public key').hitTestable(), findsOneWidget);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Share public key'), findsNothing);
      expect(
        container.read(nip55ControllerProvider).pendingPublicKeyRequest,
        isNotNull,
      );

      await enterPin(tester);

      expect(find.text('Share public key').hitTestable(), findsOneWidget);
      expect(find.text('Trusted Nostr apps'), findsNothing);
    });
  });
}
