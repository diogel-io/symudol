import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import 'widgets/inactive_account_tile.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                onPressed: () {},
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
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              side: const BorderSide(
                color: DiogelColors.actionPrimary,
                width: 0.5,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DiogelSpacing.space3,
                      vertical: DiogelSpacing.space1,
                    ),
                    decoration: const BoxDecoration(
                      color: DiogelColors.actionPrimary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(DiogelRadius.medium),
                        topRight: Radius.circular(DiogelRadius.large),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 12,
                          color: DiogelColors.textInverse,
                        ),
                        const SizedBox(width: DiogelSpacing.space1),
                        Text(
                          'Active',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: DiogelColors.textInverse),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(DiogelSpacing.space4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: DiogelColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(
                                DiogelRadius.medium,
                              ),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 40,
                              color: DiogelColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: DiogelSpacing.space4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'satoshi_vision',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: DiogelSpacing.space2,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            DiogelColors.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(
                                          DiogelRadius.small,
                                        ),
                                      ),
                                      child: Text(
                                        'npub1...7jk9',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: DiogelColors.actionPrimary,
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: DiogelSpacing.space2),
                                    const Icon(
                                      Icons.content_copy,
                                      size: 16,
                                      color: DiogelColors.textTertiary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DiogelSpacing.space4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(
                                DiogelSpacing.space3,
                              ),
                              decoration: BoxDecoration(
                                color: DiogelColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(
                                  DiogelRadius.medium,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Followers',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  Text(
                                    '12.4K',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: DiogelSpacing.space2),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(
                                DiogelSpacing.space3,
                              ),
                              decoration: BoxDecoration(
                                color: DiogelColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(
                                  DiogelRadius.medium,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Posts',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  Text(
                                    '842',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          const InactiveAccountTile(name: 'dev_mainnet', npub: 'npub1...a2x4'),
          const SizedBox(height: DiogelSpacing.space4),
          const InactiveAccountTile(
            name: 'creative_soul',
            npub: 'npub1...q9w1',
          ),
          const SizedBox(height: DiogelSpacing.space4),
          Container(
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
                        'End-to-End Encryption',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: DiogelSpacing.space1),
                      Text(
                        'All private keys are encrypted on-device with AES-256 and never leave your secure hardware element.',
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
}
