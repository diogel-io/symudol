import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../nip46/application/nip46_feature.dart';
import '../../nip46/presentation/nip46_connections_screen.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/biometric_unlock_status.dart';
import '../../vault/domain/biometric_vault.dart';
import '../../vault/presentation/vault_failure_messages.dart';
import 'change_pin_screen.dart';
import 'trusted_apps_screen.dart';
import 'widgets/biometric_pin_dialog.dart';
import 'widgets/settings_tile.dart';
import 'widgets/wipe_vault_dialog.dart';

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

String formatWipeAfterFailures(int? attempts) =>
    attempts == null ? 'Off' : 'After $attempts failed attempts';

/// Symudol's own notice on the open-source licences page (#113).
const symudolLicenceLegalese =
    '© 2026 Threenine Consulting Limited. Released under the MIT licence.';

/// The Biometric Unlock tile's subtitle (#23).
String biometricUnlockSubtitle(BiometricUnlockStatus status) {
  if (status.enabledButUnavailable) {
    return "On, but this phone can't use it right now; the PIN still works";
  }
  if (status.enabled ||
      status.availability == BiometricAvailability.available) {
    return 'Unlock with your fingerprint or face; the PIN is still needed '
        'after a restart or every 72 hours';
  }
  return switch (status.availability) {
    BiometricAvailability.noneEnrolled =>
      'Add a fingerprint or face in Android settings first',
    BiometricAvailability.noHardware =>
      'This phone has no strong biometric sensor',
    _ => 'Not available on this phone',
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
    final wipeAfterFailures = vaultControllerState.wipeAfterFailures;
    final biometricUnlock = vaultControllerState.biometricUnlock;

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
          SettingsTile(
            key: const Key('changePinTile'),
            icon: Icons.lock_outline,
            title: 'Change PIN',
            subtitle: 'Update your security access code',
            onTap: () => _changePin(context),
          ),
          SettingsTile(
            key: const Key('biometricUnlockTile'),
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: biometricUnlockSubtitle(biometricUnlock),
            trailing: Switch(
              key: const Key('biometricUnlockSwitch'),
              value: biometricUnlock.enabled,
              onChanged: biometricUnlock.enabled ||
                      biometricUnlock.availability ==
                          BiometricAvailability.available
                  ? (on) => _setBiometricUnlock(context, ref, on)
                  : null,
            ),
            onTap: () => _toggleBiometricUnlock(context, ref),
          ),
          SettingsTile(
            key: const Key('wipeAfterFailuresTile'),
            icon: Icons.phonelink_erase_outlined,
            title: 'Erase after failed PIN attempts',
            subtitle: formatWipeAfterFailures(wipeAfterFailures),
            onTap: () => _pickWipeAfterFailures(context, ref, wipeAfterFailures),
          ),
          SettingsTile(
            icon: Icons.timer_outlined,
            title: 'In-app inactivity timeout',
            subtitle:
                'Locks when you stop using Symudol while it is open: '
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
                'Locks after Symudol is sent to the background: '
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
          // Hidden in release builds for Android 1.0 (#26).
          if (ref.watch(nip46EnabledProvider))
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
            key: const Key('openSourceLicencesTile'),
            icon: Icons.description_outlined,
            title: 'Open-source licences',
            subtitle: 'Licences for Symudol and the packages it uses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Symudol',
              applicationLegalese: symudolLicenceLegalese,
            ),
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
          SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: 'Wipe Vault',
            subtitle: 'Permanently delete all keys',
            isDestructive: true,
            onTap: () => confirmAndWipeVault(context, ref),
          ),
        ],
      ),
    );
  }

  /// Off, 10, 15 or 20 failed PIN attempts (#16). Turning it on, or changing
  /// the count, asks first.
  Future<void> _pickWipeAfterFailures(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    // The picker works in ints; 0 stands for Off.
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _TimeoutPickerDialog(
        title: 'Erase after failed PIN attempts',
        initialValue: current ?? 0,
        options: const [
          _TimeoutOption(0, 'Off'),
          _TimeoutOption(10, '10 failed attempts'),
          _TimeoutOption(15, '15 failed attempts'),
          _TimeoutOption(20, '20 failed attempts'),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final attempts = picked == 0 ? null : picked;
    if (attempts == current) return;

    if (attempts != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Erase after $attempts failed attempts?'),
          content: Text(
            'If the wrong PIN is entered $attempts times in a row, Symudol '
            'permanently erases every identity and key on this phone, with '
            'every Trusted app permission and NIP-46 connection. It cannot be '
            'undone, so keep a backup of your keys elsewhere.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DiogelColors.stateError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await ref
        .read(vaultControllerProvider.notifier)
        .setWipeAfterFailures(attempts);
  }

  /// The tile itself: re-reads the sensor first, since a fingerprint may
  /// have been added in Android settings since this screen opened (#23).
  Future<void> _toggleBiometricUnlock(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifier = ref.read(vaultControllerProvider.notifier);
    await notifier.refreshBiometricUnlock();
    if (!context.mounted) return;
    final status = ref.read(vaultControllerProvider).biometricUnlock;
    if (status.enabled ||
        status.availability == BiometricAvailability.available) {
      await _setBiometricUnlock(context, ref, !status.enabled);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(biometricUnlockSubtitle(status))),
      );
    }
  }

  Future<void> _setBiometricUnlock(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final notifier = ref.read(vaultControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      await notifier.disableBiometricUnlock();
      messenger.showSnackBar(
        const SnackBar(content: Text('Biometric unlock is off')),
      );
      return;
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const BiometricPinDialog(),
    );
    if (pin == null) return;
    final failure = await notifier.enableBiometricUnlock(pin);
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(vaultFailureMessage(failure))),
      );
    } else if (ref.read(vaultControllerProvider).biometricUnlock.enabled) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Biometric unlock is on')),
      );
    }
  }

  Future<void> _changePin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePinScreen()),
    );
    if (changed == true) {
      messenger.showSnackBar(const SnackBar(content: Text('PIN changed')));
    }
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
