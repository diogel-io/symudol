import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';

class RememberRow extends StatelessWidget {
  const RememberRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(bottom: DiogelSpacing.space2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Expanded(
              child: Text(
                'Remember this decision for this app',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Tooltip(
              message:
                  'Remembered decisions only auto-approve while your '
                  'short approval session is active. Browser requests '
                  'cannot be remembered.',
              child: const Icon(
                Icons.info_outline,
                size: 16,
                color: DiogelColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
