import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

class InactiveAccountTile extends StatelessWidget {
  final String name;
  final String npub;

  const InactiveAccountTile({
    super.key,
    required this.name,
    required this.npub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBase,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: DiogelColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DiogelRadius.medium),
            ),
            child: const Icon(
              Icons.person,
              size: 32,
              color: DiogelColors.textTertiary,
            ),
          ),
          const SizedBox(width: DiogelSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: DiogelColors.textSecondary,
                  ),
                ),
                Text(
                  npub,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: DiogelColors.textTertiary),
        ],
      ),
    );
  }
}
