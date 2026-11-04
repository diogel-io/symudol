import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import '../data/profile_relay_client.dart';
import '../domain/profile_relays.dart';

/// How each relay answered a published event: a profile (#41) or a relay
/// list (#88).
class PublishResultsSheet extends StatelessWidget {
  const PublishResultsSheet({
    super.key,
    required this.title,
    required this.results,
  });

  final String title;
  final Map<String, RelayPublishResult> results;

  @override
  Widget build(BuildContext context) {
    final accepted = results.values.where((result) => result.accepted).length;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: DiogelSpacing.space2),
          Text('$accepted of ${results.length} relays accepted it.'),
          const SizedBox(height: DiogelSpacing.space3),
          for (final MapEntry(key: relay, value: result) in results.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (result.status) {
                  RelayPublishStatus.accepted => Icons.check_circle,
                  RelayPublishStatus.rejected => Icons.cancel,
                  RelayPublishStatus.noAnswer => Icons.help_outline,
                },
                color: switch (result.status) {
                  RelayPublishStatus.accepted => DiogelColors.stateSuccess,
                  RelayPublishStatus.rejected => DiogelColors.stateError,
                  RelayPublishStatus.noAnswer => DiogelColors.textTertiary,
                },
              ),
              title: Text(relayHost(relay)),
              subtitle: Text(
                switch (result.status) {
                      RelayPublishStatus.accepted => 'Accepted',
                      RelayPublishStatus.rejected => 'Rejected',
                      RelayPublishStatus.noAnswer => 'No answer',
                    } +
                    (result.message.isEmpty ? '' : ': ${result.message}'),
              ),
            ),
        ],
      ),
    );
  }
}
