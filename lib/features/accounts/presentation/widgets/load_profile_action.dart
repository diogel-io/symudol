import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/profile_load_state.dart';
import '../../../profile/domain/profile_relays.dart';

/// Asks the user before fetching one identity's profile, then loads it and
/// reports the outcome. Each relay learns the public key and the device's IP
/// address, so nothing is fetched unless the user confirms
/// (diogel-io/symudol#83).
Future<void> confirmAndLoadProfile(
  BuildContext context,
  WidgetRef ref,
  String pubkeyHex,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const LoadProfileDialog(),
  );
  if (confirmed != true) return;

  final result = await ref
      .read(nostrProfileProvider(pubkeyHex).notifier)
      .load();
  if (!context.mounted) return;

  if (result case ProfileLoaded(profile: null, :final searchedRelays)) {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          NoProfileFoundDialog(searchedRelays: searchedRelays),
    );
    return;
  }

  final (String message, Color color) = switch (result) {
    ProfileLoaded() => ('Profile loaded', DiogelColors.stateSuccess),
    _ => ("Couldn't reach the relays", DiogelColors.stateError),
  };
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
}

/// Names the relays a profile fetch will query and what they learn: the ones
/// chosen in Settings (diogel-io/symudol#45). Load waits until the settings
/// are read, so the relays named are the ones asked.
class LoadProfileDialog extends ConsumerWidget {
  const LoadProfileDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(profileNetworkSettingsProvider).value;
    final relays = settings == null
        ? null
        : profileRelays(
            const [],
            settings.profileRelays,
            settings.indexerRelays,
          ).map(relayHost).join(', ');
    return AlertDialog(
      title: const Text('Load profile from relays?'),
      content: Text(
        relays == null
            ? 'Reading your relay settings…'
            : 'Symudol will ask $relays, and the relays this identity lists '
                  'as its own, for this identity\'s profile. '
                  'They will see this public key and your IP address.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: relays == null
              ? null
              : () => Navigator.of(context).pop(true),
          child: const Text('Load profile'),
        ),
      ],
    );
  }
}

/// Says that no relay held a profile, and lists every relay searched
/// (diogel-io/symudol#42).
class NoProfileFoundDialog extends StatelessWidget {
  const NoProfileFoundDialog({super.key, required this.searchedRelays});

  final List<String> searchedRelays;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('No profile found'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'None of these relays holds a profile for this identity:',
            ),
            const SizedBox(height: DiogelSpacing.space2),
            for (final relay in searchedRelays) Text(relayHost(relay)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
