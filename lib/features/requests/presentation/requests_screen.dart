import 'dart:convert';
import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../accounts/presentation/widgets/profile_avatar.dart';
import '../../vault/application/vault_providers.dart';
import '../../identity/domain/vault_identity.dart';
import '../../nip55/application/nip55_providers.dart';
import '../../nip55/domain/nip55_permission_parser.dart';
import '../../nip55/domain/nip55_permission_scope.dart';
import '../application/request_providers.dart';
import '../domain/nostr_event_payload_parser.dart';
import '../domain/request_trust_status.dart';
import '../domain/signing_request.dart';
import '../domain/signing_request_status.dart';
import 'widgets/request_detail_item.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  bool _showDetails = false;
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final activeRequest = ref.watch(activeRequestProvider);
    final requestState = ref.watch(requestControllerProvider);
    final isLoading = requestState.isLoading;
    final failure = requestState.failure;
    final signedEvent = activeRequest == null
        ? null
        : requestState.signedEvents[activeRequest.id];

    final vaultState = ref.watch(vaultControllerProvider);
    final activeIdentity = vaultState.activeIdentity;
    final nip55State = ref.watch(nip55ControllerProvider);
    final eventReview = activeRequest == null
        ? null
        : const NostrEventPayloadParser().review(activeRequest.eventPayload);

    if (activeRequest == null) {
      if (nip55State.pendingPublicKeyRequest != null) {
        return _buildPublicKeyRequestScaffold(context, activeIdentity);
      }

      if (nip55State.pendingCryptoRequest != null) {
        return _buildCryptoRequestScaffold(context, activeIdentity);
      }

      if (nip55State.isLoading) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      return Scaffold(
        key: const ValueKey('nip55-empty'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (nip55State.lastSuccessMessage != null) ...[
                _buildSuccessMessage(context, nip55State.lastSuccessMessage!),
                const SizedBox(height: DiogelSpacing.space6),
              ],
              if (nip55State.failure != null) ...[
                _buildFailureMessage(
                  context,
                  nip55State.failure!.message,
                  onDismiss: () => ref
                      .read(nip55ControllerProvider.notifier)
                      .clearMessages(),
                ),
                const SizedBox(height: DiogelSpacing.space6),
              ],
              const Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: DiogelColors.textTertiary,
              ),
              const SizedBox(height: DiogelSpacing.space4),
              Text(
                'No active requests',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: DiogelColors.textSecondary,
                ),
              ),
              if (activeIdentity == null) ...[
                const SizedBox(height: DiogelSpacing.space6),
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
      appBar: AppBar(
        title: const Text('Signing Request'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: DiogelSpacing.space4),
            child: ProfileAvatar(),
          ),
        ],
      ),
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
            if (signedEvent != null) ...[
              _buildSignedMessage(context, signedEvent.id, signedEvent.sig),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            _buildProvenanceWarning(
              context,
              activeRequest.provenance.trustStatus,
            ),
            const SizedBox(height: DiogelSpacing.space6),
            _buildRequestSummaryCard(
              context,
              icon: Icons.apps,
              iconColor: DiogelColors.actionPrimary,
              packageName: activeRequest.provenance.sourceIdentifier,
              sourceName: activeRequest.provenance.sourceDisplayName,
              sourceVerified:
                  activeRequest.provenance.trustStatus ==
                  RequestTrustStatus.knownTrusted,
              actionDescription: _signingActionDescription(
                activeRequest,
                eventReview,
              ),
              activeIdentity: activeIdentity,
            ),
            if (eventReview != null &&
                (eventReview.isUnknownKind || eventReview.isSensitive)) ...[
              const SizedBox(height: DiogelSpacing.space4),
              _buildRiskNote(context, eventReview),
            ],
            const SizedBox(height: DiogelSpacing.space6),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                  color: DiogelColors.actionPrimary,
                  size: 16,
                ),
                label: Text(
                  _showDetails ? 'Hide details' : 'Show details',
                  style: const TextStyle(
                    color: DiogelColors.actionPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: DiogelSpacing.space2),
              if (eventReview != null)
                _buildEventSummary(context, activeRequest, eventReview),
              const SizedBox(height: DiogelSpacing.space4),
              _buildRawJsonDisclosure(activeRequest),
            ],
          ],
        ),
      ),
      bottomSheet: signedEvent == null
          ? activeRequest.status == SigningRequestStatus.failed
                ? _buildDismissFailedButton(context, activeRequest)
                : _buildActionButtons(context, activeRequest, isLoading)
          : null,
    );
  }

  Widget _buildPublicKeyRequestScaffold(
    BuildContext context,
    VaultIdentity? activeIdentity,
  ) {
    final nip55Request = ref
        .watch(nip55ControllerProvider)
        .pendingPublicKeyRequest!;
    final canRemember = ref
        .read(nip55ControllerProvider.notifier)
        .canRememberPendingPublicKeyRequest();
    final clientIdentity = nip55Request.clientIdentity;
    final parsedPermissions = const Nip55PermissionParser().parse(
      nip55Request.permissions,
    );
    final pubkey = activeIdentity?.publicKey;
    final truncatedNpub = pubkey == null
        ? 'No active identity'
        : _shortFingerprint(_npubFor(pubkey));

    final isLoading = ref.watch(nip55ControllerProvider).isLoading;

    return Scaffold(
      key: ValueKey('nip55-public-key-${nip55Request.requestToken}'),
      appBar: AppBar(
        title: const Text('Sign-in Request'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: DiogelSpacing.space4),
            child: ProfileAvatar(),
          ),
        ],
      ),
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
            _buildProvenanceWarning(
              context,
              clientIdentity.provenanceVerified
                  ? RequestTrustStatus.knownTrusted
                  : RequestTrustStatus.unknown,
            ),
            const SizedBox(height: DiogelSpacing.space6),
            _buildRequestSummaryCard(
              context,
              icon: Icons.key,
              iconColor: DiogelColors.actionPrimary,
              packageName: clientIdentity.packageName,
              sourceName: clientIdentity.displayName,
              sourceVerified: clientIdentity.provenanceVerified,
              actionDescription: _publicKeyActionDescription(
                parsedPermissions,
              ),
              activeIdentity: activeIdentity,
            ),
            if (parsedPermissions.warnings.isNotEmpty) ...[
              const SizedBox(height: DiogelSpacing.space4),
              _buildPermissionWarnings(context, parsedPermissions.warnings),
            ],
            const SizedBox(height: DiogelSpacing.space6),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                  color: DiogelColors.actionPrimary,
                  size: 16,
                ),
                label: Text(
                  _showDetails ? 'Hide details' : 'Show details',
                  style: const TextStyle(
                    color: DiogelColors.actionPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: DiogelSpacing.space2),
              Container(
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
                      'No signing will happen unless you approve a later '
                      'signing request.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (parsedPermissions.scopes.isNotEmpty) ...[
                      const SizedBox(height: DiogelSpacing.space4),
                      Text(
                        'REQUESTED PERMISSIONS',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: DiogelSpacing.space2),
                      Text(
                        parsedPermissions.scopes
                            .map((scope) => scope.label)
                            .join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: DiogelSpacing.space4),
                    Text(
                      'PUBLIC KEY',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: DiogelSpacing.space2),
                    Text(
                      truncatedNpub,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: DiogelColors.actionPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomSheet: Container(
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
            if (canRemember)
              InkWell(
                onTap: () => setState(() => _remember = !_remember),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: DiogelSpacing.space2),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (value) =>
                            setState(() => _remember = value ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Remember this decision for this app',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Tooltip(
                        message:
                            'Remembered decisions only auto-approve while your '
                            'short approval session is active. Browser '
                            'requests cannot be remembered.',
                        child: const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: DiogelColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(nip55ControllerProvider.notifier)
                            .rejectPublicKeyRequest(
                              remember: canRemember && _remember,
                            ),
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
                        borderRadius: BorderRadius.circular(
                          DiogelRadius.medium,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DiogelSpacing.space4),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: activeIdentity == null || isLoading
                        ? null
                        : () => ref
                              .read(nip55ControllerProvider.notifier)
                              .approvePublicKeyRequest(
                                remember: canRemember && _remember,
                              ),
                    icon: const Icon(Icons.key),
                    label: const Text('Share public key'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: DiogelSpacing.space4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DiogelRadius.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCryptoRequestScaffold(
    BuildContext context,
    VaultIdentity? activeIdentity,
  ) {
    final nip55Request = ref
        .watch(nip55ControllerProvider)
        .pendingCryptoRequest!;
    final canRemember = ref
        .read(nip55ControllerProvider.notifier)
        .canRememberPendingCryptoRequest();
    final source = nip55Request.clientIdentity.displayName;
    final method = nip55Request.method.wireName;
    final isSensitive = method.contains('decrypt');
    final peer = nip55Request.pubkey == null
        ? null
        : _shortFingerprint(nip55Request.pubkey!);
    final preview = (nip55Request.content ?? '').trim();

    final isLoading = ref.watch(nip55ControllerProvider).isLoading;

    return Scaffold(
      key: ValueKey('nip55-crypto-${nip55Request.requestToken}'),
      appBar: AppBar(title: Text('NIP-55 $method')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProvenanceWarning(context, RequestTrustStatus.unknown),
            const SizedBox(height: DiogelSpacing.space6),
            _buildSectionHeader(context, 'REQUEST SOURCE'),
            const SizedBox(height: DiogelSpacing.space2),
            RequestDetailItem(
              icon: Icons.android,
              iconColor: DiogelColors.actionPrimary,
              title: source,
              subtitle: nip55Request.clientIdentity.provenanceVerified
                  ? 'Verified Android package'
                  : 'Caller identity could not be fully verified',
            ),
            const SizedBox(height: DiogelSpacing.space6),
            _buildSectionHeader(context, 'OPERATION'),
            const SizedBox(height: DiogelSpacing.space2),
            RequestDetailItem(
              icon: isSensitive
                  ? Icons.visibility_outlined
                  : Icons.lock_outline,
              iconColor: isSensitive
                  ? DiogelColors.stateWarning
                  : DiogelColors.nostrAccentMuted,
              title: method,
              subtitle: isSensitive
                  ? 'Sensitive decrypt operation — review carefully'
                  : 'Encryption operation',
            ),
            if (peer != null) ...[
              const SizedBox(height: DiogelSpacing.space4),
              _buildSectionHeader(context, 'PEER PUBLIC KEY'),
              const SizedBox(height: DiogelSpacing.space2),
              Text(
                peer,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
            const SizedBox(height: DiogelSpacing.space6),
            _buildSectionHeader(context, 'USING ACCOUNT'),
            const SizedBox(height: DiogelSpacing.space2),
            _buildIdentityCard(context, activeIdentity),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: DiogelSpacing.space6),
              _buildSectionHeader(context, 'PAYLOAD PREVIEW'),
              const SizedBox(height: DiogelSpacing.space2),
              Text(
                preview.length > 400
                    ? '${preview.substring(0, 400)}…'
                    : preview,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
      bottomSheet: Container(
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
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(nip55ControllerProvider.notifier)
                            .rejectCryptoRequest(),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: DiogelSpacing.space4),
                if (canRemember) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: activeIdentity == null || isLoading
                          ? null
                          : () => ref
                                .read(nip55ControllerProvider.notifier)
                                .approveCryptoRequest(remember: true),
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Remember'),
                    ),
                  ),
                  const SizedBox(width: DiogelSpacing.space4),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: activeIdentity == null || isLoading
                        ? null
                        : () => ref
                              .read(nip55ControllerProvider.notifier)
                              .approveCryptoRequest(),
                    icon: Icon(isSensitive ? Icons.visibility : Icons.lock),
                    label: Text(isSensitive ? 'Decrypt' : 'Encrypt'),
                  ),
                ),
              ],
            ),
            if (canRemember) ...[
              const SizedBox(height: DiogelSpacing.space2),
              Text(
                'Remember is disabled for browser flows and sensitive decrypt scopes.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DiogelColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessMessage(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.stateSuccess.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(
          color: DiogelColors.stateSuccess.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: DiogelColors.stateSuccess,
          ),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: DiogelColors.stateSuccess,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              size: 20,
              color: DiogelColors.stateSuccess,
            ),
            onPressed: () =>
                ref.read(nip55ControllerProvider.notifier).clearMessages(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedMessage(
    BuildContext context,
    String eventId,
    String signature,
  ) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.stateSuccess.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(
          color: DiogelColors.stateSuccess.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_outlined, color: DiogelColors.stateSuccess),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event signed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: DiogelColors.stateSuccess,
                  ),
                ),
                const SizedBox(height: DiogelSpacing.space1),
                Text(
                  'The event was signed locally with your selected identity. It has not been published by Diogel.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DiogelSpacing.space2),
                Text(
                  'ID: ${_shortFingerprint(eventId)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                Text(
                  'SIG: ${_shortFingerprint(signature)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortFingerprint(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }

  Widget _buildFailureMessage(
    BuildContext context,
    String message, {
    VoidCallback? onDismiss,
  }) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.stateError.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(
          color: DiogelColors.stateError.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: DiogelColors.stateError),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: DiogelColors.stateError),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              size: 20,
              color: DiogelColors.stateError,
            ),
            onPressed:
                onDismiss ??
                () =>
                    ref.read(requestControllerProvider.notifier).clearFailure(),
          ),
        ],
      ),
    );
  }

  Widget _buildProvenanceWarning(
    BuildContext context,
    RequestTrustStatus status,
  ) {
    final isUntrusted =
        status == RequestTrustStatus.knownUntrusted ||
        status == RequestTrustStatus.invalid;

    if (status == RequestTrustStatus.knownTrusted) {
      return const SizedBox.shrink();
    }

    final color = isUntrusted
        ? DiogelColors.stateError
        : DiogelColors.stateWarning;
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: color),
                ),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskNote(BuildContext context, NostrEventPayloadReview review) {
    final isDangerous = review.isUnknownKind || review.isSensitive;
    final color = isDangerous
        ? DiogelColors.stateWarning
        : DiogelColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDangerous ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(DiogelRadius.small),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDangerous ? Icons.warning_amber_outlined : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Risk note',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: color),
                ),
                Text(
                  review.riskNote,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
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

  Widget _buildIdentityCard(
    BuildContext context,
    VaultIdentity? activeIdentity,
  ) {
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
              border: Border.all(color: DiogelColors.actionPrimary, width: 2),
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

  String _signingActionDescription(
    SigningRequest request,
    NostrEventPayloadReview? review,
  ) {
    if (review != null && !review.isUnknownKind) {
      return 'wants to sign a ${review.kindLabel} event';
    }
    return 'wants to sign a Kind ${request.eventKind} event';
  }

  String _publicKeyActionDescription(Nip55ParsedPermissions permissions) {
    final kinds = <int?>{};
    for (final scope in permissions.scopes) {
      if (scope is SignEventScope) {
        kinds.add(scope.kind);
      }
    }
    if (kinds.isEmpty) {
      return 'wants to connect';
    }
    if (kinds.contains(null)) {
      return 'wants permission to sign any event kind';
    }
    final sortedKinds = kinds.whereType<int>().toList()..sort();
    final kindLabel = sortedKinds.length == 1 ? 'Kind' : 'Kinds';
    return 'wants permission to sign $kindLabel ${sortedKinds.join(', ')} events';
  }

  String _npubFor(String publicKey) {
    try {
      return Nostr.instance.services.bech32.encodePublicKeyToNpub(publicKey);
    } catch (_) {
      return publicKey;
    }
  }

  static final _packageNamePattern = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  Widget _buildSourceIcon({
    required IconData icon,
    required Color iconColor,
    String? packageName,
  }) {
    const size = 40.0;
    Widget fallback() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(DiogelRadius.small),
      ),
      child: Icon(icon, color: iconColor),
    );

    if (packageName == null || !_packageNamePattern.hasMatch(packageName)) {
      return fallback();
    }

    final appIcon = ref.watch(appIconProvider(packageName));
    final bytes = appIcon.value;
    if (bytes == null || bytes.isEmpty) {
      return fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(DiogelRadius.small),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  Widget _buildRequestSummaryCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    String? packageName,
    required String sourceName,
    required bool sourceVerified,
    required String actionDescription,
    required VaultIdentity? activeIdentity,
  }) {
    final identityName = activeIdentity?.displayName ?? 'Anonymous';

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainer,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceIcon(
            icon: icon,
            iconColor: iconColor,
            packageName: packageName,
          ),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sourceName,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sourceVerified) ...[
                      const SizedBox(width: DiogelSpacing.space2),
                      const Icon(
                        Icons.verified,
                        size: 16,
                        color: DiogelColors.stateSuccess,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: DiogelSpacing.space1),
                Text.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      TextSpan(text: '$actionDescription using '),
                      TextSpan(
                        text: identityName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawJsonDisclosure(SigningRequest request) {
    final jsonString = const JsonEncoder.withIndent(
      '  ',
    ).convert(request.eventPayload);
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

  Widget _buildEventSummary(
    BuildContext context,
    SigningRequest request,
    NostrEventPayloadReview review,
  ) {
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
          if (request.eventPayload['permissionWarnings'] is List) ...[
            _buildPermissionWarnings(
              context,
              (request.eventPayload['permissionWarnings'] as List)
                  .map((warning) => warning.toString())
                  .toList(),
            ),
            const SizedBox(height: DiogelSpacing.space4),
          ],
          Text('NIP-55 METHOD', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            request.eventPayload['nip55Method']?.toString() ?? 'sign_event',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          Text(
            'PERMISSION IF REMEMBERED',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DiogelSpacing.space3),
            decoration: BoxDecoration(
              color: review.isBroadPermission
                  ? DiogelColors.stateWarning.withValues(alpha: 0.1)
                  : DiogelColors.surfaceBase,
              borderRadius: BorderRadius.circular(DiogelRadius.small),
              border: Border.all(
                color: review.isBroadPermission
                    ? DiogelColors.stateWarning.withValues(alpha: 0.4)
                    : DiogelColors.borderSubtle.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              review.permissionLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: review.isBroadPermission
                    ? DiogelColors.stateWarning
                    : null,
                fontWeight: review.isBroadPermission ? FontWeight.bold : null,
              ),
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          Text('CONTENT', style: Theme.of(context).textTheme.labelSmall),
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
              review.contentPreview,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TAGS', style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      review.tagsSummary,
                      style: Theme.of(context).textTheme.bodySmall,
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

  Widget _buildPermissionWarnings(BuildContext context, List<String> warnings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space3),
      decoration: BoxDecoration(
        color: DiogelColors.stateWarning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.small),
        border: Border.all(
          color: DiogelColors.stateWarning.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        warnings.join('\n'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: DiogelColors.stateWarning),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    SigningRequest request,
    bool isLoading,
  ) {
    final signerService = ref.watch(signerServiceProvider);
    final isDemo = signerService.isDemo;
    final nip55Controller = ref.read(nip55ControllerProvider.notifier);
    final isNip55Request =
        ref.watch(nip55ControllerProvider).pendingSigningRequestId ==
        request.id;
    final canRemember = nip55Controller.canRememberPendingSigningRequest(
      request.id,
    );

    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBackground.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: DiogelColors.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canRemember)
            InkWell(
              onTap: () => setState(() => _remember = !_remember),
              child: Padding(
                padding: const EdgeInsets.only(bottom: DiogelSpacing.space2),
                child: Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (value) =>
                          setState(() => _remember = value ?? false),
                    ),
                    Expanded(
                      child: Text(
                        'Remember this decision for this app',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Tooltip(
                      message:
                          'Remembered decisions only auto-approve while your '
                          'short approval session is active. Browser requests '
                          'cannot be remembered.',
                      child: const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: DiogelColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading
                      ? null
                      : () async {
                          await ref
                              .read(requestControllerProvider.notifier)
                              .rejectRequest(request.id);
                          await nip55Controller.rejectSigningRequest(
                            request.id,
                            remember: canRemember && _remember,
                          );
                        },
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
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (isNip55Request) {
                            await nip55Controller.approveSigningRequest(
                              request.id,
                              remember: canRemember && _remember,
                            );
                            return;
                          }
                          await ref
                              .read(requestControllerProvider.notifier)
                              .approveRequest(request.id);
                        },
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    isLoading
                        ? 'Signing...'
                        : isDemo
                        ? 'Sign event (DEMO)'
                        : 'Sign event',
                  ),
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
          if (isDemo) ...[
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              'DEMO: This action uses a fake signer for development purposes.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: DiogelColors.stateWarning,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDismissFailedButton(
    BuildContext context,
    SigningRequest request,
  ) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBackground.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: DiogelColors.borderSubtle)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => ref
              .read(requestControllerProvider.notifier)
              .dismissRequest(request.id),
          icon: const Icon(Icons.done),
          label: const Text('Dismiss failed request'),
        ),
      ),
    );
  }
}
