import 'nostr_event_draft.dart';
import 'signing_request.dart';

class NostrEventPayloadParseException implements Exception {
  final String message;

  const NostrEventPayloadParseException(this.message);

  @override
  String toString() => message;
}

class NostrEventPayloadReview {
  final int kind;
  final String kindLabel;
  final String contentPreview;
  final String tagsSummary;
  final String riskNote;
  final String permissionLabel;
  final bool isUnknownKind;
  final bool isSensitive;
  final bool isBroadPermission;

  const NostrEventPayloadReview({
    required this.kind,
    required this.kindLabel,
    required this.contentPreview,
    required this.tagsSummary,
    required this.riskNote,
    required this.permissionLabel,
    required this.isUnknownKind,
    required this.isSensitive,
    required this.isBroadPermission,
  });
}

class NostrEventPayloadParser {
  const NostrEventPayloadParser();

  NostrEventDraft parse(SigningRequest request) {
    final payload = request.eventPayload;
    final kind = payload['kind'] ?? request.eventKind;
    if (kind is! int) {
      throw const NostrEventPayloadParseException('Event kind is invalid');
    }

    final content = payload['content'];
    if (content != null && content is! String) {
      throw const NostrEventPayloadParseException('Event content is invalid');
    }

    return NostrEventDraft(
      kind: kind,
      content: content as String? ?? '',
      tags: _parseTags(payload['tags']),
      createdAt: _parseCreatedAt(payload['created_at']),
    );
  }

  NostrEventPayloadReview review(Map<String, Object?> payload) {
    final kind = payload['kind'] is int ? payload['kind'] as int : -1;
    final permission = payload['nip55PermissionScope']?.toString();
    final unknownKind = !_knownKindLabels.containsKey(kind);
    final broadPermission = permission == 'sign_event';
    final sensitive = _sensitiveKinds.contains(kind) || broadPermission;

    return NostrEventPayloadReview(
      kind: kind,
      kindLabel: kindLabel(kind),
      contentPreview: contentPreview(payload['content'], kind),
      tagsSummary: tagsSummary(payload['tags']),
      riskNote: riskNote(kind: kind, isBroadPermission: broadPermission),
      permissionLabel: permissionLabel(permission, kind),
      isUnknownKind: unknownKind,
      isSensitive: sensitive,
      isBroadPermission: broadPermission,
    );
  }

  String kindLabel(int kind) {
    return _knownKindLabels[kind] ??
        'Unknown event kind. Review carefully before signing.';
  }

  String contentPreview(Object? content, int kind) {
    final text = content?.toString() ?? '';
    if (text.trim().isEmpty) {
      return switch (kind) {
        0 => 'Profile metadata with empty content.',
        3 => 'Contact list update with no text content.',
        10002 => 'Relay list metadata with no text content.',
        _ => 'No content',
      };
    }
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 280) return singleLine;
    return '${singleLine.substring(0, 280)}…';
  }

  String tagsSummary(Object? tags) {
    if (tags is! List || tags.isEmpty) return 'No tags';
    final counts = <String, int>{};
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty) {
        final name = tag.first?.toString() ?? '?';
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '${tags.length} unstructured tag(s)';
    final summary = counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(', ');
    return '${tags.length} tag(s): $summary';
  }

  String riskNote({required int kind, required bool isBroadPermission}) {
    if (isBroadPermission) {
      return 'Broad sign_event permission. Remembering this would allow this app to request any event kind covered by that grant.';
    }
    return switch (kind) {
      0 => 'This can change your public profile metadata.',
      1 =>
        'This is a public text note. Anyone may be able to read it after the requesting app publishes it.',
      3 => 'This can replace your contact list.',
      4 => 'Legacy encrypted DM / NIP-04. Review recipient tags carefully.',
      6 => 'This reposts another event from your account.',
      7 => 'This reacts to another event from your account.',
      9735 =>
        'Zap receipts are usually service-generated. Check the source carefully.',
      10002 => 'This can update your public relay list metadata.',
      22242 => 'Client authentication proves control of this key to a service.',
      _ => 'Unknown event kind. Review carefully before signing.',
    };
  }

  String permissionLabel(String? permission, int kind) {
    if (permission == null || permission.isEmpty) {
      return 'Allow once only';
    }
    if (permission == 'sign_event') {
      return 'Remember broad permission: sign any event kind';
    }
    if (permission == 'sign_event:$kind') {
      return 'Remember permission: sign kind $kind only';
    }
    return 'Remember permission: $permission';
  }

  List<List<String>> _parseTags(Object? rawTags) {
    if (rawTags == null) return const [];
    if (rawTags is! List) {
      throw const NostrEventPayloadParseException('Event tags are invalid');
    }
    return rawTags
        .map((tag) {
          if (tag is! List) {
            throw const NostrEventPayloadParseException('Event tag is invalid');
          }
          return tag.map((value) => value.toString()).toList(growable: false);
        })
        .toList(growable: false);
  }

  DateTime _parseCreatedAt(Object? rawCreatedAt) {
    if (rawCreatedAt == null) return DateTime.now();
    if (rawCreatedAt is int) {
      return DateTime.fromMillisecondsSinceEpoch(rawCreatedAt * 1000);
    }
    if (rawCreatedAt is String) {
      final parsed = int.tryParse(rawCreatedAt);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsed * 1000);
      }
    }
    throw const NostrEventPayloadParseException('Event created_at is invalid');
  }
}

const _knownKindLabels = <int, String>{
  0: 'Metadata/profile',
  1: 'Text note',
  3: 'Contact list',
  4: 'Legacy encrypted DM / NIP-04',
  6: 'Repost',
  7: 'Reaction',
  9735: 'Zap receipt',
  10002: 'Relay list metadata',
  22242: 'Client authentication',
};

const _sensitiveKinds = <int>{0, 3, 4, 10002, 22242};
