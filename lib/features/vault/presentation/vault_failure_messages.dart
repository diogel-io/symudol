import '../domain/vault_failure.dart';

String vaultFailureMessage(VaultFailure failure) {
  if (failure is VaultLockedFailure) {
    return 'Vault is locked. Please unlock it first.';
  }
  if (failure is InvalidPrivateKeyFailure) {
    return 'Invalid nsec key format';
  }
  if (failure is UnsupportedKeyFormatFailure) {
    return 'Invalid private key format';
  }
  if (failure is DuplicateIdentityFailure) {
    return 'This identity already exists in your vault.';
  }
  if (failure is VaultNotFoundFailure) {
    return 'Vault not found.';
  }
  if (failure is VaultAlreadyExistsFailure) {
    return 'A vault already exists on this device.';
  }
  if (failure is InvalidPinFailure) {
    return 'Invalid PIN. Please try again.';
  }
  if (failure is VaultLockedOutFailure) {
    return lockoutMessage(failure.remaining);
  }
  if (failure is VaultWipedFailure) {
    return 'Too many failed PIN attempts. Symudol erased all keys.';
  }
  if (failure is VaultWipeIncompleteFailure) {
    return 'The wipe did not finish. Please try again.';
  }
  if (failure is IdentityNotFoundFailure) {
    return 'The requested identity was not found.';
  }
  if (failure is SecureStorageFailure) {
    return 'A storage error occurred. Please try again.';
  }
  if (failure is CryptoFailure) {
    return 'An encryption error occurred.';
  }
  
  return failure.message;
}

/// "Too many failed attempts. Try again in 15 minutes." (#16)
String lockoutMessage(Duration remaining) =>
    'Too many failed attempts. Try again in ${formatLockoutWait(remaining)}.';

/// [remaining] rounded up to whole seconds, minutes or hours.
String formatLockoutWait(Duration remaining) {
  String unit(int count, String name) => '$count $name${count == 1 ? '' : 's'}';
  final seconds = (remaining.inMilliseconds / 1000).ceil();
  if (seconds < 60) return unit(seconds < 1 ? 1 : seconds, 'second');
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return unit(minutes, 'minute');
  return unit((seconds / 3600).ceil(), 'hour');
}

/// The countdown shown while locked out, as m:ss or h:mm:ss.
String formatLockoutCountdown(Duration remaining) {
  final total = (remaining.inMilliseconds / 1000).ceil();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  return '$minutes:$seconds';
}

/// The warning shown from 3 attempts before an erase, or `null` (#16).
String? wipeWarningMessage({
  required int failedAttempts,
  required int? wipeAfterFailures,
}) {
  if (wipeAfterFailures == null) return null;
  final left = wipeAfterFailures - failedAttempts;
  if (left < 1 || left > 3) return null;
  return '$left ${left == 1 ? 'attempt' : 'attempts'} left before Symudol '
      'erases all keys.';
}
