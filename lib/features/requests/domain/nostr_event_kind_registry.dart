// Source-controlled event-kind registry for Diogel.
//
// Curated entries carry hand-reviewed security copy. Neutral entries carry a
// protocol label and a generic risk note so valid Nostr kinds never display
// "Unknown event kind." Unregistered kinds receive NIP-01 range labels via
// [fallbackKindLabel] and [fallbackRiskNote].
//
// Update procedure: add or revise entries here, run parser tests, and
// get security copy reviewed before merging. Do not fetch this at runtime.

class EventKindEntry {
  final String label;
  final bool sensitive;

  /// Null means: use generic registry note for known kinds, or fallback for
  /// unregistered kinds.
  final String? riskNote;
  final String? emptyContentPreview;
  final String? nonEmptyContentPreview;

  const EventKindEntry({
    required this.label,
    this.sensitive = false,
    this.riskNote,
    this.emptyContentPreview,
    this.nonEmptyContentPreview,
  });
}

const _genericNote =
    'This is a known Nostr protocol event. Review the requesting app and content before signing.';

/// Returns the [EventKindEntry] for [kind], or null if not registered.
EventKindEntry? registryEntry(int kind) => _registry[kind];

/// Returns a NIP-01 range label for [kind] when it is not in the registry.
/// Returns `'Invalid event kind'` for negative kinds.
String fallbackKindLabel(int kind) {
  if (kind < 0) return 'Invalid event kind';
  if (kind == 1 || kind == 2 || (kind >= 4 && kind < 45) || (kind >= 1000 && kind < 10000)) {
    return 'Regular Nostr event kind $kind';
  }
  if (kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000)) {
    return 'Replaceable Nostr event kind $kind';
  }
  if (kind >= 20000 && kind < 30000) {
    return 'Ephemeral Nostr event kind $kind';
  }
  if (kind >= 30000 && kind < 40000) {
    return 'Addressable Nostr event kind $kind';
  }
  return 'Custom Nostr event kind $kind';
}

/// Returns a range-appropriate risk note for [kind] when it is not curated.
/// Never returns "Unknown event kind" copy.
String fallbackRiskNote(int kind) {
  if (kind < 0) {
    return 'The event kind is missing or invalid. Do not sign this request.';
  }
  if (kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000)) {
    return 'This is a replaceable event. Signing it can overwrite prior state for this key on participating relays. Review the requesting app and content before signing.';
  }
  if (kind >= 20000 && kind < 30000) {
    return 'This is an ephemeral event. Relays are not expected to store it, but signing still authorises the content under your key.';
  }
  if (kind >= 30000 && kind < 40000) {
    return 'This is an addressable event identified by kind, pubkey, and d tag. Signing it can create or replace stored state. Review the d tag and requesting app before signing.';
  }
  return "This kind is not yet in Diogel's event-kind registry. Review the requesting app, content, and tags before signing.";
}

