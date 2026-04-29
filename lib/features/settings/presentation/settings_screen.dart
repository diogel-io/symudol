import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../vault/application/vault_providers.dart';
import 'widgets/settings_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultControllerState = ref.watch(vaultControllerProvider);
    final timeoutMinutes = vaultControllerState.inactivityTimeoutMinutes;

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
            subtitle: 'Use fingerprint for faster access',
            trailing: Switch(value: true, onChanged: (value) {}),
          ),
          SettingsTile(
            icon: Icons.timer_outlined,
            title: 'Inactivity Timeout',
            subtitle: timeoutMinutes == 0 ? 'Never' : '$timeoutMinutes minutes',
            onTap: () async {
              final newValue = await showDialog<int>(
                context: context,
                builder: (context) => _TimeoutPickerDialog(initialValue: timeoutMinutes),
              );
              if (newValue != null) {
                ref.read(vaultControllerProvider.notifier).setInactivityTimeout(newValue);
              }
            },
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

class _TimeoutPickerDialog extends StatelessWidget {
  final int initialValue;

  const _TimeoutPickerDialog({required this.initialValue});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inactivity Timeout'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildOption(context, 0, 'Never'),
            _buildOption(context, 1, '1 minute'),
            _buildOption(context, 5, '5 minutes'),
            _buildOption(context, 15, '15 minutes'),
            _buildOption(context, 30, '30 minutes'),
            _buildOption(context, 60, '1 hour'),
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
    // RadioListTile currently reports deprecation for groupValue/onChanged in some Flutter versions 
    // but the suggested RadioGroup alternative is not yet standard in many projects.
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
