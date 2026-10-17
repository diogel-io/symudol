import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/data/relay_profile_service.dart';
import '../../../profile/domain/profile_load_state.dart';

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

  final result =
      await ref.read(nostrProfileProvider(pubkeyHex).notifier).load();
  if (!context.mounted) return;

  final (String message, Color? color) = switch (result) {
    ProfileLoaded(profile: != null) => (
        'Profile loaded',
        DiogelColors.stateSuccess,
      ),
    ProfileLoaded() => ('No profile found on these relays', null),
    _ => ("Couldn't reach the relays", DiogelColors.stateError),
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: color),
  );
}

/// Names the relays a profile fetch will query and what they learn.
class LoadProfileDialog extends StatelessWidget {
  const LoadProfileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final relays = RelayProfileService.defaultRelays
        .map((url) => url.replaceFirst('wss://', ''))
        .join(' and ');
    return AlertDialog(
      title: const Text('Load profile from relays?'),
      content: Text(
        'Symudol will ask $relays for this identity\'s profile. '
        'They will see this public key and your IP address.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Load profile'),
        ),
      ],
    );
  }
}
