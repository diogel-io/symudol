import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_pop.dart';
import '../../../theme/tokens.dart';
import '../../identity/domain/vault_identity.dart';
import '../application/profile_providers.dart';
import '../application/relay_list_editor.dart';
import '../domain/profile_relays.dart';
import '../domain/relay_list.dart';
import 'publish_results_sheet.dart';

/// NIP-65 suggests keeping each kind of relay to 2 to 4.
const int _suggestedPerKind = 4;

/// Edits and publishes the active identity's relay list, NIP-65 kind 10002
/// (diogel-io/symudol#88). Opening it asks before reaching any relay
/// (diogel-io/symudol#83).
class RelayListScreen extends ConsumerStatefulWidget {
  const RelayListScreen({super.key, required this.identity});

  final VaultIdentity identity;

  @override
  ConsumerState<RelayListScreen> createState() => _RelayListScreenState();
}

class _RelayListScreenState extends ConsumerState<RelayListScreen> {
  final _input = TextEditingController();

  String get _pubkey => widget.identity.publicKey;

  RelayListEditorNotifier get _editor =>
      ref.read(relayListEditorProvider(_pubkey).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askThenLoad());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _askThenLoad() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const LoadRelayListDialog(),
    );
    if (!mounted) return;
    if (confirmed != true) {
      // A lock closes the dialog and this screen together (#123).
      popIfCurrent(context);
      return;
    }
    await _editor.load();
  }

  void _add() {
    if (_editor.add(_input.text)) _input.clear();
  }

  Future<void> _save() async {
    try {
      // Read the newest list first, so the dialog names the relays this save
      // will publish to, and the save uses that same reading.
      final prepared = await _editor.prepareSave();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _PublishDialog(
          identityName: widget.identity.displayName ?? 'this identity',
          relays: prepared.publishRelays,
        ),
      );
      if (confirmed != true || !mounted) return;

      final results = await _editor.save(prepared: prepared);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) =>
            PublishResultsSheet(title: 'Relays published', results: results),
      );
    } on RelayListSaveException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: DiogelColors.stateError,
        ),
      );
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Your changes to these relays have not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(relayListEditorProvider(_pubkey));
    final editing = editor.phase == RelayListEditorPhase.editing;

    return PopScope(
      canPop: !(editing && editor.dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Relays'),
          actions: [
            if (editing)
              TextButton(
                onPressed: editor.saving ? null : _save,
                child: const Text('Save'),
              ),
          ],
        ),
        body: switch (editor.phase) {
          // Nothing is loading while the user decides whether to load.
          RelayListEditorPhase.notLoaded => const SizedBox.shrink(),
          RelayListEditorPhase.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          RelayListEditorPhase.loadFailed => _LoadFailed(onRetry: _editor.load),
          RelayListEditorPhase.noList => _NoList(
            searchedRelays: editor.searchedRelays,
            onCreate: _editor.confirmCreate,
          ),
          RelayListEditorPhase.editing => _buildList(editor),
        },
      ),
    );
  }

  Widget _buildList(RelayListEditorState editor) {
    final reads = editor.relays.where((entry) => entry.read).length;
    final writes = editor.relays.where((entry) => entry.write).length;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(DiogelSpacing.space4),
          children: [
            const Text(
              'Other apps read your posts from your write relays, and look '
              'for replies and mentions on your read relays.',
            ),
            const SizedBox(height: DiogelSpacing.space4),
            if (editor.relays.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: DiogelSpacing.space4),
                child: Text('No relays yet. Add one below.'),
              ),
            for (final entry in editor.relays)
              _RelayRow(
                key: ValueKey(entry.url),
                entry: entry,
                enabled: !editor.saving,
                onRead: (value) => _editor.setMarkers(entry.url, read: value),
                onWrite: (value) => _editor.setMarkers(entry.url, write: value),
                onRemove: () => _editor.remove(entry.url),
              ),
            if (reads > _suggestedPerKind || writes > _suggestedPerKind) ...[
              const SizedBox(height: DiogelSpacing.space3),
              const _Note(
                'NIP-65 suggests 2 to 4 read relays and 2 to 4 write relays. '
                'A longer list makes other apps slower to find your posts.',
              ),
            ],
            if (writes > maxOwnRelays) ...[
              const SizedBox(height: DiogelSpacing.space3),
              const _Note(
                'Symudol looks up your profile on your first $maxOwnRelays '
                'write relays only.',
              ),
            ],
            const SizedBox(height: DiogelSpacing.space6),
            TextField(
              key: const Key('relayListAddField'),
              controller: _input,
              enabled: !editor.saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                labelText: 'Add a relay',
                hintText: 'wss://relay.example.com',
                errorText: editor.inputError,
                suffixIcon: IconButton(
                  tooltip: 'Add relay',
                  icon: const Icon(Icons.add),
                  onPressed: editor.saving ? null : _add,
                ),
              ),
            ),
          ],
        ),
        if (editor.saving)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onRead,
    required this.onWrite,
    required this.onRemove,
  });

  final RelayListEntry entry;
  final bool enabled;
  final ValueChanged<bool> onRead;
  final ValueChanged<bool> onWrite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final host = relayHost(entry.url);
    return Card(
      margin: const EdgeInsets.only(bottom: DiogelSpacing.space2),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DiogelSpacing.space3,
          vertical: DiogelSpacing.space2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(host, style: Theme.of(context).textTheme.titleSmall),
                  Wrap(
                    spacing: DiogelSpacing.space2,
                    children: [
                      FilterChip(
                        label: const Text('Read'),
                        selected: entry.read,
                        // Only one of read and write can be turned off.
                        onSelected: enabled && (!entry.read || entry.write)
                            ? onRead
                            : null,
                      ),
                      FilterChip(
                        label: const Text('Write'),
                        selected: entry.write,
                        onSelected: enabled && (!entry.write || entry.read)
                            ? onWrite
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove $host',
              icon: const Icon(Icons.delete_outline),
              onPressed: enabled ? onRemove : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline,
          size: 20,
          color: DiogelColors.textTertiary,
        ),
        const SizedBox(width: DiogelSpacing.space2),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: DiogelColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Names the relays a relay list lookup will query and what they learn: the
/// profile and indexer relays chosen in Settings (diogel-io/symudol#45, #83).
class LoadRelayListDialog extends ConsumerWidget {
  const LoadRelayListDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(profileNetworkSettingsProvider).value;
    final relays = settings == null
        ? null
        : profileRelays(
            const [],
            settings.profileRelays,
            settings.indexerRelays,
          ).map(relayHost).join(', ');
    return AlertDialog(
      title: const Text('Load relays from the network?'),
      content: Text(
        relays == null
            ? 'Reading your relay settings…'
            : 'Symudol will ask $relays for this identity\'s relay list. '
                  'They will see this public key and your IP address.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: relays == null
              ? null
              : () => Navigator.of(context).pop(true),
          child: const Text('Load relays'),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DiogelSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't reach the relays, so the relay list can't be edited "
              'now.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DiogelSpacing.space4),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// No relay holds a relay list: list the relays that answered, and ask
/// before creating one, which could replace a list held elsewhere.
class _NoList extends StatelessWidget {
  const _NoList({required this.searchedRelays, required this.onCreate});

  final List<String> searchedRelays;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DiogelSpacing.space6),
      children: [
        Text(
          'No relay list found',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: DiogelSpacing.space3),
        const Text(
          'None of these relays holds a relay list for this identity:',
        ),
        const SizedBox(height: DiogelSpacing.space2),
        for (final relay in searchedRelays) Text(relayHost(relay)),
        const SizedBox(height: DiogelSpacing.space4),
        const Text(
          'If this identity has a relay list on other relays, creating a new '
          'one here may replace it in apps that read these relays.',
        ),
        const SizedBox(height: DiogelSpacing.space6),
        FilledButton(
          onPressed: onCreate,
          child: const Text('Create a relay list'),
        ),
      ],
    );
  }
}

class _PublishDialog extends StatelessWidget {
  const _PublishDialog({required this.identityName, required this.relays});

  final String identityName;
  final List<String> relays;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign and publish?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Symudol will sign this relay list with $identityName and '
              'publish it to ${relays.length} relays:',
            ),
            const SizedBox(height: DiogelSpacing.space2),
            for (final relay in relays) Text(relayHost(relay)),
            const SizedBox(height: DiogelSpacing.space3),
            const Text('Anyone can read a published relay list.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign and publish'),
        ),
      ],
    );
  }
}
