class SignedNostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  SignedNostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  }) {
    if (id.isEmpty) throw ArgumentError('Event id cannot be empty');
    if (sig.isEmpty) throw ArgumentError('Event signature cannot be empty');
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags.map((tag) => List<String>.from(tag)).toList(),
      'content': content,
      'sig': sig,
    };
  }

  SignedNostrEvent copyWith({
    String? id,
    String? pubkey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
  }) {
    return SignedNostrEvent(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      tags: tags ?? this.tags,
      content: content ?? this.content,
      sig: sig ?? this.sig,
    );
  }
}
