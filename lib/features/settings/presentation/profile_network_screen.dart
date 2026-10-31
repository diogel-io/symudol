import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../profile/application/profile_providers.dart';
import '../../profile/domain/profile_network_settings.dart';
import '../../profile/domain/profile_relays.dart';

/// Which of the two relay lists an action applies to.
enum _RelayList { profile, indexer }

/// Lets the user choose the relays profiles are read from and published to,
/// the indexer relays, and the Blossom server (diogel-io/symudol#45). Nothing
/// is saved until Save.
class ProfileNetworkScreen extends ConsumerStatefulWidget {
  const ProfileNetworkScreen({super.key});

  @override
  ConsumerState<ProfileNetworkScreen> createState() =>
      _ProfileNetworkScreenState();
}

class _ProfileNetworkScreenState extends ConsumerState<ProfileNetworkScreen> {
  final _profileAdd = TextEditingController();
  final _indexerAdd = TextEditingController();
  final _blossom = TextEditingController();

  ProfileNetworkSettings? _saved;
  ProfileNetworkSettings? _form;
  String? _profileError;
  String? _indexerError;
  String? _blossomError;
  bool _saving = false;

  @override
  void dispose() {
    _profileAdd.dispose();
    _indexerAdd.dispose();
    _blossom.dispose();
    super.dispose();
  }

  /// The form with the Blossom field as typed, normalised when it is valid.
  ProfileNetworkSettings get _edited => _form!.copyWith(
    blossomServer: normaliseBlossomUrl(_blossom.text) ?? _blossom.text.trim(),
  );

  bool get _dirty => _form != null && _edited != _saved;

  void _fill(ProfileNetworkSettings settings) {
    _form = settings;
    _blossom.text = settings.blossomServer;
  }

  void _add(_RelayList list) {
    final field = list == _RelayList.profile ? _profileAdd : _indexerAdd;
    final current = list == _RelayList.profile
        ? _form!.profileRelays
        : _form!.indexerRelays;
    final url = normaliseRelayUrl(field.text);
    final String? error;
    if (url == null) {
      error = 'Enter a relay address starting with ws:// or wss://';
    } else if (current.contains(url)) {
      error = 'That relay is already in the list';
    } else if (current.length >= maxOwnRelays) {
      error = 'A list holds at most $maxOwnRelays relays';
    } else {
      error = null;
    }
    setState(() {
      if (list == _RelayList.profile) {
        _profileError = error;
      } else {
        _indexerError = error;
      }
      if (error != null) return;
      final next = [...current, url!];
      _form = list == _RelayList.profile
          ? _form!.copyWith(profileRelays: next)
          : _form!.copyWith(indexerRelays: next);
      field.clear();
    });
  }

  void _remove(_RelayList list, String url) {
    setState(() {
      _form = list == _RelayList.profile
          ? _form!.copyWith(
              profileRelays: [..._form!.profileRelays]..remove(url),
            )
          : _form!.copyWith(
              indexerRelays: [..._form!.indexerRelays]..remove(url),
            );
    });
  }

  void _reset() {
    setState(() {
      _fill(ProfileNetworkSettings.defaults());
      _profileError = null;
      _indexerError = null;
      _blossomError = null;
    });
  }

  Future<void> _save() async {
    final blossom = normaliseBlossomUrl(_blossom.text);
    if (blossom == null) {
      setState(
        () => _blossomError = 'Enter a server address starting with https://',
      );
      return;
    }
    final settings = _form!.copyWith(blossomServer: blossom);
    setState(() {
      _blossomError = null;
      _saving = true;
    });
    try {
      await ref.read(profileNetworkSettingsProvider.notifier).save(settings);
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _blossom.text = blossom;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Relay settings saved'),
          backgroundColor: DiogelColors.stateSuccess,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save the relay settings"),
          backgroundColor: DiogelColors.stateError,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your relay changes have not been saved.'),
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
    final loaded = ref.watch(profileNetworkSettingsProvider).value;
    if (_form == null && loaded != null) {
      _saved = loaded;
      _fill(loaded);
    }
    final form = _form;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Relays and media server'),
          actions: [
            if (form != null)
              TextButton(
                onPressed: _saving || !_dirty ? null : _save,
                child: const Text('Save'),
              ),
          ],
        ),
        body: form == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(DiogelSpacing.space4),
                children: [
                  Text(
                    'Symudol asks these relays for an identity\'s profile '
                    'when you load or edit it, together with the relays the '
                    'identity lists as its own. They see the public key and '
                    'your IP address.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _RelaySection(
                    title: 'PROFILE RELAYS',
                    description:
                        'Profiles are read from and published to these. '
                        'At least one is needed.',
                    relays: form.profileRelays,
                    canRemove: form.profileRelays.length > 1,
                    onRemove: (url) => _remove(_RelayList.profile, url),
                    field: _profileAdd,
                    fieldKey: const Key('addProfileRelayField'),
                    error: _profileError,
                    onAdd: () => _add(_RelayList.profile),
                  ),
                  _RelaySection(
                    title: 'INDEXER RELAYS',
                    description:
                        'These collect profiles and relay lists from across '
                        'the network. They are asked, never published to.',
                    relays: form.indexerRelays,
                    canRemove: true,
                    onRemove: (url) => _remove(_RelayList.indexer, url),
                    field: _indexerAdd,
                    fieldKey: const Key('addIndexerRelayField'),
                    error: _indexerError,
                    onAdd: () => _add(_RelayList.indexer),
                  ),
                  const SizedBox(height: DiogelSpacing.space6),
                  const _SectionTitle('MEDIA SERVER'),
                  const SizedBox(height: DiogelSpacing.space2),
                  TextField(
                    key: const Key('blossomServerField'),
                    controller: _blossom,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => setState(() => _blossomError = null),
                    decoration: InputDecoration(
                      labelText: 'Blossom server',
                      helperText:
                          'Where Edit profile uploads pictures and banners '
                          'when an identity lists no Blossom server of its '
                          'own.',
                      helperMaxLines: 3,
                      errorText: _blossomError,
                    ),
                  ),
                  const SizedBox(height: DiogelSpacing.space6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _saving ? null : _reset,
                      child: const Text('Reset to defaults'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: DiogelColors.textTertiary,
      letterSpacing: 1.2,
    ),
  );
}

/// One relay list: its relays, each removable, and a field to add another.
class _RelaySection extends StatelessWidget {
  const _RelaySection({
    required this.title,
    required this.description,
    required this.relays,
    required this.canRemove,
    required this.onRemove,
    required this.field,
    required this.fieldKey,
    required this.error,
    required this.onAdd,
  });

  final String title;
  final String description;
  final List<String> relays;
  final bool canRemove;
  final ValueChanged<String> onRemove;
  final TextEditingController field;
  final Key fieldKey;
  final String? error;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: DiogelSpacing.space6),
        _SectionTitle(title),
        const SizedBox(height: DiogelSpacing.space1),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
        if (relays.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DiogelSpacing.space3),
            child: Text(
              'None',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DiogelColors.textTertiary,
              ),
            ),
          ),
        for (final url in relays)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(relayHost(url)),
            trailing: IconButton(
              tooltip: canRemove
                  ? 'Remove ${relayHost(url)}'
                  : 'At least one profile relay is needed',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: canRemove ? () => onRemove(url) : null,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: field,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => onAdd(),
                decoration: InputDecoration(
                  hintText: 'wss://relay.example.com',
                  errorText: error,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Add relay',
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}
