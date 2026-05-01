import 'package:flutter/services.dart';

abstract interface class Nip55Gateway {
  void setIncomingIntentHandler(
    void Function(Map<String, Object?> raw)? handler,
  );

  Future<Map<String, Object?>?> getInitialNip55Intent();

  Future<Map<String, Object?>?> consumeLatestNip55Intent();

  Future<void> completeNip55Intent({
    required String requestToken,
    required Map<String, Object?> extras,
  });

  Future<void> rejectNip55Intent({required String requestToken, String? error});
}

class Nip55MethodChannelGateway implements Nip55Gateway {
  static const channelName = 'io.threenine.androidiogel/nip55';
  final MethodChannel _channel;
  void Function(Map<String, Object?> raw)? _handler;

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

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNip55Intent') {
      final raw = _castMap(call.arguments);
      if (raw != null) _handler?.call(raw);
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
