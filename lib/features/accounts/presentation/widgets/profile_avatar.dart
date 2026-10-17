import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../vault/application/vault_providers.dart';

/// Displays the active Nostr identity's profile picture once the user has
/// loaded its profile, falling back to a generic person icon until then, on
/// error, or if none is set. It never fetches a profile itself.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, this.radius = 16});

  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIdentity = ref.watch(vaultControllerProvider).activeIdentity;

    String? pictureUrl;
    if (activeIdentity != null) {
      pictureUrl = ref
          .watch(nostrProfileProvider(activeIdentity.publicKey))
          .profile
          ?.picture;
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: DiogelColors.surfaceContainerHigh,
      child: ClipOval(
        child: (pictureUrl == null || pictureUrl.isEmpty)
            ? _fallbackIcon()
            : Image.network(
                pictureUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
              ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Icon(
      Icons.person,
      size: radius * 1.25,
      color: DiogelColors.textSecondary,
    );
  }
}