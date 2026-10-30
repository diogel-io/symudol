import 'dart:typed_data';

import 'package:symudol/app/app.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/requests/application/request_providers.dart';
import 'package:symudol/features/requests/domain/request_provenance.dart';
import 'package:symudol/features/requests/domain/request_trust_status.dart';
import 'package:symudol/features/requests/domain/signing_action_type.dart';
import 'package:symudol/features/requests/domain/signing_request.dart';
import 'package:symudol/features/requests/domain/signing_request_status.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_nip55_permission_store.dart';
import '../../../fakes/fake_vault_store.dart';

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

/// A screen with unsaved text that asks before it is left, like Edit profile.
class _DirtyScreen extends StatelessWidget {
  const _DirtyScreen();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Dirty screen')),
        body: const TextField(key: Key('dirty-field')),
      ),
    );
  }
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

  Future<void> sendSigningRequest(ProviderContainer container) {
    final identity = container.read(vaultControllerProvider).activeIdentity!;
    return container
        .read(requestControllerProvider.notifier)
        .acceptRequest(
          SigningRequest(
            id: 'req1',
            provenance: const RequestProvenance(
              sourceDisplayName: 'Example App',
              trustStatus: RequestTrustStatus.knownTrusted,
            ),
            actionType: SigningActionType.signEvent,
            eventKind: 1,
            eventPayload: {'content': 'Hello Nostr'},
            targetIdentityPublicKey: identity.publicKey,
            targetIdentityLocalId: identity.localId,
            createdAt: DateTime.now(),
            status: SigningRequestStatus.pending,
          ),
        );
  }

  NavigatorState rootNavigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  group('An incoming request (#121)', () {
    testWidgets('shows above Trusted Nostr apps, which is kept', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);

      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();

      expect(find.text('Approval Request'), findsOneWidget);
      expect(find.text('Share public key').hitTestable(), findsOneWidget);
      // Back is blocked, so no close button that would do nothing.
      expect(find.byType(CloseButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(find.text('Approval Request'), findsNothing);
      expect(find.text('Trusted Nostr apps').hitTestable(), findsOneWidget);
    });

    testWidgets('keeps a screen with unsaved edits', (tester) async {
      final container = await pumpUnlockedApp(tester);
      rootNavigator(
        tester,
      ).push(MaterialPageRoute<void>(builder: (_) => const _DirtyScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('dirty-field')), 'draft');

      await sendSigningRequest(container);
      await tester.pumpAndSettle();

      expect(find.text('Approval Request').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(find.text('Dirty screen').hitTestable(), findsOneWidget);
      expect(find.text('draft'), findsOneWidget);
    });

    testWidgets('shows above an open dialog', (tester) async {
      final container = await pumpUnlockedApp(tester);
      showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (_) => const AlertDialog(title: Text('Open dialog')),
      );
      await tester.pumpAndSettle();

      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();

      expect(find.text('Share public key').hitTestable(), findsOneWidget);
    });

    testWidgets('on the home shell only switches tab', (tester) async {
      final container = await pumpUnlockedApp(tester);

      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();

      expect(find.text('Share public key').hitTestable(), findsOneWidget);
      expect(rootNavigator(tester).canPop(), isFalse);
    });

    testWidgets('cannot be hidden with Back while pending', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await openTrustedApps(tester);

      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Share public key').hitTestable(), findsOneWidget);
    });
  });
}
