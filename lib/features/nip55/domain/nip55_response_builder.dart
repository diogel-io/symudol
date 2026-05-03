import 'dart:convert';
import 'dart:io';

import 'package:android_diogel/features/identity/domain/vault_identity.dart';
import 'package:android_diogel/features/requests/domain/signed_nostr_event.dart';

import 'nip55_incoming_request.dart';
import 'nip55_web_return_options.dart';

class Nip55ResponseBuilder {
  static const signerPackage = 'io.threenine.androidiogel';

  const Nip55ResponseBuilder();

  Map<String, Object?> signEventExtras({
    required Nip55IncomingRequest incoming,
    required SignedNostrEvent signedEvent,
  }) {
    final eventJson = jsonEncode(signedEvent.toJson());
    final webPayload = _webPayload(
      incoming.webReturnOptions,
      signedEvent.sig,
      eventJson,
    );
    return {
      'result': webPayload.result,
      if (incoming.externalId != null) 'id': incoming.externalId,
      'event': eventJson,
      if (webPayload.callbackUrl != null) 'callbackUrl': webPayload.callbackUrl,
      if (webPayload.copyToClipboard) 'copyToClipboard': true,
      if (webPayload.clipboardLabel != null)
        'clipboardLabel': webPayload.clipboardLabel,
      if (webPayload.returnType != null) 'returnType': webPayload.returnType,
      if (webPayload.compressionType != null)
        'compressionType': webPayload.compressionType,
    };
  }

  Map<String, Object?> getPublicKeyExtras(VaultIdentity identity) {
    return {'result': identity.publicKey, 'package': signerPackage};
  }

  Map<String, Object?> operationResultExtras({
    required Nip55IncomingRequest incoming,
    required String result,
    String clipboardLabel = 'NIP-55 result',
  }) {
    return {
      'result': result,
      if (incoming.externalId != null) 'id': incoming.externalId,
      if (incoming.webReturnOptions.callbackUrl != null)
        'callbackUrl': incoming.webReturnOptions.callbackUrl.toString(),
      if (incoming.webReturnOptions.isBrowserFlow &&
          !incoming.webReturnOptions.hasCallback)
        'copyToClipboard': true,
      if (incoming.webReturnOptions.isBrowserFlow &&
          !incoming.webReturnOptions.hasCallback)
        'clipboardLabel': clipboardLabel,
      'returnType': incoming.webReturnOptions.returnType.name,
      'compressionType': incoming.webReturnOptions.compressionType.name,
    };
  }

  _WebPayload _webPayload(
    Nip55WebReturnOptions options,
    String signature,
    String eventJson,
  ) {
    final result = switch (options.returnType) {
      Nip55WebReturnType.signature => signature,
      Nip55WebReturnType.event => switch (options.compressionType) {
        Nip55WebCompressionType.none => eventJson,
        Nip55WebCompressionType.gzip =>
          'Signer1${base64Encode(GZipCodec().encode(utf8.encode(eventJson)))}',
      },
    };
    return _WebPayload(
      result: result,
      callbackUrl: options.callbackUrl?.toString(),
      copyToClipboard: options.isBrowserFlow && !options.hasCallback,
      clipboardLabel: options.isBrowserFlow && !options.hasCallback
          ? 'NIP-55 signing result'
          : null,
      returnType: options.returnType.name,
      compressionType: options.compressionType.name,
    );
  }
}

class _WebPayload {
  final String result;
  final String? callbackUrl;
  final bool copyToClipboard;
  final String? clipboardLabel;
  final String? returnType;
  final String? compressionType;

  const _WebPayload({
    required this.result,
    this.callbackUrl,
    this.copyToClipboard = false,
    this.clipboardLabel,
    this.returnType,
    this.compressionType,
  });
}
