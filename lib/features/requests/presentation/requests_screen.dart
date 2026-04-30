import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../vault/application/vault_providers.dart';
import '../application/request_providers.dart';
import '../domain/request_trust_status.dart';
import '../domain/signing_request.dart';
import 'widgets/request_detail_item.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  bool _showRawJson = false;

  @override
  Widget build(BuildContext context) {
    final pendingRequest = ref.watch(pendingRequestProvider);
    final requestState = ref.watch(requestControllerProvider);
    final isLoading = requestState.isLoading;
    final failure = requestState.failure;

    final vaultState = ref.watch(vaultControllerProvider);
    final activeIdentity = vaultState.activeIdentity;

    if (pendingRequest == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: DiogelColors.textTertiary,
              ),
              const SizedBox(height: DiogelSpacing.space4),
              Text(
                'No pending requests',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: DiogelColors.textSecondary,
                    ),
              ),
              const SizedBox(height: DiogelSpacing.space6),
              OutlinedButton.icon(
                onPressed: activeIdentity == null
                    ? null
                    : () => ref.read(requestControllerProvider.notifier).injectDemoRequest(),
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Load Demo Request (Dev)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DiogelColors.textTertiary,
                  side: const BorderSide(color: DiogelColors.borderSubtle),
                ),
              ),
              if (activeIdentity == null) ...[
                const SizedBox(height: DiogelSpacing.space2),
                const Text(
                  'Create an identity first',
                  style: TextStyle(
                    color: DiogelColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Signing Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DiogelSpacing.space4,
          DiogelSpacing.space4,
          DiogelSpacing.space4,
          140,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (failure != null) ...[
              _buildFailureMessage(context, failure.message),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            _buildProvenanceWarning(context, pendingRequest.provenance.trustStatus),
            const SizedBox(height: DiogelSpacing.space6),
            _buildSectionHeader(context, 'REQUEST SOURCE'),
            const SizedBox(height: DiogelSpacing.space2),
            RequestDetailItem(
              icon: Icons.apps,
              iconColor: DiogelColors.actionPrimary,
              title: pendingRequest.provenance.sourceDisplayName,
              subtitle: pendingRequest.provenance.sourceIdentifier ?? 'Unknown Source',
            ),
            const SizedBox(height: DiogelSpacing.space4),
            _buildSectionHeader(context, 'ACTION TYPE'),
            const SizedBox(height: DiogelSpacing.space2),
            RequestDetailItem(
              key: const ValueKey('action_type'),
              icon: Icons.edit_note,
              iconColor: DiogelColors.nostrAccentMuted,
              title: 'Sign Kind ${pendingRequest.eventKind} Event',
              subtitle: pendingRequest.actionType.name,
            ),
            const SizedBox(height: DiogelSpacing.space6),
            _buildSectionHeader(context, 'SIGNING WITH ACCOUNT'),
            const SizedBox(height: DiogelSpacing.space2),
            _buildIdentityCard(context, activeIdentity),
            const SizedBox(height: DiogelSpacing.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(context, 'EVENT DETAILS'),
                TextButton.icon(
                  onPressed: () => setState(() => _showRawJson = !_showRawJson),
                  icon: Text(
                    _showRawJson ? 'Hide Raw' : 'Raw JSON',
                    style: const TextStyle(
                      color: DiogelColors.actionPrimary,
                      fontSize: 12,
                    ),
                  ),
                  label: Icon(
                    _showRawJson ? Icons.expand_less : Icons.expand_more,
                    color: DiogelColors.actionPrimary,
                    size: 16,
                  ),
                ),
              ],
            ),
            if (_showRawJson) ...[
              _buildRawJsonDisclosure(pendingRequest),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            _buildEventSummary(context, pendingRequest),
          ],
        ),
      ),
      bottomSheet: _buildActionButtons(context, pendingRequest, isLoading),
    );
  }

  Widget _buildFailureMessage(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.stateError.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.stateError.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: DiogelColors.stateError),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DiogelColors.stateError,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: DiogelColors.stateError),
            onPressed: () => ref.read(requestControllerProvider.notifier).clearFailure(),
          ),
        ],
      ),
    );
  }

  Widget _buildProvenanceWarning(BuildContext context, RequestTrustStatus status) {
    final isUnknown = status == RequestTrustStatus.unknown;
    final isUntrusted = status == RequestTrustStatus.knownUntrusted || status == RequestTrustStatus.invalid;
    
    if (status == RequestTrustStatus.knownTrusted) return const SizedBox.shrink();

    final color = isUntrusted ? DiogelColors.stateError : DiogelColors.stateWarning;
    final title = isUntrusted ? 'Untrusted Source' : 'Unknown Provenance';
    final message = isUntrusted 
        ? 'This request comes from a known malicious or invalid source. DO NOT SIGN unless you are absolutely sure.'
        : 'The requesting application is not in your verified list. Exercise caution.';

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isUntrusted ? Icons.gpp_bad : Icons.warning, color: color),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
                ),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: DiogelColors.textTertiary,
            letterSpacing: 1.2,
          ),
    );
  }

  Widget _buildIdentityCard(BuildContext context, dynamic activeIdentity) {
    final displayName = activeIdentity?.displayName ?? 'Anonymous';
    final pubkey = activeIdentity?.publicKey ?? 'Unknown Public Key';
    final truncatedPubkey = pubkey.length > 16 
        ? '${pubkey.substring(0, 8)}...${pubkey.substring(pubkey.length - 8)}'
        : pubkey;

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainer,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DiogelColors.actionPrimary,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person,
              size: 24,
              color: DiogelColors.actionPrimary,
            ),
          ),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  truncatedPubkey,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DiogelColors.actionPrimary,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          ),
          if (activeIdentity != null)
            const Icon(
              Icons.verified,
              color: DiogelColors.stateSuccess,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildRawJsonDisclosure(SigningRequest request) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(request.eventPayload);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
      ),
      child: SelectableText(
        jsonString,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildEventSummary(BuildContext context, SigningRequest request) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONTENT',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DiogelSpacing.space3),
            decoration: BoxDecoration(
              color: DiogelColors.surfaceBase,
              borderRadius: BorderRadius.circular(DiogelRadius.small),
              border: Border.all(
                color: DiogelColors.borderSubtle.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              request.eventPayload['content']?.toString() ?? 'No content',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CREATED AT',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      request.eventPayload['created_at']?.toString() ?? 'N/A',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TAGS',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      request.eventPayload['tags']?.toString() ?? '[]',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, SigningRequest request, bool isLoading) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBackground.withValues(alpha: 0.8),
        border: const Border(
          top: BorderSide(color: DiogelColors.borderSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () => ref.read(requestControllerProvider.notifier).rejectRequest(request.id),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: DiogelSpacing.space4,
                    ),
                    side: const BorderSide(
                      color: DiogelColors.borderStrong,
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DiogelRadius.medium),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DiogelSpacing.space4),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : () => ref.read(requestControllerProvider.notifier).approveRequest(request.id),
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(isLoading ? 'Signing...' : 'Sign event'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: DiogelSpacing.space4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DiogelRadius.medium),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            'This action will generate a digital signature using your private key.',
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
