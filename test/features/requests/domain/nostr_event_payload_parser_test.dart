import 'package:android_diogel/features/requests/domain/nostr_event_payload_parser.dart';
import 'package:android_diogel/features/requests/domain/request_provenance.dart';
import 'package:android_diogel/features/requests/domain/request_trust_status.dart';
import 'package:android_diogel/features/requests/domain/signing_action_type.dart';
import 'package:android_diogel/features/requests/domain/signing_request.dart';
import 'package:android_diogel/features/requests/domain/signing_request_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = NostrEventPayloadParser();
  final createdAt = DateTime.utc(2026, 5, 1, 7, 30);

  SigningRequest requestWith(
    Map<String, Object?> payload, {
    int eventKind = 1,
  }) {
    return SigningRequest(
      id: 'req1',
      provenance: const RequestProvenance(
        sourceDisplayName: 'Test App',
        trustStatus: RequestTrustStatus.unknown,
      ),
      actionType: SigningActionType.signEvent,
      eventKind: eventKind,
      eventPayload: payload,
      targetIdentityPublicKey: 'pubkey',
      targetIdentityLocalId: 'local',
      createdAt: createdAt,
      status: SigningRequestStatus.pending,
    );
  }

  group('NostrEventPayloadParser', () {
    test('parses a valid request payload', () {
      final draft = parser.parse(
        requestWith({
          'kind': 1,
          'content': 'hello',
          'created_at': 1777618800,
          'tags': [
            ['p', 'abc'],
          ],
        }),
      );

      expect(draft.kind, 1);
      expect(draft.content, 'hello');
      expect(draft.tags, [
        ['p', 'abc'],
      ]);
      expect(draft.createdAt.millisecondsSinceEpoch ~/ 1000, 1777618800);
    });

    test('uses request creation time when created_at is missing', () {
      final draft = parser.parse(
        requestWith({'kind': 1, 'content': 'hello', 'tags': []}),
      );

      expect(draft.createdAt, createdAt);
    });

    test('rejects malformed kind', () {
      expect(
        () => parser.parse(requestWith({'kind': '1', 'content': 'hello'})),
        throwsA(isA<NostrEventPayloadParseException>()),
      );
    });

    test('rejects payload kind that differs from displayed request kind', () {
      expect(
        () => parser.parse(requestWith({'kind': 5, 'content': 'hello'})),
        throwsA(isA<NostrEventPayloadParseException>()),
      );
    });

    test('uses request kind when payload kind is missing', () {
      final draft = parser.parse(requestWith({'content': 'hello'}));

      expect(draft.kind, 1);
    });

    test('rejects event kind below NIP-01 range', () {
      expect(
        () => parser.parse(requestWith({'content': 'hello'}, eventKind: -1)),
        throwsA(isA<NostrEventPayloadParseException>()),
      );
    });

    test('rejects event kind above NIP-01 range', () {
      expect(
        () => parser.parse(requestWith({'content': 'hello'}, eventKind: 65536)),
        throwsA(isA<NostrEventPayloadParseException>()),
      );
    });

    test('rejects malformed tags', () {
      expect(
        () => parser.parse(
          requestWith({
            'kind': 1,
            'content': 'hello',
            'tags': [
              ['p', 123],
            ],
          }),
        ),
        throwsA(isA<NostrEventPayloadParseException>()),
      );
    });

    test('ignores incoming id sig and pubkey', () {
      final draft = parser.parse(
        requestWith({
          'kind': 1,
          'content': 'hello',
          'tags': [],
          'id': 'attacker-id',
          'sig': 'attacker-sig',
          'pubkey': 'attacker-pubkey',
        }),
      );

      expect(draft.kind, 1);
      expect(draft.content, 'hello');
    });
  });
}
