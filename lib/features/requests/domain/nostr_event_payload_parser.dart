import 'nostr_event_draft.dart';
import 'nostr_event_kind_registry.dart';
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
    final entry = registryEntry(kind);
    final notInRegistry = entry == null;
    final broadPermission = permission == 'sign_event';
    final sensitive = (entry?.sensitive ?? false) || broadPermission;

    return NostrEventPayloadReview(
      kind: kind,
      kindLabel: kindLabel(kind),
      contentPreview: contentPreview(payload['content'], kind, payload['tags']),
      tagsSummary: tagsSummary(payload['tags']),
      riskNote: riskNote(kind: kind, isBroadPermission: broadPermission),
      permissionLabel: permissionLabel(permission, kind),
      isUnknownKind: notInRegistry,
      isSensitive: sensitive,
      isBroadPermission: broadPermission,
    );
  }

  String kindLabel(int kind) {
    return registryEntry(kind)?.label ?? fallbackKindLabel(kind);
  }

  String contentPreview(
    Object? content,
    int kind, [
    Object? tags,
  ]) {
    final text = content?.toString() ?? '';
    final entry = registryEntry(kind);
    if (text.trim().isEmpty) {
      final emptyPreview = entry?.emptyContentPreview;
      if (emptyPreview != null) return emptyPreview;
      // NIP-31: for unregistered kinds, surface alt tag when content is absent
      if (entry == null) {
        final alt = _firstTagValue(tags, 'alt');
        if (alt != null) {
          final trimmed = alt.trim();
          if (trimmed.isNotEmpty) {
            if (trimmed.length <= 276) return 'Alt: $trimmed';
            return 'Alt: ${trimmed.substring(0, 276)}…';
          }
        }
      }
      return 'No content';
    }
    if (entry?.nonEmptyContentPreview != null) {
      return entry!.nonEmptyContentPreview!;
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
    final entry = registryEntry(kind);
    if (entry != null) {
      return entry.riskNote ??
          'This is a known Nostr protocol event. Review the requesting app and content before signing.';
    }
    return fallbackRiskNote(kind);
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

/// Returns the first value of a tag named [name] from a raw tags list,
/// or null if not present. Used for NIP-31 alt tag surfacing.
String? _firstTagValue(Object? tags, String name) {
  if (tags is! List) return null;
  for (final tag in tags) {
    if (tag is List && tag.length >= 2 && tag.first == name) {
      final value = tag[1];
      if (value is String && value.trim().isNotEmpty) return value;
    }
  }
  return null;
}
