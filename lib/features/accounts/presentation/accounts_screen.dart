import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../vault/application/vault_providers.dart';
import 'widgets/identity_tile.dart';
import 'widgets/create_identity_dialog.dart';
import 'widgets/import_identity_dialog.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultControllerState = ref.watch(vaultControllerProvider);
    final identities = vaultControllerState.identities;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.privacy_tip, color: DiogelColors.actionPrimary),
            const SizedBox(width: DiogelSpacing.space3),
            Text('Diogel', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DiogelSpacing.space4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: DiogelColors.surfaceContainerHigh,
              child: const Icon(
                Icons.person,
                size: 20,
                color: DiogelColors.textSecondary,
              ),
            ),
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
          const SizedBox(height: DiogelSpacing.space8),
          Container(
            padding: const EdgeInsets.all(DiogelSpacing.space4),
            decoration: BoxDecoration(
              color: DiogelColors.surfaceBase,
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              border: Border.all(color: DiogelColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user, color: DiogelColors.stateInfo),
                const SizedBox(width: DiogelSpacing.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure Local Storage',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: DiogelSpacing.space1),
                      Text(
                        'All private keys are stored locally using the device platform secure-storage backend and never leave your device.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
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
