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

  group('fallback kind labels (NIP-01 ranges)', () {
    test('unregistered addressable kind uses range label', () {
      final review = parser.review({
        'kind': 31337,
        'content': 'custom payload',
        'tags': [],
      });

      expect(review.kindLabel, 'Addressable Nostr event kind 31337');
      expect(review.isUnknownKind, isTrue);
    });

    test('fallback risk note does not contain Unknown event kind', () {
      final review = parser.review({
        'kind': 31337,
        'content': 'custom payload',
        'tags': [],
      });

      expect(review.riskNote, isNot(contains('Unknown event kind')));
      expect(review.riskNote, contains('addressable'));
    });

    test('unregistered regular kind uses range label', () {
      expect(parser.kindLabel(5000), 'Regular Nostr event kind 5000');
    });

    test('unregistered ephemeral kind uses range label', () {
      expect(parser.kindLabel(25000), 'Ephemeral Nostr event kind 25000');
    });

    test('invalid negative kind label', () {
      expect(parser.kindLabel(-1), 'Invalid event kind');
    });

    test('alt tag surfaced for unregistered kind with empty content', () {
      final review = parser.review({
        'kind': 31337,
        'content': '',
        'tags': [
          ['alt', 'Custom community event'],
        ],
      });

      expect(review.contentPreview, 'Alt: Custom community event');
    });
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

  group('kind 31234 (NIP-37 Draft Wrap)', () {
    test('kindLabel returns Draft wrap / NIP-37', () {
      expect(parser.kindLabel(31234), 'Draft wrap / NIP-37');
    });

    test('review is not unknown kind', () {
      final review = parser.review({
        'kind': 31234,
        'content': 'encrypted-payload',
        'tags': [],
      });

      expect(review.isUnknownKind, isFalse);
    });

    test('review is sensitive', () {
      final review = parser.review({
        'kind': 31234,
        'content': 'encrypted-payload',
        'tags': [],
      });

      expect(review.isSensitive, isTrue);
    });

    test('riskNote mentions encrypted draft', () {
      final review = parser.review({
        'kind': 31234,
        'content': 'encrypted-payload',
        'tags': [],
      });

      expect(review.riskNote, contains('encrypted draft'));
      expect(review.riskNote, isNot(contains('Unknown event kind')));
    });

    test('non-empty content preview is Encrypted draft payload', () {
      final review = parser.review({
        'kind': 31234,
        'content': 'encrypted-payload',
        'tags': [],
      });

      expect(review.contentPreview, 'Encrypted draft payload');
    });

    test('empty content preview is Draft deletion marker with empty content.', () {
      final review = parser.review({
        'kind': 31234,
        'content': '',
        'tags': [],
      });

      expect(review.contentPreview, 'Draft deletion marker with empty content.');
    });

    test('permission label for sign_event:31234', () {
      final review = parser.review({
        'kind': 31234,
        'content': 'encrypted-payload',
        'nip55PermissionScope': 'sign_event:31234',
        'tags': [],
      });

      expect(
        review.permissionLabel,
        'Remember permission: sign kind 31234 only',
      );
    });
  });

  group('kind 5 (NIP-09 Event Deletion Request)', () {
    test('kindLabel returns Event deletion request / NIP-09', () {
      expect(parser.kindLabel(5), 'Event deletion request / NIP-09');
    });

    test('review is not unknown kind', () {
      final review = parser.review({
        'kind': 5,
        'content': '',
        'tags': [
          ['e', 'event-id'],
          ['k', '1'],
        ],
      });

      expect(review.isUnknownKind, isFalse);
    });

    test('review is sensitive', () {
      final review = parser.review({
        'kind': 5,
        'content': '',
        'tags': [],
      });

      expect(review.isSensitive, isTrue);
    });

    test('risk note mentions delete or hide referenced events', () {
      final review = parser.review({
        'kind': 5,
        'content': '',
        'tags': [],
      });

      expect(review.riskNote, contains('delete or hide referenced events'));
      expect(review.riskNote, isNot(contains('Unknown event kind')));
    });

    test('empty content preview is Deletion request with no reason text.', () {
      final review = parser.review({
        'kind': 5,
        'content': '',
        'tags': [],
      });

      expect(review.contentPreview, 'Deletion request with no reason text.');
    });

    test('permission label for sign_event:5', () {
      final review = parser.review({
        'kind': 5,
        'content': '',
        'nip55PermissionScope': 'sign_event:5',
        'tags': [
          ['e', 'event-id'],
          ['k', '1'],
        ],
      });

      expect(review.permissionLabel, 'Remember permission: sign kind 5 only');
    });
  });
}
