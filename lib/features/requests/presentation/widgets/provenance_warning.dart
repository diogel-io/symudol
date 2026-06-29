import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../domain/request_trust_status.dart';

class ProvenanceWarning extends StatelessWidget {
  const ProvenanceWarning({super.key, required this.trustStatus});

  final RequestTrustStatus trustStatus;

  @override
  Widget build(BuildContext context) {
    if (trustStatus == RequestTrustStatus.knownTrusted) {
      return const SizedBox.shrink();
    }

    final isUntrusted =
        trustStatus == RequestTrustStatus.knownUntrusted ||
        trustStatus == RequestTrustStatus.invalid;
    final color = isUntrusted ? DiogelColors.stateError : DiogelColors.stateWarning;
    final title = isUntrusted ? 'Untrusted Source' : 'Unknown Provenance';
    final message = isUntrusted
        ? 'This request comes from a known malicious or invalid source. DO NOT SIGN unless you are absolutely sure.'
        : 'The requesting application is not in your verified list. Exercise caution.';

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isUntrusted ? Icons.gpp_bad : Icons.warning, color: color),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
                ),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
