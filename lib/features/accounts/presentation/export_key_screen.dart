import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/sensitive_clipboard.dart';
import '../../../theme/tokens.dart';
import '../../identity/domain/vault_identity.dart';
import '../../settings/presentation/widgets/confirm_pin_dialog.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/presentation/vault_failure_messages.dart';

/// How long a copied key stays on the clipboard (diogel-io/symudol#24).
const exportedKeyClipboardLifetime = Duration(seconds: 60);

/// Shows one identity's private key as an `nsec`, so the user can keep a
/// copy outside Symudol (diogel-io/symudol#24).
///
/// The warning comes first, then the PIN, then the key, hidden until asked.
/// Screenshots and screen recording are already blocked on every screen
/// (`FLAG_SECURE` in `MainActivity`, #15). Locking the vault pops this route
/// (#123), which drops the key.
class ExportKeyScreen extends ConsumerStatefulWidget {
  const ExportKeyScreen({super.key, required this.identity});

  final VaultIdentity identity;

  @override
  ConsumerState<ExportKeyScreen> createState() => _ExportKeyScreenState();
}

class _ExportKeyScreenState extends ConsumerState<ExportKeyScreen> {
  /// The key, held only here and only once the PIN was right.
  String? _nsec;
  bool _visible = false;
  bool _working = false;

  @override
  void dispose() {
    _nsec = null;
    super.dispose();
  }

  Future<void> _continue() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const ConfirmPinDialog(
        title: 'Export private key',
        message: 'Enter your PIN to show this private key.',
        fieldKey: Key('exportKeyPinField'),
      ),
    );
    if (pin == null || !mounted) return;

    setState(() => _working = true);
    final (nsec, failure) = await ref
        .read(vaultControllerProvider.notifier)
        .exportPrivateKey(pin: pin, identityLocalId: widget.identity.localId);
    if (!mounted) return;
    setState(() {
      _working = false;
      _nsec = nsec;
    });
    if (nsec == null) {
      _showMessage(
        failure == null
            ? "Couldn't read the private key. Try again."
            : vaultFailureMessage(failure),
      );
    }
  }

  Future<void> _copy() async {
    final nsec = _nsec;
    if (nsec == null) return;
    try {
      await copySensitiveText(
        nsec,
        label: 'Nostr private key',
        clearAfter: exportedKeyClipboardLifetime,
      );
    } on PlatformException {
      if (mounted) _showMessage("Couldn't copy the key.");
      return;
    }
    if (!mounted) return;
    _showMessage(
      'Private key copied. The clipboard clears in '
      '${exportedKeyClipboardLifetime.inSeconds} seconds.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = widget.identity.displayName;
    final nsec = _nsec;
    return Scaffold(
      appBar: AppBar(title: const Text('Export private key')),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          if (name != null && name.isNotEmpty) ...[
            Text(name, style: textTheme.titleMedium),
            const SizedBox(height: DiogelSpacing.space3),
          ],
          Container(
            key: const Key('exportKeyWarning'),
            padding: const EdgeInsets.all(DiogelSpacing.space4),
            decoration: BoxDecoration(
              color: DiogelColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              border: Border.all(color: DiogelColors.stateWarning),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: DiogelColors.stateWarning,
                ),
                SizedBox(width: DiogelSpacing.space3),
                Expanded(
                  child: Text(
                    'Anyone with this private key controls this identity, and '
                    "it can't be changed or revoked. Never paste it into a "
                    "website or app you don't trust. For a copy you can keep "
                    'safely, use Settings → Backup Vault, which encrypts it '
                    'with a passphrase.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DiogelSpacing.space6),
          if (nsec == null)
            FilledButton.icon(
              key: const Key('exportKeyContinue'),
              onPressed: _working ? null : _continue,
              icon: _working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key_outlined),
              label: const Text('I understand, continue'),
            )
          else ...[
            Text('Private key (nsec)', style: textTheme.titleSmall),
            const SizedBox(height: DiogelSpacing.space2),
            Container(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.surfaceBase,
                borderRadius: BorderRadius.circular(DiogelRadius.large),
                border: Border.all(color: DiogelColors.borderSubtle),
              ),
              // Plain Text isn't selectable, so the key can only leave
              // through the marked, timed copy below (#96).
              child: Text(
                _visible ? nsec : '•' * 24,
                key: const Key('exportKeyValue'),
                style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: DiogelSpacing.space3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('exportKeyToggle'),
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible ? Icons.visibility_off : Icons.visibility,
                    ),
                    label: Text(_visible ? 'Hide' : 'Show'),
                  ),
                ),
                const SizedBox(width: DiogelSpacing.space3),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('exportKeyCopy'),
                    onPressed: _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              'A copied key is cleared from the clipboard after '
              '${exportedKeyClipboardLifetime.inSeconds} seconds.',
              style: textTheme.bodySmall?.copyWith(
                color: DiogelColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
