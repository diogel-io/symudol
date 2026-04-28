import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import 'widgets/request_detail_item.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signing Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DiogelSpacing.space4,
          DiogelSpacing.space4,
          DiogelSpacing.space4,
          120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.stateError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(
                  color: DiogelColors.stateError.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning, color: DiogelColors.stateError),
                  const SizedBox(width: DiogelSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unknown Provenance',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: DiogelColors.stateError),
                        ),
                        Text(
                          'The requesting application is not in your verified list. Exercise caution.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: DiogelColors.stateError),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DiogelSpacing.space6),
            Text(
              'REQUEST SOURCE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DiogelColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: DiogelSpacing.space2),
            const RequestDetailItem(
              icon: Icons.apps,
              iconColor: DiogelColors.actionPrimary,
              title: 'Amethyst',
              subtitle: 'nostr:amethyst:client',
            ),
            const SizedBox(height: DiogelSpacing.space4),
            Text(
              'ACTION TYPE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DiogelColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: DiogelSpacing.space2),
            const RequestDetailItem(
              icon: Icons.edit_note,
              iconColor: DiogelColors.nostrAccentMuted,
              title: 'Sign Kind 1 Event',
              subtitle: 'Standard Text Note',
            ),
            const SizedBox(height: DiogelSpacing.space6),
            Text(
              'SIGNING WITH ACCOUNT',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: DiogelColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: DiogelSpacing.space2),
            Container(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainer,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(color: DiogelColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: DiogelColors.actionPrimary,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 24,
                      color: DiogelColors.actionPrimary,
                    ),
                  ),
                  const SizedBox(width: DiogelSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Satoshi\'s Vault',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'npub1...a4f2',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: DiogelColors.actionPrimary,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.verified,
                    color: DiogelColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: DiogelSpacing.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'EVENT DETAILS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: DiogelColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Text(
                    'Raw JSON',
                    style: TextStyle(
                      color: DiogelColors.actionPrimary,
                      fontSize: 12,
                    ),
                  ),
                  label: const Icon(
                    Icons.expand_more,
                    color: DiogelColors.actionPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(color: DiogelColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTENT',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: DiogelSpacing.space2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DiogelSpacing.space3),
                    decoration: BoxDecoration(
                      color: DiogelColors.surfaceBase,
                      borderRadius: BorderRadius.circular(DiogelRadius.small),
                      border: Border.all(
                        color: DiogelColors.borderSubtle.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      '"Hello Nostr! Signing this message from my secure vault. Security first, always."',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: DiogelSpacing.space4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CREATED AT',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              '1715432001',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TAGS',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              '[]',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ],
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
      bottomSheet: Container(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        decoration: BoxDecoration(
          color: DiogelColors.surfaceBackground.withValues(alpha: 0.8),
          border: const Border(
            top: BorderSide(color: DiogelColors.borderSubtle),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: DiogelSpacing.space4,
                      ),
                      side: const BorderSide(
                        color: DiogelColors.borderStrong,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DiogelRadius.medium,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DiogelSpacing.space4),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: DiogelSpacing.space4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DiogelRadius.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              'This action will generate a digital signature using your private key.',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
