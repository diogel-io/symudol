import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../theme/tokens.dart';
import '../../../nip55/application/nip55_providers.dart';
import '../../domain/known_app_directory.dart';

class RequestSummaryCard extends ConsumerWidget {
  const RequestSummaryCard({
    super.key,
    required this.icon,
    required this.iconColor,
    this.packageName,
    required this.sourceName,
    required this.sourceVerified,
  });

  final IconData icon;
  final Color iconColor;
  final String? packageName;
  final String sourceName;
  final bool sourceVerified;

  static final _packageNamePattern = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDescription = describeKnownPackage(packageName);

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainer,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceIcon(ref),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sourceName,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sourceVerified) ...[
                      const SizedBox(width: DiogelSpacing.space2),
                      const Icon(
                        Icons.verified,
                        size: 16,
                        color: DiogelColors.stateSuccess,
                      ),
                    ],
                  ],
                ),
                if (appDescription != null) ...[
                  const SizedBox(height: DiogelSpacing.space1),
                  Text(
                    appDescription,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DiogelColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceIcon(WidgetRef ref) {
    const size = 40.0;

    Widget fallback() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(DiogelRadius.small),
      ),
      child: Icon(icon, color: iconColor),
    );

    final pkg = packageName;
    if (pkg == null || !_packageNamePattern.hasMatch(pkg)) return fallback();

    final appIcon = ref.watch(appIconProvider(pkg));
    final bytes = appIcon.value;
    if (bytes == null || bytes.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(DiogelRadius.small),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }
}
