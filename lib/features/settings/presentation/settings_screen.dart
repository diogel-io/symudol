import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import 'widgets/settings_tile.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
