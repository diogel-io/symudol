import 'dart:convert';
import 'dart:typed_data';

import 'package:symudol/app/app.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/nip46/application/nip46_feature.dart';
import 'package:symudol/features/nip46/application/nip46_providers.dart';
import 'package:symudol/features/nip46/data/method_channel_nip46_background.dart';
import 'package:symudol/features/nip46/domain/nip46_relay_event.dart';
import 'package:symudol/features/nip46/domain/nip46_session.dart';
import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:symudol/features/nip55/data/nip55_native_mirror_sync.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/profile/data/relay_profile_service.dart';
import 'package:symudol/features/signing/data/dart_nostr_crypto_service.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_nip46_session_store.dart';
import '../fakes/fake_nip55_permission_store.dart';
import '../fakes/fake_profile_network_store.dart';
import '../fakes/fake_vault_store.dart';
import '../features/nip46/data/fake_nip46_relay_service.dart';

/// A throwaway client key, for these tests only.
final _clientPrivkey = '${'0' * 63}7';

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

/// Records the foreground service being started and stopped (#29).
class _FakeBackground extends MethodChannelNip46Background {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

/// A connected client, stored before this run (#29).
final _storedSession = Nip46Session(
  id: 'stored-1',
  clientPubkey: 'c' * 64,
  remoteSignerPubkey: 'd' * 64,
  remoteSignerPrivkey: '${'0' * 63}5',
  relays: const ['wss://relay.example.com'],
  status: Nip46SessionStatus.active,
  createdAt: DateTime(2026, 11, 2),
);

/// Avoids real relay connections from the identity's avatar.
class _RelayProfileService extends RelayProfileService {
  @override
  Future<ProfileLookup> fetchProfile(String pubkeyHex) async =>
      const ProfileLookup();
}

void main() {
  setUp(() => ConcurrencyUtils.useSynchronousTasks = true);
  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  Future<ProviderContainer> pumpUnlockedApp(
    WidgetTester tester, {
    List<Nip46Session> sessions = const [],
    bool nip46Enabled = true,
    MethodChannelNip46Background? background,
  }) async {
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
          nip46RelayServiceProvider.overrideWithValue(FakeNip46RelayService()),
          // Reads no session without the vault's key, like the real store
          // (#32), so starting on unlock must count rather than read.
          nip46SessionStoreProvider.overrideWithValue(
            FakeNip46SessionStore(List.of(sessions))..requireKey = true,
          ),
          nip46EnabledProvider.overrideWithValue(nip46Enabled),
          if (background != null)
            nip46BackgroundProvider.overrideWithValue(background),
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

  Future<void> openRemoteSigner(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Remote Signer (NIP-46)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Remote Signer (NIP-46)'));
    await tester.pumpAndSettle();
  }

  /// A client's nostrconnect:// request, which waits for the user's approval.
  /// The client key is a real curve point, so responses to it can be
  /// encrypted.
  Future<void> sendConnectRequest(ProviderContainer container) {
    final clientPubkey = const DartNostrCryptoService().derivePublicKey(
      _clientPrivkey,
    );
    return container
        .read(nip46ControllerProvider.notifier)
        .importNostrconnectToken(
          'nostrconnect://$clientPubkey'
          '?secret=testsecret123&relay=wss%3A%2F%2Frelay.example.com',
        );
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

  // The lock closes the NIP-46 connection approval, but the request stays
  // pending with its timer running (diogel-io/symudol#125).
  group('a NIP-46 connection request across a lock (#125)', () {
    testWidgets('can be reviewed and approved after the unlock', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openRemoteSigner(tester);
      await sendConnectRequest(container);
      await tester.pumpAndSettle();
      expect(find.text('Remote Signer Request').hitTestable(), findsOneWidget);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Remote Signer Request'), findsNothing);
      expect(container.read(nip46ControllerProvider).pendingApproval, isNotNull);

      await enterPin(tester);
      await openRemoteSigner(tester);
      await tester.tap(find.byKey(const Key('nip46ReviewRequest')));
      await tester.pumpAndSettle();
      expect(find.text('Remote Signer Request').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      final state = container.read(nip46ControllerProvider);
      expect(state.pendingApproval, isNull);
      expect(state.sessions.single.status, Nip46SessionStatus.active);
      expect(find.text('Remote Signer Request'), findsNothing);
      expect(find.byKey(const Key('nip46ReviewRequest')), findsNothing);
    });

    testWidgets('that times out while locked leaves nothing after unlock', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openRemoteSigner(tester);
      await sendConnectRequest(container);
      await tester.pumpAndSettle();
      final relay =
          container.read(nip46RelayServiceProvider) as FakeNip46RelayService;
      final clientPubkey =
          container.read(nip46ControllerProvider).pendingApproval!.clientPubkey;
      expect(relay.capturedPublishes, isEmpty);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 121));
      await tester.pumpAndSettle();

      final state = container.read(nip46ControllerProvider);
      expect(state.pendingApproval, isNull);
      expect(state.sessions, isEmpty);
      // The client is told: one NIP-46 error response (kind 24133) addressed
      // to it, not a successful connect.
      final published = relay.capturedPublishes.single;
      expect(published['kind'], 24133);
      expect(published['tags'], [
        ['p', clientPubkey],
      ]);
      final response = jsonDecode(
        const DartNostrCryptoService().nip44Decrypt(
          privateKeyHex: _clientPrivkey,
          peerPubkeyHex: published['pubkey'] as String,
          ciphertext: published['content'] as String,
        ),
      ) as Map<String, Object?>;
      expect(response['error'], isNotNull);
      expect(response['result'], isNull);

      await enterPin(tester);
      await openRemoteSigner(tester);

      expect(find.text('Remote Signer Request'), findsNothing);
      expect(find.byKey(const Key('nip46ReviewRequest')), findsNothing);
      expect(find.text('No remote signer connections'), findsOneWidget);
    });

    testWidgets('that times out in the background keeps the unlock screen', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openRemoteSigner(tester);
      await sendConnectRequest(container);
      await tester.pumpAndSettle();

      // In the background no frames run, so the lock's pops never finish and
      // the approval is still mounted when the timer rejects the request.
      await container.read(vaultControllerProvider.notifier).lock();
      await tester.binding.delayed(const Duration(seconds: 121));
      expect(container.read(nip46ControllerProvider).pendingApproval, isNull);
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Remote Signer Request'), findsNothing);

      await enterPin(tester);

      expect(find.text('Accounts'), findsWidgets);
    });

    testWidgets('that times out under a NIP-55 approval keeps that approval', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await openRemoteSigner(tester);
      await sendConnectRequest(container);
      await tester.pumpAndSettle();
      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();
      expect(find.text('Share public key').hitTestable(), findsOneWidget);

      await tester.pump(const Duration(seconds: 121));
      await tester.pumpAndSettle();

      expect(container.read(nip46ControllerProvider).pendingApproval, isNull);
      expect(find.text('Remote Signer Request'), findsNothing);
      expect(find.text('Share public key').hitTestable(), findsOneWidget);
    });
  });

  // A connected client's requests that need review come to the shared
  // Approval screen (diogel-io/symudol#27).
  group('a NIP-46 request that needs review (#27)', () {
    var eventCounter = 0;

    /// Opens Remote Signer and approves a client's connection.
    Future<void> connectClient(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await openRemoteSigner(tester);
      await sendConnectRequest(container);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(
        container.read(nip46ControllerProvider).sessions.single.status,
        Nip46SessionStatus.active,
      );
    }

    /// The connected client asks Symudol to sign a note, as a relay would
    /// deliver it.
    Future<void> sendSignEvent(
      WidgetTester tester,
      ProviderContainer container,
      String id,
    ) async {
      final session = container.read(nip46ControllerProvider).sessions.single;
      const crypto = DartNostrCryptoService();
      final relay =
          container.read(nip46RelayServiceProvider) as FakeNip46RelayService;
      relay.simulateInbound(
        Nip46InboundRelayEvent(
          eventId: 'event-${++eventCounter}',
          senderPubkey: crypto.derivePublicKey(_clientPrivkey),
          recipientPubkey: session.remoteSignerPubkey,
          encryptedContent: crypto.nip44Encrypt(
            privateKeyHex: _clientPrivkey,
            peerPubkeyHex: session.remoteSignerPubkey,
            plaintext: jsonEncode({
              'id': id,
              'method': 'sign_event',
              'params': [
                jsonEncode({
                  'kind': 1,
                  'content': 'a remote note',
                  'tags': <Object>[],
                  'created_at': 1700000000,
                }),
              ],
            }),
          ),
          relay: 'wss://relay.example.com',
          createdAt: 0,
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The client's view of what Symudol published to it, oldest first.
    List<Map<String, Object?>> responses(ProviderContainer container) {
      final relay =
          container.read(nip46RelayServiceProvider) as FakeNip46RelayService;
      return [
        for (final event in relay.capturedPublishes)
          if (event['kind'] == 24133)
            (jsonDecode(
                      const DartNostrCryptoService().nip44Decrypt(
                        privateKeyHex: _clientPrivkey,
                        peerPubkeyHex: event['pubkey'] as String,
                        ciphertext: event['content'] as String,
                      ),
                    )
                    as Map)
                .cast<String, Object?>(),
      ];
    }

    testWidgets('comes forward over Remote Signer and approve signs it', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await connectClient(tester, container);
      final before = responses(container).length;

      await sendSignEvent(tester, container, 'sign-1');

      expect(find.text('Approval Request').hitTestable(), findsOneWidget);
      expect(find.textContaining('a remote note'), findsWidgets);

      await tester.tap(find.text('Sign event'));
      await tester.pumpAndSettle();

      final answer = responses(container).skip(before).single;
      expect(answer['id'], 'sign-1');
      expect(answer['error'], isNull);
      final signed = (jsonDecode(answer['result'] as String) as Map)
          .cast<String, Object?>();
      expect(signed['content'], 'a remote note');
      expect(signed['sig'], isA<String>());
      // Back where the user was.
      expect(find.text('Approval Request'), findsNothing);
      expect(find.text('Remote Signer (NIP-46)').hitTestable(), findsOneWidget);
    });

    testWidgets('queued across a lock is shown again after the unlock', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await connectClient(tester, container);
      await sendSignEvent(tester, container, 'sign-1');
      expect(find.text('Approval Request').hitTestable(), findsOneWidget);

      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(
        container.read(nip46ControllerProvider).pendingMethodRequests,
        hasLength(1),
      );

      await enterPin(tester);

      expect(find.text('Approval Request').hitTestable(), findsOneWidget);
      expect(find.textContaining('a remote note'), findsWidgets);
    });

    testWidgets('one held while locked is shown after the unlock (#29)', (
      tester,
    ) async {
      final container = await pumpUnlockedApp(tester);
      await connectClient(tester, container);
      await container.read(vaultControllerProvider.notifier).lock();
      await tester.pumpAndSettle();
      final before = responses(container).length;

      await sendSignEvent(tester, container, 'held-1');

      // Not answered, and no approval over the unlock screen.
      expect(responses(container), hasLength(before));
      expect(find.text('Unlock Vault').hitTestable(), findsWidgets);
      expect(find.text('Approval Request'), findsNothing);

      await enterPin(tester);

      expect(find.text('Approval Request').hitTestable(), findsOneWidget);
      expect(find.textContaining('a remote note'), findsWidgets);
    });

    testWidgets('the home shell does not start NIP-46', (tester) async {
      final container = await pumpUnlockedApp(tester);
      await sendPublicKeyRequest(container);
      await tester.pumpAndSettle();

      // Watching the review queue must not create the controller, which
      // opens relays (#26).
      expect(find.text('Share public key').hitTestable(), findsOneWidget);
      expect(container.exists(nip46ControllerProvider), isFalse);
      expect(container.exists(nip46RelayServiceProvider), isFalse);
    });
  });

  // NIP-46 starts on unlock, and the foreground service keeps it running in
  // the background when the user wants it (diogel-io/symudol#29).
  group('NIP-46 in the background (#29)', () {
    Future<void> goToBackground(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
    }

    Future<void> comeBack(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('unlocking with a stored session starts it', (tester) async {
      final container = await pumpUnlockedApp(
        tester,
        sessions: [_storedSession],
      );

      expect(container.exists(nip46ControllerProvider), isTrue);
      final relay =
          container.read(nip46RelayServiceProvider) as FakeNip46RelayService;
      expect(relay.connectedSessions, {_storedSession.id});
    });

    testWidgets('a build that hides NIP-46 does not start it', (tester) async {
      final container = await pumpUnlockedApp(
        tester,
        sessions: [_storedSession],
        nip46Enabled: false,
      );

      expect(container.exists(nip46ControllerProvider), isFalse);
      expect(container.exists(nip46RelayServiceProvider), isFalse);
    });

    testWidgets('revoking the last session stops the service', (tester) async {
      final background = _FakeBackground();
      final container = await pumpUnlockedApp(
        tester,
        sessions: [_storedSession],
        background: background,
      );
      final controller = container.read(nip46ControllerProvider.notifier);
      await controller.setRunInBackground(true);
      expect(background.stops, 0);

      // As when a client logs out while Symudol is in the background.
      await controller.revokeSession(_storedSession.id);
      await tester.pump();

      expect(background.stops, 1);
    });

    testWidgets('the service runs in the background only when turned on', (
      tester,
    ) async {
      final background = _FakeBackground();
      final container = await pumpUnlockedApp(
        tester,
        sessions: [_storedSession],
        background: background,
      );

      await goToBackground(tester);
      await comeBack(tester);
      expect(background.starts, 0);

      await container
          .read(nip46ControllerProvider.notifier)
          .setRunInBackground(true);
      await goToBackground(tester);
      expect(background.starts, 1);

      await comeBack(tester);
      expect(background.stops, greaterThanOrEqualTo(1));
      expect(find.text('Unlock Vault'), findsNothing);
    });
  });
}
