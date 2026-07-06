import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/nip46_providers.dart';
import '../domain/nip46_connection_token.dart';

class Nip46ConnectionQrSheet extends ConsumerStatefulWidget {
  const Nip46ConnectionQrSheet({super.key});

  @override
  ConsumerState<Nip46ConnectionQrSheet> createState() =>
      _Nip46ConnectionQrSheetState();
}

class _Nip46ConnectionQrSheetState
    extends ConsumerState<Nip46ConnectionQrSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Nip46BunkerToken? _generatedToken;
  bool _isGenerating = false;
  String? _generateError;

  final _importController = TextEditingController();
  bool _isImporting = false;
  String? _importError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'New NIP-46 Connection',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Generate bunker://'),
              Tab(text: 'Import nostrconnect://'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _GenerateTab(
                  token: _generatedToken,
                  isGenerating: _isGenerating,
                  error: _generateError,
                  onGenerate: _onGenerate,
                ),
                _ImportTab(
                  controller: _importController,
                  isImporting: _isImporting,
                  error: _importError,
                  onImport: _onImport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onGenerate() async {
    setState(() {
      _isGenerating = true;
      _generateError = null;
    });
    try {
      final token = await ref
          .read(nip46ControllerProvider.notifier)
          .initiateBunkerSession();
      setState(() {
        _generatedToken = token;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _generateError = e.toString();
        _isGenerating = false;
      });
    }
  }

  Future<void> _onImport() async {
    final uri = _importController.text.trim();
    if (uri.isEmpty) {
      setState(() => _importError = 'Paste a nostrconnect:// URI first');
      return;
    }
    if (!uri.startsWith('nostrconnect://')) {
      setState(() => _importError = 'URI must start with nostrconnect://');
      return;
    }
    setState(() {
      _isImporting = true;
      _importError = null;
    });
    try {
      await ref
          .read(nip46ControllerProvider.notifier)
          .importNostrconnectToken(uri);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _importError = e.toString();
        _isImporting = false;
      });
    }
  }
}

class _GenerateTab extends StatelessWidget {
  final Nip46BunkerToken? token;
  final bool isGenerating;
  final String? error;
  final VoidCallback onGenerate;

  const _GenerateTab({
    required this.token,
    required this.isGenerating,
    required this.error,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Generate a bunker:// token and share it with a NIP-46 compatible '
            'client (e.g. Amethyst, Nostria). The client will initiate the connection.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (token == null) ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: isGenerating ? null : onGenerate,
              child: isGenerating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate bunker:// token'),
            ),
          ] else ...[
            Text(
              'Share this token with your NIP-46 client:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _TokenDisplay(uri: token!.toUri()),
            const SizedBox(height: 16),
            Text(
              'Waiting for client to connect…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportTab extends StatelessWidget {
  final TextEditingController controller;
  final bool isImporting;
  final String? error;
  final VoidCallback onImport;

  const _ImportTab({
    required this.controller,
    required this.isImporting,
    required this.error,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste a nostrconnect:// URI from a client app (e.g. a QR code '
            'scanned externally or copied from the client).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'nostrconnect:// URI',
              hintText: 'nostrconnect://…',
              border: const OutlineInputBorder(),
              errorText: error,
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Paste',
                onPressed: () async {
                  final data =
                      await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    controller.text = data!.text!;
                  }
                },
              ),
            ),
            maxLines: 3,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isImporting ? null : onImport,
            child: isImporting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Import and connect'),
          ),
        ],
      ),
    );
  }
}

class _TokenDisplay extends StatelessWidget {
  final String uri;
  const _TokenDisplay({required this.uri});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            uri,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uri));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('bunker:// token copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
