import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../accounts/presentation/widgets/profile_avatar.dart';
import '../../identity/domain/vault_identity.dart';
import '../../nip55/application/nip55_providers.dart';
import '../../nip55/domain/nip55_permission_parser.dart';
import '../../nip55/domain/nip55_permission_scope.dart';
import '../../vault/application/vault_providers.dart';
import '../application/request_providers.dart';
import '../domain/approval_context.dart';
import '../domain/nostr_event_payload_parser.dart';
import '../domain/request_trust_status.dart';
import '../domain/signed_nostr_event.dart';
import 'widgets/approval_context_section.dart';
import 'widgets/approval_details_section.dart';
import 'widgets/provenance_warning.dart';
import 'widgets/remember_row.dart';
import 'widgets/request_summary_card.dart';

class ApprovalScreen extends ConsumerWidget {
  const ApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approval = _resolveContext(ref);
    final nip55State = ref.watch(nip55ControllerProvider);

    if (approval == null) {
      return _EmptyApprovalState(
        isLoading: nip55State.isLoading,
        successMessage: nip55State.lastSuccessMessage,
        failureMessage: nip55State.failure?.message,
        activeIdentity: ref.watch(vaultControllerProvider).activeIdentity,
        onDismissMessages: () =>
            ref.read(nip55ControllerProvider.notifier).clearMessages(),
      );
    }

    return _ApprovalContent(
      key: ValueKey(approval.requestKey),
      approval: approval,
    );
  }

  ApprovalContext? _resolveContext(WidgetRef ref) {
    final activeRequest = ref.watch(activeRequestProvider);
    final nip55State = ref.watch(nip55ControllerProvider);
    final requestState = ref.watch(requestControllerProvider);
    final nip55Notifier = ref.read(nip55ControllerProvider.notifier);

    if (activeRequest != null) {
      final review = const NostrEventPayloadParser().review(activeRequest.eventPayload);
      final isNip55 = nip55State.pendingSigningRequestId == activeRequest.id;
      final canRemember = nip55Notifier.canRememberPendingSigningRequest(activeRequest.id);
      final signedEvent = requestState.signedEvents[activeRequest.id];
      return SigningApprovalContext(
        request: activeRequest,
        eventReview: review,
        isNip55Request: isNip55,
        canRemember: canRemember,
        signedEvent: signedEvent,
      );
    }

    final publicKeyRequest = nip55State.pendingPublicKeyRequest;
    if (publicKeyRequest != null) {
      final parsed = const Nip55PermissionParser().parse(publicKeyRequest.permissions);
      final canRemember = nip55Notifier.canRememberPendingPublicKeyRequest();
      return PublicKeyApprovalContext(
        request: publicKeyRequest,
        parsedPermissions: parsed,
        canRemember: canRemember,
      );
    }

    final cryptoRequest = nip55State.pendingCryptoRequest;
    if (cryptoRequest != null) {
      final canRemember = nip55Notifier.canRememberPendingCryptoRequest();
      return CryptoApprovalContext(
        request: cryptoRequest,
        canRemember: canRemember,
      );
    }

    return null;
  }
}

// ---------------------------------------------------------------------------
// Empty / idle state
// ---------------------------------------------------------------------------

class _EmptyApprovalState extends ConsumerWidget {
  const _EmptyApprovalState({
    required this.isLoading,
    required this.successMessage,
    required this.failureMessage,
    required this.activeIdentity,
    required this.onDismissMessages,
  });

  final bool isLoading;
  final String? successMessage;
  final String? failureMessage;
  final VaultIdentity? activeIdentity;
  final VoidCallback onDismissMessages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      key: const ValueKey('approval-empty'),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (successMessage != null) ...[
              _StatusBanner(
                icon: Icons.check_circle_outline,
                color: DiogelColors.stateSuccess,
                message: successMessage!,
                onDismiss: onDismissMessages,
              ),
              const SizedBox(height: DiogelSpacing.space6),
            ],
            if (failureMessage != null) ...[
              _StatusBanner(
                icon: Icons.error_outline,
                color: DiogelColors.stateError,
                message: failureMessage!,
                onDismiss: onDismissMessages,
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
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.message,
    required this.onDismiss,
  });

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space4),
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: DiogelSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: color),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active approval content — keyed per request so state resets automatically
// ---------------------------------------------------------------------------

class _ApprovalContent extends ConsumerStatefulWidget {
  const _ApprovalContent({required super.key, required this.approval});

  final ApprovalContext approval;

  @override
  ConsumerState<_ApprovalContent> createState() => _ApprovalContentState();
}

class _ApprovalContentState extends ConsumerState<_ApprovalContent> {
  bool _showDetails = false;
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    final vaultState = ref.watch(vaultControllerProvider);
    final activeIdentity = vaultState.activeIdentity;
    final requestState = ref.watch(requestControllerProvider);
    final nip55State = ref.watch(nip55ControllerProvider);

