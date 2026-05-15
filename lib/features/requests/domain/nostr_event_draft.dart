class NostrEventDraft {
  final int kind;
  final String content;
  final List<List<String>> tags;
  final DateTime createdAt;

  const NostrEventDraft({
    required this.kind,
    required this.content,
    required this.tags,
    required this.createdAt,
  });
}
