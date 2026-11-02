import 'dart:convert';

import 'package:symudol/features/requests/domain/nostr_event_draft.dart';

/// A NIP-46 `sign_event` request refused before it is reviewed or signed.
class Nip46SignEventException implements Exception {
  final String message;

  const Nip46SignEventException(this.message);

  @override
  String toString() => message;
}

/// The event a NIP-46 `sign_event` request asks Symudol to sign
/// (diogel-io/symudol#27).
///
/// The controller signs [draft] and the Approval screen reviews
/// [reviewPayload], both built here, so the review shows what is signed.
/// Only `pubkey`, `kind`, `content`, `tags` and `created_at` are read: any
/// other key the client sends is dropped.
class Nip46SignEvent {
  /// The client's pubkey, or the active identity's when it gave none. The
  /// controller refuses an event whose pubkey is not the active identity's.
  final String pubkey;
  final NostrEventDraft draft;

  /// Whether the client gave `created_at`. Without it the event is signed
  /// with the time of signing.
  final bool hasCreatedAt;

  const Nip46SignEvent._({
    required this.pubkey,
    required this.draft,
    required this.hasCreatedAt,
  });

  /// Parses the request's first parameter. Throws [Nip46SignEventException]
  /// when it is missing or is not a JSON object.
  factory Nip46SignEvent.parse(
    String? raw, {
    required String activePubkey,
    DateTime Function() now = _utcNow,
  }) {
    if (raw == null) {
      throw const Nip46SignEventException('sign_event: missing event JSON');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const Nip46SignEventException('sign_event: invalid event JSON');
    }
    if (decoded is! Map) {
      throw const Nip46SignEventException('sign_event: invalid event JSON');
    }

    final pubkey = decoded['pubkey'];
    final kind = decoded['kind'];
    final content = decoded['content'];
    final tags = decoded['tags'];
    final createdAt = decoded['created_at'];
    // Unix seconds that DateTime can hold: anything else would throw, or
    // wrap when turned into milliseconds.
    if (createdAt is int && (createdAt < 0 || createdAt > _maxCreatedAt)) {
      throw const Nip46SignEventException('sign_event: invalid created_at');
    }
    return Nip46SignEvent._(
      pubkey: pubkey is String && pubkey.isNotEmpty ? pubkey : activePubkey,
      hasCreatedAt: createdAt is int,
      draft: NostrEventDraft(
        // A missing kind is signed as kind 1 for now; refusing it is #28.
        kind: kind is int ? kind : 1,
        content: content is String ? content : '',
        tags: tags is List
            ? tags
                  .whereType<List>()
                  .map((t) => t.map((e) => e.toString()).toList())
                  .toList()
            : const [],
        createdAt: createdAt is int
            ? DateTime.fromMillisecondsSinceEpoch(createdAt * 1000, isUtc: true)
            : now(),
      ),
    );
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// The latest time DateTime can represent, 8.64e15 ms, in seconds.
  static const int _maxCreatedAt = 8640000000000;

  /// The event for review, as it will be signed.
  Map<String, Object?> get reviewPayload => {
    'pubkey': pubkey,
    'kind': draft.kind,
    'content': draft.content,
    'tags': draft.tags,
    if (hasCreatedAt)
      'created_at': draft.createdAt.millisecondsSinceEpoch ~/ 1000,
  };
}
