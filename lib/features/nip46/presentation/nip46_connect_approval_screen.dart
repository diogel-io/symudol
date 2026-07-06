import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/nip46_providers.dart';
import '../domain/nip46_permission_scope.dart';
import '../domain/nip46_session.dart';

class Nip46ConnectApprovalScreen extends ConsumerWidget {
  const Nip46ConnectApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nip46ControllerProvider);
    final controller = ref.read(nip46ControllerProvider.notifier);
    final session = state.pendingApproval;

    // Pop when approval is cleared (approved or rejected).
    ref.listen(nip46ControllerProvider, (previous, next) {
      if (previous?.pendingApproval != null &&
          next.pendingApproval == null &&
          context.mounted) {
        Navigator.of(context).pop();
      }
    });

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Signer Request'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metadataWarningBanner(context),
                    const SizedBox(height: 20),
                    _ClientInfoSection(session: session),
                    const SizedBox(height: 20),
                    _RelaysSection(session: session),
                    if (session.grantedScopes.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _PermissionsSection(scopes: session.grantedScopes),
                    ],
                  ],
                ),
              ),
            ),
            _ActionBar(
              onApprove: () => controller.approveConnection(),
              onReject: () => controller.rejectConnection(),
              isLoading: state.isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataWarningBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: Theme.of(context).colorScheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Identity unverified — client name, URL, and image are '
              'unauthenticated metadata and cannot be trusted.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientInfoSection extends StatelessWidget {
  final Nip46Session session;
  const _ClientInfoSection({required this.session});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requesting client',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.lan_outlined,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.clientName ?? 'Unknown client',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (session.clientUrl != null)
                    Text(
                      session.clientUrl!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Client pubkey: ${_shortPubkey(session.clientPubkey)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  String _shortPubkey(String pubkey) {
    if (pubkey.isEmpty) return 'unknown';
    if (pubkey.length <= 12) return pubkey;
    return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 6)}';
  }
}

class _RelaysSection extends StatelessWidget {
  final Nip46Session session;
  const _RelaysSection({required this.session});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Relays (${session.relays.length})',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        for (final relay in session.relays)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.cell_tower,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    relay,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PermissionsSection extends StatelessWidget {
  final List<Nip46PermissionScope> scopes;
  const _PermissionsSection({required this.scopes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requested permissions',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        for (final scope in scopes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  scope.isSensitive ? Icons.lock_outlined : Icons.check_circle_outline,
                  size: 14,
                  color: scope.isSensitive
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  scope.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scope.isSensitive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool isLoading;

  const _ActionBar({
    required this.onApprove,
    required this.onReject,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: isLoading ? null : onReject,
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: isLoading ? null : onApprove,
              child: const Text('Approve'),
            ),
          ),
        ],
      ),
    );
  }
}
