import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/app/system_picker.dart';
import 'package:symudol/app/utils/concurrency_utils.dart';
import 'package:symudol/features/accounts/presentation/accounts_screen.dart';
import 'package:symudol/features/backup/application/backup_providers.dart';
import 'package:symudol/features/backup/data/scrypt_kdf.dart';
import 'package:symudol/features/backup/domain/vault_backup.dart';
import 'package:symudol/features/backup/presentation/backup_vault_screen.dart';
import 'package:symudol/features/profile/application/profile_providers.dart';
import 'package:symudol/features/vault/application/vault_controller.dart';
import 'package:symudol/features/vault/application/vault_providers.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

import '../../../fakes/fake_backup_files.dart';
import '../../../fakes/fake_profile_network_store.dart';
import '../../../fakes/fake_vault_store.dart';

const _pin = '123456';
const _passphrase = 'correct horse battery staple';

/// Settings → Backup Vault and the restore flow (diogel-io/symudol#25).
void main() {
  late VaultServiceImpl vault;
  late VaultController controller;
  late FakeBackupFiles files;

  setUp(() async {
    ConcurrencyUtils.useSynchronousTasks = true;
    vault = VaultServiceImpl(
      FakeVaultStore(),
      keyDeriver: const DartNip49KeyDeriver(),
    );
    await vault.createVault(_pin);
    await vault.createIdentity(displayName: 'Work');
    controller = VaultController(vault);
    await controller.initialize();
    await controller.unlock(_pin);
    files = FakeBackupFiles();
  });

  tearDown(() => ConcurrencyUtils.useSynchronousTasks = false);

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultServiceProvider.overrideWithValue(vault),
          vaultControllerProvider.overrideWith((ref) => controller),
          backupFilesProvider.overrideWithValue(files),
          profileNetworkStoreProvider.overrideWithValue(
            FakeProfileNetworkStore(),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPassphrase(WidgetTester tester, String a, String b) async {
    await tester.enterText(find.byKey(const Key('backupPassphraseField')), a);
    await tester.enterText(find.byKey(const Key('backupConfirmField')), b);
    await tester.pump();
  }

  FilledButton backUpButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Back up and share'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ),
  );

  /// Lets the PIN check, scrypt and storage finish: a spinner is showing
  /// meanwhile, so pumpAndSettle alone would never settle.
  Future<void> finishWork(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      final busy =
          find.text('Encrypting…').evaluate().isNotEmpty ||
          find.text('Restoring…').evaluate().isNotEmpty;
      if (!busy && i > 0) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> backUpWithPin(WidgetTester tester, String pin) async {
    await tester.tap(find.text('Back up and share'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('backupPinField')), pin);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await finishWork(tester);
  }

  testWidgets('warns before anything is backed up', (tester) async {
    await pump(tester, const BackupVaultScreen());

    expect(find.textContaining('Anyone with the file and the'), findsOneWidget);
    expect(find.textContaining("can't recover a"), findsOneWidget);
  });

  testWidgets('needs a long, confirmed passphrase', (tester) async {
    await pump(tester, const BackupVaultScreen());

    await enterPassphrase(tester, 'too short', 'too short');
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(backUpButton(tester).onPressed, isNull);

    await enterPassphrase(tester, _passphrase, '$_passphrase!');
    expect(find.text("The passphrases don't match."), findsOneWidget);
    expect(backUpButton(tester).onPressed, isNull);

    await enterPassphrase(tester, _passphrase, _passphrase);
    expect(backUpButton(tester).onPressed, isNotNull);
  });

  testWidgets('asks for the PIN, then shares a file that opens with the '
      'passphrase', (tester) async {
    await pump(tester, const BackupVaultScreen());
    await enterPassphrase(tester, _passphrase, _passphrase);

    await backUpWithPin(tester, _pin);

    final shared = files.shared.single;
    expect(shared.fileName, startsWith('symudol-backup-'));
    final restored = await tester.runAsync(
      () => decryptVaultBackup(
        shared.file,
        _passphrase,
        deriver: const DartNip49KeyDeriver(),
      ),
    );
    expect(restored!.single.name, 'Work');
    expect(find.textContaining('Backup made.'), findsOneWidget);
  });

  testWidgets('a dismissed share sheet says the backup was not saved', (
    tester,
  ) async {
    files.completesShare = false;
    await pump(tester, const BackupVaultScreen());
    await enterPassphrase(tester, _passphrase, _passphrase);

    await backUpWithPin(tester, _pin);

    expect(
      find.text('The backup was not shared. Back up again to save it.'),
      findsOneWidget,
    );
    expect(find.textContaining('Backup made.'), findsNothing);
  });

  testWidgets('the background lock waits while the share sheet and the '
      'document picker are open', (tester) async {
    final open = <bool>[];
    await pump(tester, const BackupVaultScreen());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BackupVaultScreen)),
    );
    files.whileOpen = () => open.add(container.read(systemPickerOpenProvider));
    await enterPassphrase(tester, _passphrase, _passphrase);

    await backUpWithPin(tester, _pin);
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();

    expect(open, [true, true]);
    expect(container.read(systemPickerOpenProvider), isFalse);
  });

  testWidgets('a wrong PIN shares nothing', (tester) async {
    await pump(tester, const BackupVaultScreen());
    await enterPassphrase(tester, _passphrase, _passphrase);

    await backUpWithPin(tester, '000000');

    expect(files.shared, isEmpty);
    expect(find.text('Invalid PIN. Please try again.'), findsOneWidget);
  });

  group('restoring', () {
    Future<void> restoreWith(WidgetTester tester, String passphrase) async {
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('restorePassphraseField')),
        passphrase,
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pump();
      await finishWork(tester);
    }

    Future<void> holdBackupFromAnotherVault() async {
      final other = VaultServiceImpl(
        FakeVaultStore(),
        keyDeriver: const DartNip49KeyDeriver(),
      );
      await other.createVault('111111');
      await other.createIdentity(displayName: 'Personal');
      files.picked = await other.exportBackup(
        pin: '111111',
        passphrase: _passphrase,
      );
    }

    testWidgets('adds the identities and says what it did', (tester) async {
      await holdBackupFromAnotherVault();
      await pump(tester, const BackupVaultScreen());

      await restoreWith(tester, _passphrase);

      expect(find.text('Backup restored'), findsOneWidget);
      expect(find.text('Restored 1 identity.'), findsOneWidget);
      expect(
        (await vault.listIdentities()).map((i) => i.displayName),
        unorderedEquals(['Work', 'Personal']),
      );
    });

    testWidgets('a wrong passphrase restores nothing', (tester) async {
      await holdBackupFromAnotherVault();
      await pump(tester, const BackupVaultScreen());

      await restoreWith(tester, 'not the passphrase at all');

      expect(
        find.text("That passphrase doesn't open this backup."),
        findsOneWidget,
      );
      expect(await vault.listIdentities(), hasLength(1));
    });

    testWidgets('cancelling the file picker asks nothing more', (tester) async {
      await pump(tester, const BackupVaultScreen());

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(files.picks, 1);
      expect(find.byKey(const Key('restorePassphraseField')), findsNothing);
    });
  });

  group('Accounts (#25)', () {
    setUp(() async {
      final empty = VaultServiceImpl(
        FakeVaultStore(),
        keyDeriver: const DartNip49KeyDeriver(),
      );
      await empty.createVault(_pin);
      vault = empty;
      controller = VaultController(vault);
      await controller.initialize();
      await controller.unlock(_pin);
    });

    testWidgets('an empty vault offers a restore', (tester) async {
      await pump(tester, const AccountsScreen());

      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(files.picks, 1);
    });

    testWidgets('a restore asked for in Forgot PIN opens after setup', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          vaultServiceProvider.overrideWithValue(vault),
          vaultControllerProvider.overrideWith((ref) => controller),
          backupFilesProvider.overrideWithValue(files),
          profileNetworkStoreProvider.overrideWithValue(
            FakeProfileNetworkStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(restoreAfterSetupProvider.notifier).request();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(files.picks, 1);
      expect(container.read(restoreAfterSetupProvider), isFalse);
    });
  });
}
