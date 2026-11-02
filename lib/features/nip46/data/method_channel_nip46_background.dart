import 'dart:async';

import 'package:flutter/services.dart';
import 'package:symudol/app/diogel_log.dart';

import '../application/nip46_background.dart';

/// The Android foreground service and request notices, over the
/// `io.diogel.symudol/nip46_service` channel (`Nip46Background.kt`, #29).
///
/// Where nothing answers the channel, as in tests, every call does nothing.
class MethodChannelNip46Background
    implements Nip46Notifier, Nip46BackgroundService {
  static const _channel = MethodChannel('io.diogel.symudol/nip46_service');

  final _stopRequests = StreamController<void>.broadcast();

  MethodChannelNip46Background() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') _stopRequests.add(null);
    });
  }

  @override
  Stream<void> get stopRequests => _stopRequests.stream;

  @override
  Future<void> start() => _call('start');

  @override
  Future<void> stop() => _call('stop');

  @override
  Future<void> showHeldRequest(String sessionId) =>
      _call('showHeldRequest', {'sessionId': sessionId});

  @override
  Future<void> cancelHeldRequest(String sessionId) =>
      _call('cancelHeldRequest', {'sessionId': sessionId});

  /// Whether request notices can be shown (always true before Android 13).
  Future<bool> notificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsAllowed') ?? true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Shows Android's notification prompt when it has not been answered yet.
  Future<void> requestNotificationPermission() =>
      _call('requestNotificationPermission');

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No Android side, as in tests.
    } on PlatformException catch (e) {
      diogelLog('NIP-46 background: $method failed', error: e);
    }
  }
}
