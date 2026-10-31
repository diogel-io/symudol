


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../backup/application/backup_providers.dart';
import '../../backup/presentation/restore_backup_flow.dart';
import '../../profile/presentation/profile_edit_screen.dart';
import '../../vault/application/vault_providers.dart';
import 'widgets/identity_tile.dart';
import 'widgets/create_identity_dialog.dart';
import 'widgets/import_identity_dialog.dart';
import 'widgets/profile_avatar.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    // Forgot PIN → Restore from a backup: the new vault is set up, so the
    // restore opens now (#25).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(restoreAfterSetupProvider.notifier).take()) {
        restoreFromBackup(context, ref);
      }
    });
  }

  Future<void> _showImportIdentityDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ImportIdentityDialog(),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identity imported successfully'),
          backgroundColor: DiogelColors.stateSuccess,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultControllerState = ref.watch(vaultControllerProvider);
    final identities = vaultControllerState.identities;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/symudol.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: DiogelSpacing.space3),
            Text('Symudol', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DiogelSpacing.space4),
            child: const ProfileAvatar(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accounts',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  Text(
                    'Manage your Nostr identities',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DiogelColors.textSecondary,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _showCreateIdentityDialog(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add New'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DiogelSpacing.space4,
                    vertical: DiogelSpacing.space2,
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: DiogelSpacing.space8),
          
          if (identities.isEmpty)
            _buildEmptyState(context)
          else
            ...identities.map((identity) => Padding(
              padding: const EdgeInsets.only(bottom: DiogelSpacing.space4),
              child: IdentityTile(
                identity: identity,
                onTap: identity.isActive 
                  ? null 
                  : () => ref.read(vaultControllerProvider.notifier).setActiveIdentity(identity.localId),
                onEditProfile: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileEditScreen(identity: identity),
                  ),
                ),
              ),
            )),

          const SizedBox(height: DiogelSpacing.space4),
          InkWell(
            onTap: () => _showImportIdentityDialog(context),
            child: Container(
              padding: const EdgeInsets.all(DiogelSpacing.space6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DiogelRadius.large),
                border: Border.all(
                  color: DiogelColors.borderSubtle,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.add_circle_outline,
                    size: 32,
                    color: DiogelColors.textTertiary,
                  ),
                  const SizedBox(height: DiogelSpacing.space2),
                  Text(
                    'Import Private Key',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: DiogelColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space6),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: DiogelColors.textTertiary,
          ),
          const SizedBox(height: DiogelSpacing.space4),
          Text(
            'No Identities Found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            'Create or import your first Nostr identity to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: DiogelColors.textSecondary,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          OutlinedButton.icon(
            onPressed: () => restoreFromBackup(context, ref),
            icon: const Icon(Icons.restore),
            label: const Text('Restore from a backup'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateIdentityDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CreateIdentityDialog(),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identity created successfully'),
          backgroundColor: DiogelColors.stateSuccess,
        ),
      );
    }
  }
}
