import 'dart:convert';

import 'package:symudol/app/diogel_log.dart';
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
      diogelLog('Nip55NativeMirrorSync: syncing ${grants.length} grants (${payload.length} bytes)');
      await _channel.invokeMethod<void>('syncNip55PermissionGrants', payload);
      diogelLog('Nip55NativeMirrorSync: sync complete');
    } catch (e) {
      diogelLog('Nip55NativeMirrorSync: failed to sync grants', error: e);
    }
  }

  /// Set the active identity's public key in the native mirror
  /// so ContentProvider can check currentUser matching.
  Future<void> setActiveIdentityPubkey(String? pubkey) async {
    try {
      await _channel.invokeMethod<void>('setNip55ActiveIdentityPubkey', pubkey ?? '');
    } catch (e) {
      diogelLog('Nip55NativeMirrorSync: failed to set active pubkey', error: e);
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
      diogelLog('Nip55NativeMirrorSync: failed to set active key', error: e);
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
      diogelLog('Nip55NativeMirrorSync: failed to set lock deadline', error: e);
    }
  }

  /// The app is in the foreground again: the native key has no deadline.
  Future<void> clearLockDeadline() async {
    try {
      await _channel.invokeMethod<void>('clearNip55LockDeadline');
    } catch (e) {
      diogelLog('Nip55NativeMirrorSync: failed to clear lock deadline', error: e);
    }
  }

  /// Erase all native NIP-55 state for a vault wipe (#20): the active key and
  /// its lock deadline, the permission mirror (grants and active pubkey) and
  /// the legacy remembered rejects.
  ///
  /// Unlike the other calls here this rethrows, so the wipe can report that
  /// it did not finish. A build with no native side has nothing to wipe.
  Future<void> wipeNativeState() async {
    try {
      await _channel.invokeMethod<void>('wipeNip55NativeState');
    } on MissingPluginException {
      diogelLog('Nip55NativeMirrorSync: no native side, nothing to wipe');
    }
  }

  /// Clear the active key from the native crypto bridge
  /// (called when the vault locks).
  Future<void> clearActiveKey() async {
    try {
      await _channel.invokeMethod<void>('clearNip55ActiveKey');
    } catch (e) {
      diogelLog('Nip55NativeMirrorSync: failed to clear active key', error: e);
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
