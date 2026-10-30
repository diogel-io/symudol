import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens.dart';
import '../../../identity/domain/vault_identity.dart';
import '../../../profile/application/profile_providers.dart';
import '../../../profile/domain/profile_load_state.dart';
import 'load_profile_action.dart';

class IdentityTile extends ConsumerWidget {
  final VaultIdentity identity;
  final VoidCallback? onTap;

  /// Opens the profile editor; offered on the active identity only
  /// (diogel-io/symudol#41).
  final VoidCallback? onEditProfile;

  const IdentityTile({
    super.key,
    required this.identity,
    this.onTap,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = identity.isActive;
    // Watching never fetches: the picture appears only after the user loads
    // this identity's profile.
    final profileState = ref.watch(nostrProfileProvider(identity.publicKey));
    final pictureUrl = profileState.profile?.picture;

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: isActive ? DiogelColors.surfaceBase : DiogelColors.surfaceBase,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
        border: Border.all(
          color: isActive ? DiogelColors.actionPrimary : DiogelColors.borderSubtle,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                child: (pictureUrl == null || pictureUrl.isEmpty)
                    ? Icon(
                        Icons.person,
                        size: 32,
                        color: isActive ? DiogelColors.actionPrimary : DiogelColors.textTertiary,
                      )
                    : Image.network(
                        pictureUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.person,
                          size: 32,
                          color: isActive ? DiogelColors.actionPrimary : DiogelColors.textTertiary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: DiogelSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        identity.displayName ?? 'Unnamed Identity',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isActive ? DiogelColors.textPrimary : DiogelColors.textSecondary,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: DiogelSpacing.space2),
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: DiogelColors.actionPrimary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _truncateKey(_npubFor(identity.publicKey)),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: isActive ? DiogelColors.actionPrimary.withValues(alpha: 0.8) : DiogelColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (profileState is ProfileLoading)
              const Padding(
                padding: EdgeInsets.all(DiogelSpacing.space3),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              if (isActive && onEditProfile != null)
                IconButton(
                  tooltip: 'Edit profile',
                  icon: const Icon(Icons.edit_outlined),
                  color: DiogelColors.textTertiary,
                  onPressed: onEditProfile,
                ),
              IconButton(
                tooltip: 'Load profile',
                icon: const Icon(Icons.cloud_download_outlined),
                color: DiogelColors.textTertiary,
                onPressed: () =>
                    confirmAndLoadProfile(context, ref, identity.publicKey),
              ),
            ],
            if (!isActive)
              const Icon(Icons.chevron_right, color: DiogelColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _npubFor(String publicKey) {
    try {
      return Nostr.instance.services.bech32.encodePublicKeyToNpub(publicKey);
    } catch (_) {
      return publicKey;
    }
  }

  String _truncateKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }
}
