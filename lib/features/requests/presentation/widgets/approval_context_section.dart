import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../../nip46/domain/nip46_method.dart';
import '../../domain/approval_context.dart';
import '../../domain/nostr_event_payload_parser.dart';
import 'request_detail_item.dart';

class ApprovalContextSection extends StatelessWidget {
  const ApprovalContextSection({super.key, required this.approval});

  final ApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    return switch (approval) {
      SigningApprovalContext(:final eventReview) =>
        _SigningContextSection(review: eventReview),
      PublicKeyApprovalContext() => _PublicKeyContextSection(approval: approval as PublicKeyApprovalContext),
      CryptoApprovalContext(:final request) => _CryptoContextSection(
        label: request.method.displayLabel,
        isDecrypt: request.method.isDecrypt,
        isSignMessage: request.isSignMessage,
        peer: request.pubkey,
        content: request.content,
      ),
      RemoteSignerApprovalContext(:final method) =>
        method == Nip46Method.signEvent
            ? _SigningContextSection(
                review: (approval as RemoteSignerApprovalContext).eventReview,
              )
            : _CryptoContextSection(
                label: method.displayLabel,
                isDecrypt: method.isDecrypt,
                isSignMessage: false,
                peer: (approval as RemoteSignerApprovalContext).peerPubkey,
                content: (approval as RemoteSignerApprovalContext).content,
              ),
    };
  }
}

class _SigningContextSection extends StatelessWidget {
  const _SigningContextSection({required this.review});

  final NostrEventPayloadReview? review;

  @override
  Widget build(BuildContext context) {
    final review = this.review;
    if (review == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequestDetailItem(
          icon: Icons.edit_note,
          iconColor: DiogelColors.actionPrimary,
          title: review.kindLabel,
          subtitle: review.contentPreview,
        ),
        if (review.isUnknownKind || review.isSensitive) ...[
          const SizedBox(height: DiogelSpacing.space4),
          _RiskNote(review: review),
        ],
      ],
    );
  }
}

class _PublicKeyContextSection extends StatelessWidget {
  const _PublicKeyContextSection({required this.approval});

  final PublicKeyApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    final scopes = approval.parsedPermissions.scopes;
    final warnings = approval.parsedPermissions.warnings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequestDetailItem(
          icon: Icons.key,
          iconColor: DiogelColors.actionPrimary,
          title: scopes.isEmpty ? 'Connect to signer' : 'Permissions requested',
          subtitle: scopes.isEmpty
              ? 'No additional permissions were declared.'
              : scopes.map((s) => s.label).join(', '),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: DiogelSpacing.space3),
          _PermissionWarnings(warnings: warnings),
        ],
      ],
    );
  }
}

/// An encrypt, decrypt or sign-message request, from either protocol.
class _CryptoContextSection extends StatelessWidget {
  const _CryptoContextSection({
    required this.label,
    required this.isDecrypt,
    required this.isSignMessage,
    required this.peer,
    required this.content,
  });

  final String label;
  final bool isDecrypt;
  final bool isSignMessage;
  final String? peer;
  final String? content;

  @override
  Widget build(BuildContext context) {
    final isSensitive = isDecrypt;
    final peer = this.peer;
    final truncatedPeer = peer == null ? null : _shortFingerprint(peer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequestDetailItem(
          icon: isSignMessage
              ? Icons.draw_outlined
              : isSensitive
              ? Icons.visibility_outlined
              : Icons.lock_outline,
          iconColor: isSensitive
              ? DiogelColors.stateWarning
              : DiogelColors.nostrAccentMuted,
          title: label,
          subtitle: isSignMessage
              ? 'Signs this exact text with your key'
              : isSensitive
              ? 'Sensitive decrypt operation — review carefully'
              : 'Encryption operation',
        ),
        if (truncatedPeer != null) ...[
          const SizedBox(height: DiogelSpacing.space4),
          _SectionLabel(label: 'PEER PUBLIC KEY'),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            truncatedPeer,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: DiogelColors.textSecondary,
            ),
          ),
        ],
        if (content?.trim().isNotEmpty == true) ...[
          const SizedBox(height: DiogelSpacing.space4),
          _SectionLabel(
            label: isSignMessage ? 'MESSAGE' : 'PAYLOAD PREVIEW',
          ),
          const SizedBox(height: DiogelSpacing.space2),
          Builder(
            builder: (context) {
              final preview = content!.trim();
              // A message is shown in full, never cut short: it is what gets signed.
              return Text(
                isSignMessage || preview.length <= 400
                    ? preview
                    : '${preview.substring(0, 400)}…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: DiogelColors.textSecondary,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  String _shortFingerprint(String value) {
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }
}

class _RiskNote extends StatelessWidget {
  const _RiskNote({required this.review});

  final NostrEventPayloadReview review;

  @override
  Widget build(BuildContext context) {
    final isDangerous = review.isUnknownKind || review.isSensitive;
    final color = isDangerous ? DiogelColors.stateWarning : DiogelColors.textSecondary;

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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
                ),
                Text(
                  review.riskNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionWarnings extends StatelessWidget {
  const _PermissionWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space3),
      decoration: BoxDecoration(
        color: DiogelColors.stateWarning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DiogelRadius.small),
        border: Border.all(color: DiogelColors.stateWarning.withValues(alpha: 0.3)),
      ),
      child: Text(
        warnings.join('\n'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: DiogelColors.stateWarning,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: DiogelColors.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }
}
