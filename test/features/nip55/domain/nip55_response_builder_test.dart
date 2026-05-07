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
    final event = SignedNostrEvent(
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

    expect(extras['signature'], 'signature');
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
    final event = SignedNostrEvent(
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
    final event = SignedNostrEvent(
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

  test('browser crypto callback returns generic operation result extras', () {
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-crypto-web',
      method: Nip55Method.nip44Encrypt,
      externalId: 'caller-id',
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: Nip55WebReturnOptions(
        callbackUrl: Uri.parse('https://example.com/callback'),
      ),
    );

    final extras = builder.operationResultExtras(
      incoming: incoming,
      result: 'encrypted-payload',
    );

    expect(extras['signature'], 'encrypted-payload');
    expect(extras['result'], 'encrypted-payload');
    expect(extras['id'], 'caller-id');
    expect(extras['callbackUrl'], 'https://example.com/callback');
    expect(extras['copyToClipboard'], isNull);
    expect(extras['returnType'], 'signature');
    expect(extras['compressionType'], 'none');
  });

  test('browser crypto flow without callback marks sensitive clipboard label', () {
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-crypto-web',
      method: Nip55Method.nip44Decrypt,
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: const Nip55WebReturnOptions(isBrowserFlow: true),
    );

    final extras = builder.operationResultExtras(
      incoming: incoming,
      result: 'plaintext secret',
      clipboardLabel: 'Sensitive NIP-55 result',
    );

    expect(extras['result'], 'plaintext secret');
    expect(extras['copyToClipboard'], isTrue);
    expect(extras['clipboardLabel'], 'Sensitive NIP-55 result');
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
      'package': 'io.threenine.diogel',
    });
  });

  test('browser get_public_key callback includes callback result metadata', () {
    final identity = VaultIdentity(
      localId: 'local',
      publicKey: 'a' * 64,
      createdAt: DateTime.utc(2026, 5, 1),
      origin: IdentityOrigin.generated,
    );
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-pk-web',
      method: Nip55Method.getPublicKey,
      externalId: 'caller-id',
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: Nip55WebReturnOptions(
        callbackUrl: Uri.parse('https://example.com/callback'),
      ),
    );

    final extras = builder.getPublicKeyExtras(identity, incoming: incoming);

    expect(extras['result'], identity.publicKey);
    expect(extras['id'], 'caller-id');
    expect(extras['callbackUrl'], 'https://example.com/callback');
    expect(extras['copyToClipboard'], isNull);
  });

  test('browser get_public_key without callback marks clipboard fallback', () {
    final identity = VaultIdentity(
      localId: 'local',
      publicKey: 'a' * 64,
      createdAt: DateTime.utc(2026, 5, 1),
      origin: IdentityOrigin.generated,
    );
    final incoming = Nip55IncomingRequest(
      localId: 'local',
      requestToken: 'token-pk-web',
      method: Nip55Method.getPublicKey,
      receivedAt: DateTime.utc(2026, 5, 1),
      webReturnOptions: const Nip55WebReturnOptions(isBrowserFlow: true),
    );

    final extras = builder.getPublicKeyExtras(identity, incoming: incoming);

    expect(extras['copyToClipboard'], isTrue);
    expect(extras['clipboardLabel'], 'NIP-55 public key result');
  });
}
