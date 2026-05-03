import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../nip55/application/nip55_providers.dart';
import '../../nip55/domain/nip55_client_permission.dart';
import '../../nip55/domain/nip55_permission_decision.dart';

class TrustedAppsScreen extends ConsumerWidget {
  const TrustedAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nip55PermissionControllerProvider);
    final controller = ref.read(nip55PermissionControllerProvider.notifier);
    final groups = _groupByPackage(state.grants);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Nostr apps'),
        actions: [
          if (state.grants.isNotEmpty)
            TextButton(
              onPressed: () => _confirmRevokeAll(context, controller.revokeAll),
              child: const Text('Revoke all'),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.grants.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(DiogelSpacing.space4),
                child: Text(
                  'No remembered NIP-55 app permissions yet. Approvals you remember from signer requests will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              itemCount: groups.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: DiogelSpacing.space4),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _TrustedAppCard(
                  group: group,
                  onRevokeGrant: controller.revokeGrant,
                  onRevokePackage: (packageName) => _confirmRevokePackage(
                    context,
                    packageName,
                    () => controller.revokePackage(packageName),
                  ),
                );
              },
            ),
    );
  }

  List<_TrustedAppGroup> _groupByPackage(List<Nip55PermissionGrant> grants) {
    final grouped = <String, List<Nip55PermissionGrant>>{};
    for (final grant in grants) {
      final key = grant.packageName ?? 'unknown';
      grouped.putIfAbsent(key, () => []).add(grant);
    }
    final groups = grouped.entries.map((entry) {
      final items = [...entry.value]
        ..sort((a, b) => _activityDate(b).compareTo(_activityDate(a)));
      return _TrustedAppGroup(packageName: entry.key, grants: items);
    }).toList();
    groups.sort(
      (a, b) => _activityDate(b.latest).compareTo(_activityDate(a.latest)),
    );
    return groups;
  }

  DateTime _activityDate(Nip55PermissionGrant grant) {
    return grant.lastUsedAt ?? grant.createdAt;
  }

  Future<void> _confirmRevokePackage(
    BuildContext context,
    String packageName,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke app permissions?'),
        content: Text(
          'Remove all remembered NIP-55 permissions for $packageName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true) await action();
  }

  Future<void> _confirmRevokeAll(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke all trusted apps?'),
        content: const Text(
          'Remove every remembered NIP-55 allow/reject decision? Future requests will ask again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke all'),
          ),
        ],
      ),
    );
    if (confirmed == true) await action();
  }
}

class _TrustedAppCard extends StatelessWidget {
  final _TrustedAppGroup group;
  final Future<void> Function(String id) onRevokeGrant;
  final Future<void> Function(String packageName) onRevokePackage;

  const _TrustedAppCard({
    required this.group,
    required this.onRevokeGrant,
    required this.onRevokePackage,
  });

  @override
  Widget build(BuildContext context) {
    final latest = group.latest;
    final title = latest.userLabel ?? group.packageName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DiogelSpacing.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: DiogelSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(group.packageName),
                      Text('Identity ${_short(latest.identityPubkey)}'),
                      Text('Last used ${_formatDate(latest.lastUsedAt)}'),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => onRevokePackage(group.packageName),
                  child: const Text('Revoke app'),
                ),
              ],
            ),
            const Divider(),
            for (final grant in group.grants)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(grant)),
                title: Text('${_decisionLabel(grant)} • ${grant.scope.label}'),
                subtitle: Text(
                  '${_statusLabel(grant)} • Last used ${_formatDate(grant.lastUsedAt)}\n'
                  'Created ${_formatDate(grant.createdAt)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Revoke permission',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRevokeGrant(grant.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(Nip55PermissionGrant grant) {
    return switch (grant.decision) {
      Nip55PermissionDecision.allow => Icons.check_circle_outline,
      Nip55PermissionDecision.reject => Icons.block_outlined,
      Nip55PermissionDecision.ask => Icons.help_outline,
    };
  }

  String _decisionLabel(Nip55PermissionGrant grant) {
    return switch (grant.decision) {
      Nip55PermissionDecision.allow => 'Allowed',
      Nip55PermissionDecision.reject => 'Rejected',
      Nip55PermissionDecision.ask => 'Ask every time',
    };
  }

  String _statusLabel(Nip55PermissionGrant grant) {
    if (grant.isExpired) return 'Expired';
    final expiry = grant.expiresAt;
    if (expiry == null) return 'No expiry';
    return 'Expires ${_formatDate(expiry)}';
  }

  String _short(String value) {
    if (value.length <= 12) return value;
    return '${value.substring(0, 6)}…${value.substring(value.length - 6)}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'never';
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TrustedAppGroup {
  final String packageName;
  final List<Nip55PermissionGrant> grants;

  const _TrustedAppGroup({required this.packageName, required this.grants});

  Nip55PermissionGrant get latest => grants.first;
}
