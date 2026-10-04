import 'package:flutter/services.dart';

abstract interface class Nip55Gateway {
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  );

  void setProviderQueryHandler(
    Future<Map<String, Object?>?> Function(Map<String, Object?> raw)? handler,
  );

  Future<Map<String, Object?>?> getInitialNip55Intent();

  Future<Map<String, Object?>?> consumeLatestNip55Intent();

  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  });

  Future<void> rejectNip55Intent({required String requestToken, String? error});

  Future<Uint8List?> getAppIcon(String packageName);
}

class Nip55MethodChannelGateway implements Nip55Gateway {
  static const channelName = 'io.diogel.symudol/nip55';
  final MethodChannel _channel;
  void Function(Map<String, Object?> raw)? _handler;
  Future<Map<String, Object?>?> Function(Map<String, Object?> raw)?
  _providerQueryHandler;

  Nip55MethodChannelGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  ) {
    _handler = handler;
  }

  @override
  void setProviderQueryHandler(
    Future<Map<String, Object?>?> Function(Map<String, Object?> raw)? handler,
  ) {
    _providerQueryHandler = handler;
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNip55Intent') {
      final raw = _castMap(call.arguments);
      if (raw != null) _handler?.call(raw);
      return null;
    }
    if (call.method == 'handleNip55ProviderQuery') {
      final raw = _castMap(call.arguments);
      if (raw == null) return null;
      return _providerQueryHandler?.call(raw);
    }
    return null;
  }

  @override
  Future<Map<String, Object?>?> getInitialNip55Intent() async {
    final result = await _channel.invokeMethod<Object?>(
      'getInitialNip55Intent',
    );
    return _castMap(result);
  }

  @override
  Future<Map<String, Object?>?> consumeLatestNip55Intent() async {
    final result = await _channel.invokeMethod<Object?>(
      'consumeLatestNip55Intent',
    );
    return _castMap(result);
  }

  @override
  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  }) async {
    await _channel.invokeMethod<void>('completeNip55Intent', {
      'requestToken': requestToken,
      'resultCode': 'ok',
      'extras': extras,
    });
  }

  @override
  Future<void> rejectNip55Intent({
    required String requestToken,
    String? error,
  }) async {
    final arguments = <String, Object?>{'requestToken': requestToken};
    if (error != null) {
      arguments['error'] = error;
    }
    await _channel.invokeMethod<void>('rejectNip55Intent', arguments);
  }

  @override
  Future<Uint8List?> getAppIcon(String packageName) async {
    final result = await _channel.invokeMethod<Object?>(
      'getAppIcon',
      packageName,
    );
    if (result is Uint8List) return result;
    if (result is List<int>) return Uint8List.fromList(result);
    return null;
  }

  Map<String, Object?>? _castMap(Object? value) {
    if (value == null || value is! Map) return null;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        result[key] = entry.value;
      }
    }
    return result;
  }
}
