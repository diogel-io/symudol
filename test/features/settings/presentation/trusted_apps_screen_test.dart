import 'package:symudol/features/nip55/application/nip55_providers.dart';
import 'package:symudol/features/nip55/domain/nip55_client_permission.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
import 'package:symudol/features/nip55/domain/nip55_permission_scope.dart';
import 'package:symudol/features/settings/presentation/trusted_apps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../fakes/fake_nip55_permission_store.dart';

void main() {
  testWidgets('TrustedAppsScreen lists app, scopes, status, and last used', (
    tester,
  ) async {
    final store = FakeNip55PermissionStore()
      ..grants.addAll([
        Nip55PermissionGrant(
          id: 'grant-1',
          identityPubkey: 'abcdef1234567890',
          packageName: 'com.example.nostr',
          certificateSha256: 'AA:BB',
          scope: const SignEventScope(1),
          decision: Nip55PermissionDecision.allow,
          createdAt: DateTime(2026, 5, 1, 10, 0),
          lastUsedAt: DateTime(2026, 5, 3, 9, 30),
          userLabel: 'Example Nostr',
        ),
        Nip55PermissionGrant(
          id: 'grant-2',
          identityPubkey: 'abcdef1234567890',
          packageName: 'com.example.nostr',
          scope: const Nip04DecryptScope(),
          decision: Nip55PermissionDecision.reject,
          createdAt: DateTime(2026, 5, 2, 11, 0),
        ),
      ]);

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('Example Nostr'), findsOneWidget);
    expect(find.textContaining('never remembered'), findsOneWidget);
    expect(
      find.textContaining('Browser flows are not remembered'),
      findsOneWidget,
    );
    expect(find.text('com.example.nostr'), findsOneWidget);
    expect(find.textContaining('Identity abcdef…567890'), findsOneWidget);
    expect(find.textContaining('Allowed • Sign kind 1'), findsOneWidget);
    expect(find.textContaining('Rejected • NIP-04 decrypt'), findsOneWidget);
    expect(find.textContaining('No expiry'), findsNWidgets(2));
    expect(find.textContaining('Last used 2026-05-03 09:30'), findsWidgets);
  });

  testWidgets('TrustedAppsScreen revokes one permission', (tester) async {
    final store = FakeNip55PermissionStore()
      ..grants.addAll([
        _grant('grant-1', const GetPublicKeyScope()),
        _grant('grant-2', const SignEventScope(1)),
      ]);

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Revoke permission').first);
    await tester.pumpAndSettle();

    expect(store.grants, hasLength(1));
  });

  testWidgets('TrustedAppsScreen revokes all permissions for an app', (
    tester,
  ) async {
    final store = FakeNip55PermissionStore()
      ..grants.addAll([
        _grant('grant-1', const GetPublicKeyScope()),
        _grant('grant-2', const SignEventScope(1)),
      ]);

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke app'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(store.grants, isEmpty);
    expect(
      find.text(
        'No remembered NIP-55 app permissions yet. Approvals you remember from verified native app requests will appear here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('TrustedAppsScreen revokes all remembered permissions globally', (
    tester,
  ) async {
    final store = FakeNip55PermissionStore()
      ..grants.addAll([
        _grant('grant-1', const GetPublicKeyScope()),
        Nip55PermissionGrant(
          id: 'grant-2',
          identityPubkey: 'pubkey',
          packageName: 'com.other.app',
          scope: const SignEventScope(1),
          decision: Nip55PermissionDecision.allow,
          createdAt: DateTime(2026),
        ),
      ]);

    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke all'));
    await tester.pumpAndSettle();

    expect(store.grants, isEmpty);
  });
  group('a grant stored after the first open shows (#99)', () {
    // Settings with a Trusted apps tile, so the screen can be closed and
    // reopened in the same ProviderScope.
    Widget settings(FakeNip55PermissionStore store) => ProviderScope(
      overrides: [nip55PermissionStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrustedAppsScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('reopening shows a grant stored while it was closed', (
      tester,
    ) async {
      final store = FakeNip55PermissionStore();
      await tester.pumpWidget(settings(store));
      await open(tester);
      expect(find.textContaining('No remembered NIP-55'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Stored straight to the store, as Nip55Controller does.
      store.grants.add(_grant('grant-1', const GetPublicKeyScope()));
      await open(tester);

      expect(find.text('com.example.nostr'), findsWidgets);
      expect(find.textContaining('No remembered NIP-55'), findsNothing);
    });

    testWidgets('a reload while open keeps the list on screen', (tester) async {
      final store = FakeNip55PermissionStore()
        ..grants.add(_grant('grant-1', const GetPublicKeyScope()));
      await tester.pumpWidget(settings(store));
      await open(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrustedAppsScreen)),
      );

      store.grants.add(_grant('grant-2', const Nip04DecryptScope()));
      final reload = container
          .read(nip55PermissionControllerProvider.notifier)
          .load();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await reload;
      await tester.pumpAndSettle();

      expect(find.textContaining('NIP-04 decrypt'), findsOneWidget);
    });

    testWidgets('a grant shown after reopening can be revoked', (tester) async {
      final store = FakeNip55PermissionStore();
      await tester.pumpWidget(settings(store));
      await open(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      store.grants.add(_grant('grant-1', const GetPublicKeyScope()));
      await open(tester);

      await tester.tap(find.byTooltip('Revoke permission'));
      await tester.pumpAndSettle();

      expect(store.grants, isEmpty);
      expect(find.textContaining('No remembered NIP-55'), findsOneWidget);
    });
  });
}

Widget _app(FakeNip55PermissionStore store) {
  return ProviderScope(
    overrides: [nip55PermissionStoreProvider.overrideWithValue(store)],
    child: const MaterialApp(home: TrustedAppsScreen()),
  );
}

Nip55PermissionGrant _grant(String id, Nip55PermissionScope scope) {
  return Nip55PermissionGrant(
    id: id,
    identityPubkey: 'pubkey',
    packageName: 'com.example.nostr',
    scope: scope,
    decision: Nip55PermissionDecision.allow,
    createdAt: DateTime(2026, 5, 1),
  );
}
