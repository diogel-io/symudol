import 'dart:async';

import 'package:flutter/services.dart';
import 'package:symudol/app/diogel_log.dart';

import '../application/nip46_link_handler.dart';

/// `nostrconnect:` links over the `io.diogel.symudol/nip46_links` channel
/// (`Nip46Links.kt`, #31).
///
/// Where nothing answers the channel, as in tests, there is never a link.
class MethodChannelNip46Links implements Nip46Links {
  static const _channel = MethodChannel('io.diogel.symudol/nip46_links');

  final _linkAvailable = StreamController<void>.broadcast();

  MethodChannelNip46Links() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'linkAvailable') _linkAvailable.add(null);
    });
  }

  @override
  Stream<void> get linkAvailable => _linkAvailable.stream;

  @override
  Future<String?> takeLink() async {
    try {
      return await _channel.invokeMethod<String>('takeLink');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      diogelLog('NIP-46 links: takeLink failed', error: e);
      return null;
    }
  }

  @override
  Future<void> setLinksEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setLinksEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // No Android side, as in tests.
    } on PlatformException catch (e) {
      diogelLog('NIP-46 links: setLinksEnabled failed', error: e);
    }
  }
}
