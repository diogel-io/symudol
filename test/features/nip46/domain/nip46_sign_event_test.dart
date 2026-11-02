import 'dart:convert';

import 'package:symudol/features/nip46/domain/nip46_sign_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final active = 'a1' * 32;
  final fixedNow = DateTime.utc(2026, 11, 2, 12);

  Nip46SignEvent parse(Object? event) => Nip46SignEvent.parse(
    event is String ? event : jsonEncode(event),
    activePubkey: active,
    now: () => fixedNow,
  );

  group('Nip46SignEvent (#27)', () {
    test('a missing or non-object event is refused', () {
      expect(
        () => Nip46SignEvent.parse(null, activePubkey: active),
        throwsA(
          isA<Nip46SignEventException>().having(
            (e) => e.message,
            'message',
            'sign_event: missing event JSON',
          ),
        ),
      );
      for (final raw in ['not json', '[1, 2]', '"text"']) {
        expect(
          () => parse(raw),
          throwsA(
            isA<Nip46SignEventException>().having(
              (e) => e.message,
              'message',
              'sign_event: invalid event JSON',
            ),
          ),
          reason: raw,
        );
      }
    });

    test('the review shows exactly what is signed', () {
      final event = parse({
        'kind': 7,
        'content': '+',
        'tags': [
          ['e', 'abc'],
          ['p', 42],
          'not a tag',
        ],
        'created_at': 1700000000,
        'nip55Method': 'get_public_key',
        'permissionWarnings': ['Symudol has verified this app'],
      });

      expect(event.draft.kind, 7);
      expect(event.draft.content, '+');
      expect(event.draft.tags, [
        ['e', 'abc'],
        ['p', '42'],
      ]);
      expect(event.draft.createdAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(event.reviewPayload, {
        'pubkey': active,
        'kind': 7,
        'content': '+',
        'tags': [
          ['e', 'abc'],
          ['p', '42'],
        ],
        'created_at': 1700000000,
      });
    });

    test('missing fields get the defaults they are signed with', () {
      final event = parse({'content': 5});

      expect(event.pubkey, active);
      expect(event.draft.kind, 1);
      expect(event.draft.content, '');
      expect(event.draft.tags, isEmpty);
      expect(event.draft.createdAt, fixedNow);
      expect(event.hasCreatedAt, isFalse);
      expect(event.reviewPayload.containsKey('created_at'), isFalse);
    });

    test('a created_at DateTime cannot hold is refused', () {
      for (final createdAt in [-1, 8640000000001, 9000000000000000]) {
        expect(
          () => parse({'kind': 1, 'created_at': createdAt}),
          throwsA(
            isA<Nip46SignEventException>().having(
              (e) => e.message,
              'message',
              'sign_event: invalid created_at',
            ),
          ),
          reason: '$createdAt',
        );
      }
      expect(
        parse({'kind': 1, 'created_at': 8640000000000}).draft.createdAt,
        DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
      );
    });

    test("keeps the client's pubkey so a mismatch can be refused", () {
      expect(parse({'pubkey': 'b2' * 32, 'kind': 1}).pubkey, 'b2' * 32);
    });
  });
}