    // Derive the trust status and source info based on context type.
    final (trustStatus, sourceName, packageName, sourceVerified, actionDescription) =
        _sourceInfo(approval, activeIdentity);

    // For signing: check for failure or completed state.
    final signingFailureMsg = switch (approval) {
      SigningApprovalContext() => requestState.failure?.message,
      _ => null,
    };
    final displayFailureMsg = signingFailureMsg ?? nip55State.failure?.message;

    final isLoading = switch (approval) {
      SigningApprovalContext() => requestState.isLoading,
      _ => nip55State.isLoading,
    };

    // Signing-specific: signed event and failed state.
    final signingCtx = approval is SigningApprovalContext ? approval : null;
    final signedEvent = signingCtx?.signedEvent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approval Request'),
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
            if (displayFailureMsg != null) ...[
              _FailureBanner(
                message: displayFailureMsg,
                onDismiss: () => _dismissFailure(approval),
              ),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            if (signedEvent != null) ...[
              _SignedEventBanner(event: signedEvent),
              const SizedBox(height: DiogelSpacing.space4),
            ],
            ProvenanceWarning(trustStatus: trustStatus),
            const SizedBox(height: DiogelSpacing.space6),
            RequestSummaryCard(
              icon: _iconFor(approval),
              iconColor: DiogelColors.actionPrimary,
              packageName: packageName,
              sourceName: sourceName,
              sourceVerified: sourceVerified,
              actionDescription: actionDescription,
              activeIdentity: activeIdentity,
            ),
            const SizedBox(height: DiogelSpacing.space6),
            ApprovalContextSection(approval: approval),
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
              ApprovalDetailsSection(approval: approval),
            ],
          ],
        ),
      ),
      bottomSheet: _buildBottomSheet(
        context,
        approval: approval,
        activeIdentity: activeIdentity,
        isLoading: isLoading,
        signedEvent: signedEvent,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet
  // ---------------------------------------------------------------------------

  Widget? _buildBottomSheet(
    BuildContext context, {
    required ApprovalContext approval,
    required VaultIdentity? activeIdentity,
    required bool isLoading,
    SignedNostrEvent? signedEvent,
  }) {
    // Signing: no bottom sheet once the event is signed.
    if (signedEvent != null) return null;

    // Signing failed: only show dismiss button.
    if (approval is SigningApprovalContext && approval.isFailed) {
      return _DismissFailedSheet(
        onDismiss: () => ref
            .read(requestControllerProvider.notifier)
            .dismissRequest(approval.request.id),
      );
    }

    final canRemember = switch (approval) {
      SigningApprovalContext(:final canRemember) => canRemember,
      PublicKeyApprovalContext(:final canRemember) => canRemember,
      CryptoApprovalContext(:final canRemember) => canRemember,
    };

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
            RememberRow(
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () => _onReject(approval),
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: DiogelSpacing.space4),
                    side: const BorderSide(color: DiogelColors.borderStrong, width: 2),
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
                  onPressed: _approveDisabled(approval, activeIdentity, isLoading)
                      ? null
                      : () => _onApprove(approval),
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_approveIconFor(approval)),
                  label: Text(
                    isLoading
                        ? 'Processing...'
                        : _approveLabelFor(approval, ref),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: DiogelSpacing.space4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DiogelRadius.medium),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (approval is SigningApprovalContext &&
              ref.watch(signerServiceProvider).isDemo) ...[
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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _onApprove(ApprovalContext approval) async {
    final nip55 = ref.read(nip55ControllerProvider.notifier);
    final requests = ref.read(requestControllerProvider.notifier);

    switch (approval) {
      case SigningApprovalContext():
        if (approval.isNip55Request) {
          await nip55.approveSigningRequest(
            approval.request.id,
            remember: approval.canRemember && _remember,
          );
        } else {
          await requests.approveRequest(approval.request.id);
        }
      case PublicKeyApprovalContext():
        await nip55.approvePublicKeyRequest(
          remember: approval.canRemember && _remember,
        );
      case CryptoApprovalContext():
        await nip55.approveCryptoRequest(
          remember: approval.canRemember && _remember,
        );
    }
  }

  Future<void> _onReject(ApprovalContext approval) async {
    final nip55 = ref.read(nip55ControllerProvider.notifier);
    final requests = ref.read(requestControllerProvider.notifier);

    switch (approval) {
      case SigningApprovalContext():
        await requests.rejectRequest(approval.request.id);
        await nip55.rejectSigningRequest(
          approval.request.id,
          remember: approval.canRemember && _remember,
        );
      case PublicKeyApprovalContext():
        await nip55.rejectPublicKeyRequest(
          remember: approval.canRemember && _remember,
        );
      case CryptoApprovalContext():
        await nip55.rejectCryptoRequest(
          remember: approval.canRemember && _remember,
        );
    }
  }

  void _dismissFailure(ApprovalContext approval) {
    if (approval is SigningApprovalContext) {
      ref.read(requestControllerProvider.notifier).clearFailure();
    } else {
      ref.read(nip55ControllerProvider.notifier).clearMessages();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  (RequestTrustStatus, String, String?, bool, String) _sourceInfo(
    ApprovalContext approval,
    VaultIdentity? activeIdentity,
  ) {
    return switch (approval) {
      SigningApprovalContext() => (
        approval.request.provenance.trustStatus,
        approval.request.provenance.sourceDisplayName,
        approval.request.provenance.sourceIdentifier,
        approval.request.provenance.trustStatus == RequestTrustStatus.knownTrusted,
        _signingActionDescription(approval),
      ),
      PublicKeyApprovalContext() => (
        approval.request.clientIdentity.provenanceVerified
            ? RequestTrustStatus.knownTrusted
            : RequestTrustStatus.unknown,
        approval.request.clientIdentity.displayName,
        approval.request.clientIdentity.packageName,
        approval.request.clientIdentity.provenanceVerified,
        _publicKeyActionDescription(approval),
      ),
      CryptoApprovalContext() => (
        approval.request.clientIdentity.provenanceVerified
            ? RequestTrustStatus.knownTrusted
            : RequestTrustStatus.unknown,
        approval.request.clientIdentity.displayName,
        approval.request.clientIdentity.packageName,
        approval.request.clientIdentity.provenanceVerified,
        'requests a ${approval.request.method.displayLabel} operation',
      ),
    };
  }

  String _signingActionDescription(SigningApprovalContext approval) {
    final review = approval.eventReview;
    if (review != null && !review.isUnknownKind) {
      return 'wants to sign a ${review.kindLabel} event';
    }
    return 'wants to sign a Kind ${approval.request.eventKind} event';
  }

  String _publicKeyActionDescription(PublicKeyApprovalContext approval) {
    final scopes = approval.parsedPermissions.scopes;
    final kinds = <int?>{};
    for (final scope in scopes) {
      if (scope is SignEventScope) kinds.add(scope.kind);
    }
    if (kinds.isEmpty) return 'wants to connect';
    if (kinds.contains(null)) return 'wants permission to sign any event kind';
    final sortedKinds = kinds.whereType<int>().toList()..sort();
    final kindLabel = sortedKinds.length == 1 ? 'Kind' : 'Kinds';
    return 'wants permission to sign $kindLabel ${sortedKinds.join(', ')} events';
  }

  IconData _iconFor(ApprovalContext approval) {
    return switch (approval) {
      SigningApprovalContext() => Icons.edit_note,
      PublicKeyApprovalContext() => Icons.key,
      CryptoApprovalContext() =>
        approval.request.method.isDecrypt
            ? Icons.visibility_outlined
            : Icons.lock_outline,
    };
  }

  IconData _approveIconFor(ApprovalContext approval) {
    return switch (approval) {
      SigningApprovalContext() => Icons.check,
      PublicKeyApprovalContext() => Icons.key,
      CryptoApprovalContext() =>
        approval.request.method.isDecrypt ? Icons.visibility : Icons.lock,
    };
  }

  bool _approveDisabled(
    ApprovalContext approval,
    VaultIdentity? activeIdentity,
    bool isLoading,
  ) {
    if (isLoading) return true;
    // Signing lets the controller handle locked/no-identity errors so the user
    // sees a clear failure message rather than a silently disabled button.
    if (approval is SigningApprovalContext) return false;
    return activeIdentity == null;
  }

  String _approveLabelFor(ApprovalContext approval, WidgetRef ref) {
    return switch (approval) {
      SigningApprovalContext() => ref.watch(signerServiceProvider).isDemo
          ? 'Sign event (DEMO)'
          : 'Sign event',
      PublicKeyApprovalContext() => 'Share public key',
      CryptoApprovalContext() =>
        approval.request.method.isDecrypt ? 'Decrypt' : 'Encrypt',
    };
  }
}

// ---------------------------------------------------------------------------
// Inline banner widgets
// ---------------------------------------------------------------------------

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
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
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _SignedEventBanner extends StatelessWidget {
  const _SignedEventBanner({required this.event});

  final SignedNostrEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.stateSuccess.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.stateSuccess.withValues(alpha: 0.3)),
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
                const Text(
                  'The event was signed locally with your selected identity. '
                  'It has not been published by Diogel.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: DiogelSpacing.space2),
                Text(
                  'ID: ${_short(event.id)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'SIG: ${_short(event.sig)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _short(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }
}

class _DismissFailedSheet extends StatelessWidget {
  const _DismissFailedSheet({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBackground.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: DiogelColors.borderSubtle)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onDismiss,
          icon: const Icon(Icons.done),
          label: const Text('Dismiss failed request'),
        ),
      ),
    );
  }
}
