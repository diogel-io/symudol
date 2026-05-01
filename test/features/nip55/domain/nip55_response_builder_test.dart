import 'dart:convert';

import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_response_builder.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = Nip55ResponseBuilder();

  test('returns exact NIP-55 extras for sign_event', () {
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-1',
      method: Nip55Method.signEvent,
      externalId: 'external-id',
      receivedAt: DateTime.utc(2026, 5, 1),
    );
    const event = SignedNostrEvent(
      id: 'event-id',
      pubkey: 'pubkey',
      createdAt: 1777618800,
      kind: 1,
      tags: [],
      content: 'hello',
      sig: 'signature',
    );

    final extras = builder.signEventExtras(
      incoming: incoming,
      signedEvent: event,
    );

    expect(extras['result'], 'signature');
    expect(extras['id'], 'external-id');
    final eventJson =
        jsonDecode(extras['event']! as String) as Map<String, dynamic>;
    expect(eventJson['id'], 'event-id');
    expect(eventJson['pubkey'], 'pubkey');
    expect(eventJson['sig'], 'signature');
  });

  test('returns exact NIP-55 extras for get_public_key', () {
    final identity = VaultIdentity(
      localId: 'local',
      publicKey: 'a' * 64,
      createdAt: DateTime.utc(2026, 5, 1),
      origin: IdentityOrigin.generated,
    );

    final extras = builder.getPublicKeyExtras(identity);

    expect(extras, {
      'result': identity.publicKey,
      'package': 'io.threenine.androidiogel',
    });
  });
}
