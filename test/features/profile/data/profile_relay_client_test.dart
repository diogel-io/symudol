import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/data/profile_relay_client.dart';

/// dart_nostr passes on whatever relays send, so the client checks each
/// event itself (diogel-io/symudol#42).
void main() {
  final keys = NostrKeyPairs.generate();
  final signed = NostrEvent.fromPartialData(
    kind: 0,
    content: '{"name":"alice"}',
    keyPairs: keys,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );

  NostrEvent copy({String? content, String? pubkey, String? sig}) => NostrEvent(
    id: signed.id,
    kind: signed.kind,
    content: content ?? signed.content,
    sig: sig ?? signed.sig,
    pubkey: pubkey ?? signed.pubkey,
    createdAt: signed.createdAt,
    tags: signed.tags,
  );

  test('a correctly signed event is authentic', () {
    expect(DartNostrProfileRelayClient.isAuthentic(signed), isTrue);
  });

  test('changed content does not match the id', () {
    expect(
      DartNostrProfileRelayClient.isAuthentic(copy(content: '{"name":"eve"}')),
      isFalse,
    );
  });

  test('another key cannot claim the event', () {
    final other = NostrKeyPairs.generate().public;
    expect(
      DartNostrProfileRelayClient.isAuthentic(copy(pubkey: other)),
      isFalse,
    );
  });

  test('a malformed signature is rejected', () {
    expect(DartNostrProfileRelayClient.isAuthentic(copy(sig: 'zz')), isFalse);
  });
}
