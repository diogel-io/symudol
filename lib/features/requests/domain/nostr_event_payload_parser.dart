import 'nostr_event_draft.dart';
import 'signing_request.dart';

class NostrEventPayloadParseException implements Exception {
  final String message;

  const NostrEventPayloadParseException(this.message);

  @override
  String toString() => 'NostrEventPayloadParseException: $message';
}

class NostrEventPayloadParser {
  const NostrEventPayloadParser();

  NostrEventDraft parse(SigningRequest request) {
    final payload = request.eventPayload;

    final payloadKind = payload['kind'];
    if (payloadKind != null && payloadKind is! int) {
      throw const NostrEventPayloadParseException('Invalid event kind');
    }
    if (payloadKind != null && payloadKind != request.eventKind) {
      throw const NostrEventPayloadParseException(
        'Event kind mismatch between request metadata and payload',
      );
    }
    final kindValue = request.eventKind;

    final contentValue = payload['content'];
    if (contentValue is! String) {
      throw const NostrEventPayloadParseException('Invalid event content');
    }

    final createdAtValue = payload['created_at'];
    final createdAt = createdAtValue == null
        ? request.createdAt
        : _parseCreatedAt(createdAtValue);

    return NostrEventDraft(
      kind: kindValue,
      content: contentValue,
      tags: _parseTags(payload['tags']),
      createdAt: createdAt,
    );
  }

  DateTime _parseCreatedAt(Object? value) {
    if (value is! int) {
      throw const NostrEventPayloadParseException('Invalid created_at');
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  List<List<String>> _parseTags(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const NostrEventPayloadParseException('Invalid tags');
    }

    return value
        .map<List<String>>((tag) {
          if (tag is! List) {
            throw const NostrEventPayloadParseException('Invalid tag');
          }
          return tag
              .map<String>((entry) {
                if (entry is! String) {
                  throw const NostrEventPayloadParseException(
                    'Invalid tag entry',
                  );
                }
                return entry;
              })
              .toList(growable: false);
        })
        .toList(growable: false);
  }
}
