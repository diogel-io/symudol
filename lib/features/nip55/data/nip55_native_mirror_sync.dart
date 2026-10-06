import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../domain/nip55_client_permission.dart';

/// Syncs NIP-55 permission grants to the native Kotlin side so that
/// [Nip55ContentProvider] can check remembered permissions synchronously
/// without going through the Flutter engine.
class Nip55NativeMirrorSync {
  static const _channel = MethodChannel('io.diogel.symudol/nip55');

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
    // Sent as raw bytes, which arrive as a byte[] the native side can zero,
    // never as a JVM String (#9).
    final keyBytes = hexToKeyBytes(privateKey);
    try {
      await _channel.invokeMethod<void>('setNip55ActiveKey', {
        'privateKey': keyBytes,
        'publicKey': publicKey,
        'localId': localId,
      });
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to set active key: $e', name: 'Diogel');
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  /// Have the native side clear the key after [delay], unless
  /// [clearLockDeadline] is called first. Holds without the Flutter engine.
  Future<void> setLockDeadline(Duration delay) async {
    try {
      await _channel.invokeMethod<void>(
        'setNip55LockDeadline',
        delay.inMilliseconds,
      );
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to set lock deadline: $e', name: 'Diogel');
    }
  }

  /// The app is in the foreground again: the native key has no deadline.
  Future<void> clearLockDeadline() async {
    try {
      await _channel.invokeMethod<void>('clearNip55LockDeadline');
    } catch (e) {
      dev.log('Nip55NativeMirrorSync: failed to clear lock deadline: $e', name: 'Diogel');
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

/// The 32 bytes of a 64-character hex private key.
@visibleForTesting
Uint8List hexToKeyBytes(String hex) {
  if (hex.length != 64) {
    throw ArgumentError('A private key is 64 hex characters');
  }
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
