import 'package:android_diogel/features/nip55/application/nip55_providers.dart';
import 'package:android_diogel/features/nip55/domain/nip55_client_permission.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_decision.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_scope.dart';
import 'package:android_diogel/features/nip55/domain/nip55_permission_store.dart';
import 'package:android_diogel/features/settings/presentation/trusted_apps_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNip55PermissionStore implements Nip55PermissionStore {
  final grants = <Nip55PermissionGrant>[];

  @override
  Future<void> clearAll() async => grants.clear();

  @override
  Future<void> deleteAllForPackage(String packageName) async {
    grants.removeWhere((grant) => grant.packageName == packageName);
  }

  @override
  Future<void> deleteGrant(String id) async {
    grants.removeWhere((grant) => grant.id == id);
  }

  @override
  Future<List<Nip55PermissionGrant>> listGrants() async => List.of(grants);

  @override
  Future<void> saveGrant(Nip55PermissionGrant grant) async {
    grants.removeWhere((existing) => existing.id == grant.id);
    grants.add(grant);
  }
}

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
    expect(find.textContaining('not permanent silent trust'), findsOneWidget);
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
