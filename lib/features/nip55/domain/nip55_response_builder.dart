import 'dart:convert';

import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';

import 'nip55_incoming_request.dart';

class Nip55ResponseBuilder {
  static const signerPackage = 'io.threenine.androidiogel';

  const Nip55ResponseBuilder();

  Map<String, Object?> signEventExtras({
    required Nip55IncomingRequest incoming,
    required SignedNostrEvent signedEvent,
  }) {
    return {
      'result': signedEvent.sig,
      if (incoming.externalId != null) 'id': incoming.externalId,
      'event': jsonEncode(signedEvent.toJson()),
    };
  }

  Map<String, Object?> getPublicKeyExtras(VaultIdentity identity) {
    return {'result': identity.publicKey, 'package': signerPackage};
  }
}
