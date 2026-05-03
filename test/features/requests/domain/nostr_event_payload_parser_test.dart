import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = NostrEventPayloadParser();

  test('labels common Nostr event kinds', () {
    expect(parser.kindLabel(0), 'Metadata/profile');
    expect(parser.kindLabel(1), 'Text note');
    expect(parser.kindLabel(3), 'Contact list');
    expect(parser.kindLabel(4), 'Legacy encrypted DM / NIP-04');
    expect(parser.kindLabel(9735), 'Zap receipt');
    expect(parser.kindLabel(22242), 'Client authentication');
  });

  test('unknown kind is bluntly flagged', () {
    final review = parser.review({
      'kind': 31337,
      'content': 'custom payload',
      'tags': [],
    });

    expect(
      review.kindLabel,
      'Unknown event kind. Review carefully before signing.',
    );
    expect(
      review.riskNote,
      'Unknown event kind. Review carefully before signing.',
    );
    expect(review.isUnknownKind, isTrue);
  });

  test('summarises content, tags, and remembered permission', () {
    final review = parser.review({
      'kind': 1,
      'content': 'Hello\nNostr',
      'tags': [
        ['p', 'pubkey'],
        ['e', 'event'],
        ['p', 'other'],
      ],
      'nip55PermissionScope': 'sign_event:1',
    });

    expect(review.contentPreview, 'Hello Nostr');
    expect(review.tagsSummary, '3 tag(s): p:2, e:1');
    expect(review.permissionLabel, 'Remember permission: sign kind 1 only');
    expect(review.riskNote, contains('public text note'));
  });

  test('broad sign_event permission is visually sensitive', () {
    final review = parser.review({
      'kind': 1,
      'content': 'Hello',
      'nip55PermissionScope': 'sign_event',
    });

    expect(review.isBroadPermission, isTrue);
    expect(review.isSensitive, isTrue);
    expect(review.permissionLabel, contains('broad permission'));
    expect(review.riskNote, contains('Broad sign_event permission'));
  });
}
