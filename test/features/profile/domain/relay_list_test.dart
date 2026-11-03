import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/domain/relay_list.dart';
import 'package:symudol/features/profile/domain/replaceable_event.dart';

/// An identity's NIP-65 relay list (diogel-io/symudol#88).
void main() {
  const a = 'wss://a.example.com';
  const b = 'wss://b.example.com';
  const c = 'wss://c.example.com';

  group('relayListFromTags', () {
    test('reads markers: none is both', () {
      expect(
        relayListFromTags([
          ['r', a],
          ['r', b, 'read'],
          ['r', c, 'write'],
        ]),
        const [
          RelayListEntry(a),
          RelayListEntry(b, write: false),
          RelayListEntry(c, read: false),
        ],
      );
    });

    test('normalises URLs and merges a relay listed twice', () {
      expect(
        relayListFromTags([
          ['r', 'WSS://A.example.com/', 'read'],
          ['r', a, 'write'],
          ['p', 'f' * 64],
          ['r', 'https://not-a-relay.example'],
          ['r'],
        ]),
        const [RelayListEntry(a)],
      );
    });

    test('keeps every relay, past the lookup bound', () {
      final tags = [
        for (var i = 0; i < 12; i++) ['r', 'wss://r$i.example.com'],
      ];

      expect(relayListFromTags(tags), hasLength(12));
    });
  });

  test('relayListTags writes markers and keeps other tags', () {
    expect(
      relayListTags(
        const [
          RelayListEntry(a),
          RelayListEntry(b, write: false),
          RelayListEntry(c, read: false),
        ],
        otherTags: nonRelayTags([
          ['r', a],
          ['alt', 'relay list'],
        ]),
      ),
      [
        ['r', a],
        ['r', b, 'read'],
        ['r', c, 'write'],
        ['alt', 'relay list'],
      ],
    );
  });

  group('parseRelayInput', () {
    test('assumes wss:// and normalises', () {
      expect(parseRelayInput(' Relay.Example.com '), 'wss://relay.example.com');
      expect(
        parseRelayInput('wss://relay.example.com/'),
        'wss://relay.example.com',
      );
    });

    test('refuses ws:// unless allowed', () {
      expect(
        parseRelayInput('ws://10.0.2.2:10547', allowInsecure: false),
        isNull,
      );
      expect(
        parseRelayInput('ws://10.0.2.2:10547', allowInsecure: true),
        'ws://10.0.2.2:10547',
      );
    });

    test('refuses what is not a relay address', () {
      expect(parseRelayInput(''), isNull);
      expect(parseRelayInput('https://relay.example.com'), isNull);
      expect(parseRelayInput('wss://'), isNull);
    });
  });

  group('applyRelayEdits', () {
    test('keeps a change another app made to a relay the user left', () {
      const loaded = [RelayListEntry(a), RelayListEntry(b)];
      // The user removes b and adds c; another app made a read-only.
      const edited = [RelayListEntry(a), RelayListEntry(c)];
      const latest = [RelayListEntry(a, write: false), RelayListEntry(b)];

      expect(applyRelayEdits(latest, loaded, edited), const [
        RelayListEntry(a, write: false),
        RelayListEntry(c),
      ]);
    });

    test('keeps a relay another app added, and the user\'s marker edit', () {
      const loaded = [RelayListEntry(a)];
      const edited = [RelayListEntry(a, read: false)];
      const latest = [RelayListEntry(a), RelayListEntry(b)];

      expect(applyRelayEdits(latest, loaded, edited), const [
        RelayListEntry(a, read: false),
        RelayListEntry(b),
      ]);
    });

    test(
      'a relay another app removed stays removed unless the user edited it',
      () {
        const loaded = [RelayListEntry(a), RelayListEntry(b)];
        const edited = [RelayListEntry(a), RelayListEntry(b, write: false)];
        const latest = <RelayListEntry>[];

        expect(applyRelayEdits(latest, loaded, edited), const [
          RelayListEntry(b, write: false),
        ]);
        expect(applyRelayEdits(latest, loaded, loaded), isEmpty);
      },
    );
  });

  group('createdAfter', () {
    final now = DateTime.utc(2026, 11, 3, 12, 0, 0, 500);

    test('is now, to the second, when the old event is older', () {
      final second = DateTime.utc(2026, 11, 3, 12).millisecondsSinceEpoch;

      expect(
        createdAfter(
          DateTime.utc(2026, 11, 3),
          now: now,
        ).millisecondsSinceEpoch,
        second,
      );
      expect(createdAfter(null, now: now).millisecondsSinceEpoch, second);
    });

    test('is a second after an old event dated ahead of the clock', () {
      final ahead = DateTime.utc(2026, 11, 3, 12, 5);

      expect(
        createdAfter(ahead, now: now),
        ahead.add(const Duration(seconds: 1)),
      );
    });

    test('refuses when that is too far ahead for relays', () {
      expect(
        () => createdAfter(DateTime.utc(2026, 11, 3, 13), now: now),
        throwsA(isA<ReplaceableEventDateException>()),
      );
    });
  });
}
