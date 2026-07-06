import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/nip46_providers.dart';
import '../domain/nip46_session.dart';
import 'nip46_connection_qr_sheet.dart';
import 'nip46_connect_approval_screen.dart';

class Nip46ConnectionsScreen extends ConsumerWidget {
  const Nip46ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nip46ControllerProvider);
    final controller = ref.read(nip46ControllerProvider.notifier);

    // Navigate to approval screen when a session is pending approval.
    ref.listen(nip46ControllerProvider, (previous, next) {
      if (next.pendingApproval != null &&
          previous?.pendingApproval == null &&
          context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const Nip46ConnectApprovalScreen(),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Signer (NIP-46)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New connection',
            onPressed: () => _showConnectionSheet(context),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.failure != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error: ${state.failure}',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final activeSessions = state.sessions
              .where(
                (s) =>
                    s.status == Nip46SessionStatus.active ||
                    s.status == Nip46SessionStatus.pending,
              )
              .toList();

          if (activeSessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lan_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No remote signer connections',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to generate a bunker:// token or import a '
                      'nostrconnect:// token from a client app.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('New connection'),
                      onPressed: () => _showConnectionSheet(context),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: activeSessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = activeSessions[index];
              return _SessionTile(
                session: session,
                onRevoke: () async {
                  final confirmed = await _confirmRevoke(context, session);
                  if (confirmed == true) {
                    await controller.revokeSession(session.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showConnectionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const Nip46ConnectionQrSheet(),
    );
  }

  Future<bool?> _confirmRevoke(
    BuildContext context,
    Nip46Session session,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke connection?'),
        content: Text(
          'Revoke the remote signer connection for '
          '"${session.clientName ?? session.clientPubkey.substring(0, 8)}…"? '
          'This client will no longer be able to request signing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Nip46Session session;
  final VoidCallback onRevoke;

  const _SessionTile({required this.session, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final isPending = session.status == Nip46SessionStatus.pending;
    final name = session.clientName ??
        (session.clientPubkey.isNotEmpty
            ? '${session.clientPubkey.substring(0, 8)}…'
            : 'Awaiting connection…');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(isPending: isPending),
                        ],
                      ),
                      if (session.clientUrl != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          session.clientUrl!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: onRevoke,
                  child: const Text('Revoke'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.cell_tower,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '${session.relays.length} relay${session.relays.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                if (session.lastUsedAt != null) ...[
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Last used ${_formatTime(session.lastUsedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            if (session.grantedScopes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                session.grantedScopes.map((s) => s.wire).join(', '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusChip extends StatelessWidget {
  final bool isPending;
  const _StatusChip({required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPending
            ? Theme.of(context).colorScheme.tertiaryContainer
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isPending ? 'Pending' : 'Active',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isPending
              ? Theme.of(context).colorScheme.onTertiaryContainer
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