const _registry = <int, EventKindEntry>{
  // ── Curated: profile and social core ────────────────────────────────────
  0: EventKindEntry(
    label: 'Metadata/profile',
    sensitive: true,
    riskNote: 'This can change your public profile metadata.',
    emptyContentPreview: 'Profile metadata with empty content.',
  ),
  1: EventKindEntry(
    label: 'Text note',
    riskNote:
        'This is a public text note. Anyone may be able to read it after the requesting app publishes it.',
  ),
  3: EventKindEntry(
    label: 'Contact list',
    sensitive: true,
    riskNote: 'This can replace your contact list.',
    emptyContentPreview: 'Contact list update with no text content.',
  ),
  4: EventKindEntry(
    label: 'Legacy encrypted DM / NIP-04',
    sensitive: true,
    riskNote: 'Legacy encrypted DM / NIP-04. Review recipient tags carefully.',
  ),
  5: EventKindEntry(
    label: 'Event deletion request / NIP-09',
    sensitive: true,
    riskNote:
        'This asks relays and clients to delete or hide referenced events. Deletion is not guaranteed across all relays.',
    emptyContentPreview: 'Deletion request with no reason text.',
  ),
  6: EventKindEntry(
    label: 'Repost',
    riskNote: 'This reposts another event from your account.',
  ),
  7: EventKindEntry(
    label: 'Reaction',
    riskNote: 'This reacts to another event from your account.',
  ),

  // ── Curated: private and encrypted event types ───────────────────────────
  13: EventKindEntry(
    label: 'Seal / NIP-59',
    sensitive: true,
    riskNote:
        'This is an encrypted sealed event. The content is hidden from relay inspection, but signing identifies you as the sender.',
  ),
  14: EventKindEntry(
    label: 'Direct Message / NIP-17',
    sensitive: true,
    riskNote:
        'This is a private direct-message rumor. The content is private, but the recipient tags are visible to relays.',
  ),
  15: EventKindEntry(
    label: 'File Message / NIP-17',
    sensitive: true,
    riskNote:
        'This is a private file-message rumor. The content is private, but the recipient tags are visible to relays.',
  ),

  // ── Curated: destructive or high-impact ──────────────────────────────────
  62: EventKindEntry(
    label: 'Request to Vanish / NIP-62',
    sensitive: true,
    riskNote:
        'This requests participating relays to delete all events from this key up to the given timestamp. The action is irreversible on participating relays.',
  ),

  // ── Neutral: social content ──────────────────────────────────────────────
  8: EventKindEntry(label: 'Badge Award / NIP-58', riskNote: _genericNote),
  9: EventKindEntry(label: 'Chat Message / NIP-C7', riskNote: _genericNote),
  11: EventKindEntry(label: 'Thread / NIP-7D', riskNote: _genericNote),
  16: EventKindEntry(label: 'Generic Repost / NIP-18', riskNote: _genericNote),
  17: EventKindEntry(
    label: 'Reaction to a website / NIP-25',
    riskNote: _genericNote,
  ),
  20: EventKindEntry(label: 'Picture / NIP-68', riskNote: _genericNote),
  21: EventKindEntry(label: 'Video Event / NIP-71', riskNote: _genericNote),
  22: EventKindEntry(
    label: 'Short-form Portrait Video / NIP-71',
    riskNote: _genericNote,
  ),
  24: EventKindEntry(label: 'Public Message / NIP-A4', riskNote: _genericNote),

  // ── Neutral: channel events ───────────────────────────────────────────────
  40: EventKindEntry(
    label: 'Channel Creation / NIP-28',
    riskNote: _genericNote,
  ),
  41: EventKindEntry(
    label: 'Channel Metadata / NIP-28',
    riskNote: _genericNote,
  ),
  42: EventKindEntry(
    label: 'Channel Message / NIP-28',
    riskNote: _genericNote,
  ),
  43: EventKindEntry(
    label: 'Channel Hide Message / NIP-28',
    riskNote: _genericNote,
  ),
  44: EventKindEntry(
    label: 'Channel Mute User / NIP-28',
    riskNote: _genericNote,
  ),

  // ── Neutral: media and content ────────────────────────────────────────────
  54: EventKindEntry(
    label: 'Podcast Episode / NIP-F4',
    riskNote: _genericNote,
  ),
  64: EventKindEntry(label: 'Chess (PGN) / NIP-64', riskNote: _genericNote),
  78: EventKindEntry(
    label: 'Application-specific Data / NIP-78',
    riskNote: _genericNote,
  ),
  818: EventKindEntry(
    label: 'Merge Request / NIP-54',
    riskNote: _genericNote,
  ),

  // ── Neutral: marketplace and finance ─────────────────────────────────────
  1018: EventKindEntry(
    label: 'Poll Response / NIP-88',
    riskNote: _genericNote,
  ),
  1021: EventKindEntry(label: 'Bid / NIP-15', riskNote: _genericNote),
  1022: EventKindEntry(
    label: 'Bid Confirmation / NIP-15',
    riskNote: _genericNote,
  ),

  // ── Neutral: regular events ───────────────────────────────────────────────
  1040: EventKindEntry(
    label: 'OpenTimestamps / NIP-03',
    riskNote: _genericNote,
  ),
  1059: EventKindEntry(
    label: 'Gift Wrap / NIP-59',
    sensitive: true,
    riskNote:
        'This is an encrypted gift-wrapped delivery event with recipient routing tags. The inner content is encrypted.',
  ),
  1063: EventKindEntry(
    label: 'File Metadata / NIP-94',
    riskNote: _genericNote,
  ),
  1068: EventKindEntry(label: 'Poll / NIP-88', riskNote: _genericNote),
  1111: EventKindEntry(label: 'Comment / NIP-22', riskNote: _genericNote),
  1222: EventKindEntry(
    label: 'Voice Message / NIP-A0',
    riskNote: _genericNote,
  ),
  1234: EventKindEntry(
    label: 'Draft Checkpoint / NIP-37',
    riskNote: _genericNote,
  ),
  1311: EventKindEntry(
    label: 'Live Chat Message / NIP-53',
    riskNote: _genericNote,
  ),
  1337: EventKindEntry(
    label: 'Code Snippet / NIP-C0',
    riskNote: _genericNote,
  ),
  1617: EventKindEntry(label: 'Patches / NIP-34', riskNote: _genericNote),
  1618: EventKindEntry(
    label: 'Pull Requests / NIP-34',
    riskNote: _genericNote,
  ),
  1621: EventKindEntry(label: 'Issues / NIP-34', riskNote: _genericNote),
  1984: EventKindEntry(label: 'Reporting / NIP-56', riskNote: _genericNote),
  1985: EventKindEntry(label: 'Label / NIP-32', riskNote: _genericNote),
  2003: EventKindEntry(label: 'Torrent / NIP-35', riskNote: _genericNote),
  2004: EventKindEntry(
    label: 'Torrent Comment / NIP-35',
    riskNote: _genericNote,
  ),
  4550: EventKindEntry(
    label: 'Community Post Approval / NIP-72',
    riskNote: _genericNote,
  ),

  // ── Neutral: Cashu wallet ─────────────────────────────────────────────────
  7375: EventKindEntry(
    label: 'Cashu Wallet Tokens / NIP-60',
    riskNote: _genericNote,
  ),
  7376: EventKindEntry(
    label: 'Cashu Wallet History / NIP-60',
    riskNote: _genericNote,
  ),

  // ── Neutral: group management ─────────────────────────────────────────────
  8000: EventKindEntry(label: 'Add User / NIP-43', riskNote: _genericNote),
  8001: EventKindEntry(label: 'Remove User / NIP-43', riskNote: _genericNote),

  // ── Curated: payment ─────────────────────────────────────────────────────
  9041: EventKindEntry(label: 'Zap Goal / NIP-75', riskNote: _genericNote),
  9321: EventKindEntry(label: 'Nutzap / NIP-61', riskNote: _genericNote),
  9734: EventKindEntry(
    label: 'Zap Request / NIP-57',
    sensitive: true,
    riskNote: 'This is a payment-related zap request event. Review the amount and recipient tags before signing.',
  ),
  9735: EventKindEntry(
    label: 'Zap receipt',
    riskNote:
        'Zap receipts are usually service-generated. Check the source carefully.',
  ),
  9802: EventKindEntry(label: 'Highlights / NIP-84', riskNote: _genericNote),

  // ── Curated: replaceable list events ─────────────────────────────────────
  10000: EventKindEntry(
    label: 'Mute list / NIP-51',
    sensitive: true,
    riskNote: 'This can replace your mute list.',
    emptyContentPreview: 'Mute list with no text content.',
  ),
  10001: EventKindEntry(
    label: 'Pin list / NIP-51',
    riskNote: _genericNote,
  ),
  10002: EventKindEntry(
    label: 'Relay List Metadata',
    sensitive: true,
    riskNote: 'This can update your public relay list metadata.',
    emptyContentPreview: 'Relay list metadata with no text content.',
  ),
  10003: EventKindEntry(
    label: 'Bookmark list / NIP-51',
    riskNote: _genericNote,
  ),
  10004: EventKindEntry(
    label: 'Communities list / NIP-51',
    riskNote: _genericNote,
  ),
  10005: EventKindEntry(
    label: 'Public chats list / NIP-51',
    riskNote: _genericNote,
  ),
  10006: EventKindEntry(
    label: 'Blocked relays list / NIP-51',
    sensitive: true,
    riskNote: 'This can update the relays your client blocks.',
  ),
  10007: EventKindEntry(
    label: 'Search relays list / NIP-51',
    riskNote: _genericNote,
  ),
  10008: EventKindEntry(
    label: 'Profile Badges / NIP-58',
    riskNote: _genericNote,
  ),
  10009: EventKindEntry(
    label: 'User groups / NIP-51',
    riskNote: _genericNote,
  ),
  10011: EventKindEntry(
    label: 'External Identities / NIP-39',
    riskNote: _genericNote,
  ),
  10013: EventKindEntry(
    label: 'Private event relay list / NIP-37',
    sensitive: true,
    riskNote: 'This stores your private relay preferences for draft events.',
  ),
  10015: EventKindEntry(
    label: 'Interests list / NIP-51',
    riskNote: _genericNote,
  ),
  10030: EventKindEntry(
    label: 'User emoji list / NIP-51',
    riskNote: _genericNote,
  ),
  10050: EventKindEntry(
    label: 'DM relay list / NIP-17',
    sensitive: true,
    riskNote:
        'This can update the relays where you receive encrypted direct messages.',
  ),

  // ── Curated: auth and protocol ────────────────────────────────────────────
  22242: EventKindEntry(
    label: 'Client authentication',
    sensitive: true,
    riskNote:
        'Client authentication proves control of this key to a service.',
  ),
  23194: EventKindEntry(
    label: 'Wallet Request / NIP-47',
    riskNote: _genericNote,
  ),
  23195: EventKindEntry(
    label: 'Wallet Response / NIP-47',
    riskNote: _genericNote,
  ),
  24133: EventKindEntry(
    label: 'Nostr Connect / NIP-46',
    riskNote: _genericNote,
  ),
  27235: EventKindEntry(
    label: 'HTTP Auth / NIP-98',
    riskNote: _genericNote,
  ),

  // ── Curated: ephemeral encrypted ─────────────────────────────────────────
  21059: EventKindEntry(
    label: 'Ephemeral Gift Wrap / NIP-59',
    sensitive: true,
    riskNote:
        'This is an ephemeral encrypted delivery wrapper. Relays are not expected to store it, but signing still authorises the content under your key.',
  ),

  // ── Curated: addressable storage ─────────────────────────────────────────
  31234: EventKindEntry(
    label: 'Draft wrap / NIP-37',
    sensitive: true,
    riskNote:
        'This can save, update, or delete an encrypted draft. Review the requesting app and draft tags before signing.',
    emptyContentPreview: 'Draft deletion marker with empty content.',
    nonEmptyContentPreview: 'Encrypted draft payload',
  ),
};
