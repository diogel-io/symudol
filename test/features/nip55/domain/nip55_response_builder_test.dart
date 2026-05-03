import 'dart:convert';
import 'dart:io';

import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/nip55/domain/nip55_incoming_request.dart';
import 'package:android_diogel/features/nip55/domain/nip55_method.dart';
import 'package:android_diogel/features/nip55/domain/nip55_response_builder.dart';
import 'package:android_diogel/features/nip55/domain/nip55_web_return_options.dart';
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

  test('browser callback returnType=event gzip returns Signer1 payload', () {
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-web',
      method: Nip55Method.signEvent,
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: Nip55WebReturnOptions(
        callbackUrl: Uri.parse('https://example.com/callback'),
        returnType: Nip55WebReturnType.event,
        compressionType: Nip55WebCompressionType.gzip,
      ),
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

    expect(extras['callbackUrl'], 'https://example.com/callback');
    expect(extras['copyToClipboard'], isNull);
    expect(extras['returnType'], 'event');
    expect(extras['compressionType'], 'gzip');
    final result = extras['result']! as String;
    expect(result, startsWith('Signer1'));
    final decoded = utf8.decode(
      GZipCodec().decode(base64Decode(result.substring('Signer1'.length))),
    );
    expect(jsonDecode(decoded)['sig'], 'signature');
  });

  test('browser flow without callback marks result for clipboard fallback', () {
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-web',
      method: Nip55Method.signEvent,
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: const Nip55WebReturnOptions(
        returnType: Nip55WebReturnType.event,
        isBrowserFlow: true,
      ),
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

    expect(extras['copyToClipboard'], isTrue);
    expect(extras['clipboardLabel'], 'NIP-55 signing result');
    expect(jsonDecode(extras['result']! as String)['sig'], 'signature');
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
