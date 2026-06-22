import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/material.dart';

import '../../../../../theme/tokens.dart';
import '../../domain/approval_context.dart';
import '../../domain/nostr_event_payload_parser.dart';

class ApprovalDetailsSection extends StatelessWidget {
  const ApprovalDetailsSection({super.key, required this.approval});

  final ApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    return switch (approval) {
      SigningApprovalContext() =>
        _SigningDetailsSection(approval: approval as SigningApprovalContext),
      PublicKeyApprovalContext() =>
        _PublicKeyDetailsSection(approval: approval as PublicKeyApprovalContext),
      CryptoApprovalContext() =>
        _CryptoDetailsSection(approval: approval as CryptoApprovalContext),
    };
  }
}

class _SigningDetailsSection extends StatelessWidget {
  const _SigningDetailsSection({required this.approval});

  final SigningApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    final review = approval.eventReview;
    final payload = approval.request.eventPayload;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review != null) ...[
          _EventSummary(review: review, payload: payload),
          const SizedBox(height: DiogelSpacing.space4),
        ],
        _RawJsonBlock(payload: payload),
      ],
    );
  }
}

class _EventSummary extends StatelessWidget {
  const _EventSummary({required this.review, required this.payload});

  final NostrEventPayloadReview review;
  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
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
          if (payload['permissionWarnings'] is List) ...[
            _PermissionWarnings(
              warnings: (payload['permissionWarnings'] as List)
                  .map((w) => w.toString())
                  .toList(),
            ),
            const SizedBox(height: DiogelSpacing.space4),
          ],
          _label(context, 'NIP-55 METHOD'),
          const SizedBox(height: DiogelSpacing.space2),
          Text(
            payload['nip55Method']?.toString() ?? 'sign_event',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          _label(context, 'PERMISSION IF REMEMBERED'),
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
                color: review.isBroadPermission ? DiogelColors.stateWarning : null,
                fontWeight: review.isBroadPermission ? FontWeight.bold : null,
              ),
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          _label(context, 'CONTENT'),
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
                    _label(context, 'CREATED AT'),
                    Text(
                      payload['created_at']?.toString() ?? 'N/A',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context, 'TAGS'),
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

  Widget _label(BuildContext context, String text) {
    return Text(text, style: Theme.of(context).textTheme.labelSmall);
  }
}

class _RawJsonBlock extends StatelessWidget {
  const _RawJsonBlock({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
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
}

class _PublicKeyDetailsSection extends StatelessWidget {
  const _PublicKeyDetailsSection({required this.approval});

  final PublicKeyApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    final pubkey = approval.request.currentUser;
    final truncatedNpub = pubkey == null ? 'No active identity' : _npubFingerprint(pubkey);
    final scopes = approval.parsedPermissions.scopes;

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
          if (scopes.isNotEmpty) ...[
            Text('REQUESTED PERMISSIONS', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              scopes.map((s) => s.label).join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: DiogelSpacing.space4),
          ],
          Text('PUBLIC KEY', style: Theme.of(context).textTheme.labelSmall),
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
    );
  }

  String _npubFingerprint(String pubkey) {
    try {
      final npub = Nostr.instance.services.bech32.encodePublicKeyToNpub(pubkey);
      if (npub.length <= 16) return npub;
      return '${npub.substring(0, 8)}...${npub.substring(npub.length - 8)}';
    } catch (_) {
      if (pubkey.length <= 16) return pubkey;
      return '${pubkey.substring(0, 8)}...${pubkey.substring(pubkey.length - 8)}';
    }
  }
}

class _CryptoDetailsSection extends StatelessWidget {
  const _CryptoDetailsSection({required this.approval});

  final CryptoApprovalContext approval;

  @override
  Widget build(BuildContext context) {
    final content = (approval.request.content ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: content.isEmpty
          ? Text(
              'No payload content.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DiogelColors.textTertiary,
              ),
            )
          : SelectableText(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
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
