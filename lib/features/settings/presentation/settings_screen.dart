import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../nip46/presentation/nip46_connections_screen.dart';
import '../../vault/application/vault_providers.dart';
import 'trusted_apps_screen.dart';
import 'widgets/settings_tile.dart';

String formatInactivityTimeout(int minutes) {
  return switch (minutes) {
    0 => 'Never while app is open',
    1 => '1 minute',
    60 => '1 hour',
    _ => '$minutes minutes',
  };
}

String formatBackgroundLockDelay(int minutes) {
  return switch (minutes) {
    -1 => 'Never while app is running',
    0 => 'Immediately',
    1 => '1 minute',
    60 => '1 hour',
    _ => '$minutes minutes',
  };
}

String formatApprovalSessionDuration(int minutes) {
  return switch (minutes) {
    0 => 'Ask every time',
    1 => '1 minute',
    _ => '$minutes minutes',
  };
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultControllerState = ref.watch(vaultControllerProvider);
    final timeoutMinutes = vaultControllerState.inactivityTimeoutMinutes;
    final backgroundLockDelayMinutes =
        vaultControllerState.backgroundLockDelayMinutes;
    final approvalSessionDurationMinutes =
        vaultControllerState.approvalSessionDurationMinutes;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Text(
            'SECURITY',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: DiogelColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space2),
          const SettingsTile(
            icon: Icons.lock_outline,
            title: 'Change PIN',
            subtitle: 'Update your security access code',
          ),
          SettingsTile(
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: 'Not available yet — PIN unlock remains required',
            trailing: const Switch(value: false, onChanged: null),
          ),
          SettingsTile(
            icon: Icons.timer_outlined,
            title: 'In-app inactivity timeout',
            subtitle:
                'Locks when you stop using Diogel while it is open: '
                '${formatInactivityTimeout(timeoutMinutes)}',
            onTap: () async {
              final newValue = await showDialog<int>(
                context: context,
                builder: (context) => _TimeoutPickerDialog(
                  title: 'In-app inactivity timeout',
                  initialValue: timeoutMinutes,
                  options: const [
                    _TimeoutOption(0, 'Never while app is open'),
                    _TimeoutOption(1, '1 minute'),
                    _TimeoutOption(5, '5 minutes'),
                    _TimeoutOption(15, '15 minutes'),
                    _TimeoutOption(30, '30 minutes'),
                    _TimeoutOption(60, '1 hour'),
                  ],
                ),
              );
              if (newValue != null) {
                ref
                    .read(vaultControllerProvider.notifier)
                    .setInactivityTimeout(newValue);
              }
            },
          ),
          SettingsTile(
            icon: Icons.phonelink_lock_outlined,
            title: 'Background lock delay',
            subtitle:
                'Locks after Diogel is sent to the background: '
                '${formatBackgroundLockDelay(backgroundLockDelayMinutes)}',
            onTap: () async {
              final newValue = await showDialog<int>(
                context: context,
                builder: (context) => _TimeoutPickerDialog(
                  title: 'Background lock delay',
                  initialValue: backgroundLockDelayMinutes,
                  options: const [
                    _TimeoutOption(0, 'Immediately'),
                    _TimeoutOption(1, '1 minute'),
                    _TimeoutOption(5, '5 minutes'),
                    _TimeoutOption(15, '15 minutes'),
                    _TimeoutOption(30, '30 minutes'),
                    _TimeoutOption(60, '1 hour'),
                    _TimeoutOption(-1, 'Never while app is running'),
                  ],
                ),
              );
              if (newValue != null) {
                ref
                    .read(vaultControllerProvider.notifier)
                    .setBackgroundLockDelayMinutes(newValue);
              }
            },
          ),
          SettingsTile(
            icon: Icons.verified_user_outlined,
            title: 'Approval session duration',
            // Says what the code does (#5): remembered decisions for a specific
            // kind or action do not depend on an approval session, and a
            // request to sign any kind is never remembered.
            subtitle:
                'Not currently used: remembered decisions apply whenever the '
                'vault is unlocked. Set to: '
                '${formatApprovalSessionDuration(approvalSessionDurationMinutes)}',
            onTap: () async {
              final newValue = await showDialog<int>(
                context: context,
                builder: (context) => _TimeoutPickerDialog(
                  title: 'Approval session duration',
                  initialValue: approvalSessionDurationMinutes,
                  options: const [
                    _TimeoutOption(0, 'Ask every time'),
                    _TimeoutOption(1, '1 minute'),
                    _TimeoutOption(5, '5 minutes'),
                    _TimeoutOption(15, '15 minutes'),
                  ],
                ),
              );
              if (newValue != null) {
                ref
                    .read(vaultControllerProvider.notifier)
                    .setApprovalSessionDurationMinutes(newValue);
              }
            },
          ),
          SettingsTile(
            icon: Icons.verified_user_outlined,
            title: 'Trusted Nostr apps',
            subtitle:
                'Review remembered NIP-55 app permissions. They apply whenever the vault is unlocked.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TrustedAppsScreen()),
              );
            },
          ),
          SettingsTile(
            icon: Icons.lan_outlined,
            title: 'Remote Signer (NIP-46)',
            subtitle:
                'Manage relay-based remote signing sessions for Amethyst, Nostria, and other NIP-46 clients.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const Nip46ConnectionsScreen(),
                ),
              );
            },
          ),
          const SettingsTile(
            icon: Icons.info_outline,
            title: 'Session security',
            subtitle:
                'Shorter delays are safer; longer delays are more convenient. '
                'Never only lasts while the app process remains running.',
          ),
          SettingsTile(
            icon: Icons.lock_open,
            title: 'Lock Vault',
            subtitle: 'Secure your vault immediately',
            onTap: () {
              ref.read(vaultControllerProvider.notifier).lock();
            },
          ),
          const SizedBox(height: DiogelSpacing.space6),
          Text(
            'VAULT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: DiogelColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: DiogelSpacing.space2),
          const SettingsTile(
            icon: Icons.backup_outlined,
            title: 'Backup Vault',
            subtitle: 'Export your recovery data',
          ),
          const SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: 'Wipe Vault',
            subtitle: 'Permanently delete all keys',
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _TimeoutOption {
  final int value;
  final String label;

  const _TimeoutOption(this.value, this.label);
}

class _TimeoutPickerDialog extends StatelessWidget {
  final String title;
  final int initialValue;
  final List<_TimeoutOption> options;

  const _TimeoutPickerDialog({
    required this.title,
    required this.initialValue,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              _buildOption(context, option.value, option.label),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildOption(BuildContext context, int value, String label) {
    // RadioListTile currently reports deprecation for groupValue/onChanged in
    // some Flutter versions, but RadioGroup is not standard everywhere yet.
    // ignore: deprecated_member_use
    return RadioListTile<int>(
      title: Text(label),
      value: value,
      // ignore: deprecated_member_use
      groupValue: initialValue,
      // ignore: deprecated_member_use
      onChanged: (newValue) {
        if (newValue != null) {
          Navigator.of(context).pop(newValue);
        }
      },
      contentPadding: EdgeInsets.zero,
    );
  }
}
