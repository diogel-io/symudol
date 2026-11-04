import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../domain/profile_relays.dart';

/// Asks before signing [subject] with [identityName] and publishing it to
/// [relays], naming each one: a profile (#41) or a relay list (#88). Pops
/// true to publish.
class PublishDialog extends StatelessWidget {
  const PublishDialog({
    super.key,
    required this.subject,
    required this.identityName,
    required this.relays,
  });

  /// What is published, such as "profile" or "relay list".
  final String subject;
  final String identityName;
  final List<String> relays;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign and publish?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Symudol will sign this $subject with $identityName and '
              'publish it to ${relays.length} relays:',
            ),
            const SizedBox(height: DiogelSpacing.space2),
            for (final relay in relays) Text(relayHost(relay)),
            const SizedBox(height: DiogelSpacing.space3),
            Text('Anyone can read a published $subject.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign and publish'),
        ),
      ],
    );
  }
}
