import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../nip55/domain/nip55_approval_timeframe.dart';

class TimeframeRow extends StatelessWidget {
  const TimeframeRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Nip55ApprovalTimeframe value;
  final ValueChanged<Nip55ApprovalTimeframe> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DiogelSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remember this decision',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: DiogelColors.textSecondary,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space2),
          SegmentedButton<Nip55ApprovalTimeframe>(
            segments: const [
              ButtonSegment(
                value: Nip55ApprovalTimeframe.justOnce,
                label: Text('Just once'),
                icon: Icon(Icons.looks_one_outlined),
              ),
              ButtonSegment(
                value: Nip55ApprovalTimeframe.eightHours,
                label: Text('8 hours'),
                icon: Icon(Icons.schedule),
              ),
              ButtonSegment(
                value: Nip55ApprovalTimeframe.always,
                label: Text('Always'),
                icon: Icon(Icons.verified_user_outlined),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space1),
          Text(
            _hintFor(value),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: DiogelColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  static String _hintFor(Nip55ApprovalTimeframe timeframe) => switch (timeframe) {
    Nip55ApprovalTimeframe.justOnce =>
      'This decision applies to this single request only.',
    Nip55ApprovalTimeframe.eightHours =>
      'Requests from this app will be auto-approved for 8 hours.',
    Nip55ApprovalTimeframe.always =>
      'All future requests from this app will be auto-approved.',
  };
}
