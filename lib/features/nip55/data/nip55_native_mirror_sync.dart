import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../domain/nip55_client_permission.dart';

/// Syncs NIP-55 permission grants to the native Kotlin side so that
/// [Nip55ContentProvider] can check remembered permissions synchronously
/// without going through the Flutter engine.
class Nip55NativeMirrorSync {
  static const _channel = MethodChannel('io.threenine.diogel/nip55');

  /// Sync the full grant list to the native SharedPreferences mirror.
  Future<void> syncGrants(List<Nip55PermissionGrant> grants) async {
    try {
      final payload = jsonEncode(grants.map((g) => g.toJson()).toList());
      debugPrint('Nip55NativeMirrorSync: syncing ${grants.length} grants (${payload.length} bytes)');
      await _channel.invokeMethod<void>('syncNip55PermissionGrants', payload);
      debugPrint('Nip55NativeMirrorSync: sync complete');
    } catch (e) {
      debugPrint('Nip55NativeMirrorSync: FAILED to sync grants: $e');
      dev.log('Nip55NativeMirrorSync: failed to sync grants: $e', name: 'Diogel');
    }
  }

  /// Set the active identity's public key in the native mirror
  /// so ContentProvider can check currentUser matching.
  Future<void> setActiveIdentityPubkey(String? pubkey) async {
    try {
      await _channel.invokeMethod<void>('setNip55ActiveIdentityPubkey', pubkey ?? '');
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to set active pubkey: $e', name: 'Diogel');
    }
  }

  /// Set the active identity's private key in the native crypto bridge
  /// so ContentProvider can perform native crypto operations.
  Future<void> setActiveKey({
    required String privateKey,
    required String publicKey,
    required String localId,
  }) async {
    try {
      await _channel.invokeMethod<void>('setNip55ActiveKey', {
        'privateKey': privateKey,
        'publicKey': publicKey,
        'localId': localId,
      });
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to set active key: $e', name: 'Diogel');
    }
  }

  /// Clear the active key from the native crypto bridge
  /// (called when the vault locks).
  Future<void> clearActiveKey() async {
    try {
      await _channel.invokeMethod<void>('clearNip55ActiveKey');
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to clear active key: $e', name: 'Diogel');
    }
  }
}