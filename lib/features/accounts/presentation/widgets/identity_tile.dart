import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';
import '../../../identity/domain/vault_identity.dart';

class IdentityTile extends StatelessWidget {
  final VaultIdentity identity;
  final VoidCallback? onTap;

  const IdentityTile({
    super.key,
    required this.identity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = identity.isActive;
    
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: isActive ? DiogelColors.surfaceBase : DiogelColors.surfaceBase,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
        border: Border.all(
          color: isActive ? DiogelColors.actionPrimary : DiogelColors.borderSubtle,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
              ),
              child: Icon(
                Icons.person,
                size: 32,
                color: isActive ? DiogelColors.actionPrimary : DiogelColors.textTertiary,
              ),
            ),
            const SizedBox(width: DiogelSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        identity.displayName ?? 'Unnamed Identity',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isActive ? DiogelColors.textPrimary : DiogelColors.textSecondary,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: DiogelSpacing.space2),
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: DiogelColors.actionPrimary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _truncateKey(identity.publicKey),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: isActive ? DiogelColors.actionPrimary.withValues(alpha: 0.8) : DiogelColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isActive)
              const Icon(Icons.chevron_right, color: DiogelColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _truncateKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }
}
