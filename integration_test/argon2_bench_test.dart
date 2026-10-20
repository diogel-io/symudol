// Times the PIN key derivation on a device, to choose
// VaultKdfParams.defaultParams (#16). Run it in profile mode, which is AOT
// like a release build:
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/argon2_bench_test.dart
//
// The figures are recorded in documentation/pin-protection.md. CI does not
// run this: `flutter test` only runs test/.
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:symudol/features/vault/data/pointycastle_vault_crypto_service.dart';
import 'package:symudol/features/vault/data/secure_storage_vault_store.dart';
import 'package:symudol/features/vault/domain/vault_crypto_service.dart';
import 'package:symudol/features/vault/domain/vault_service_impl.dart';

const _ladder = [
  VaultKdfParams(memory: 64 * 1024, iterations: 3),
  VaultKdfParams(memory: 46 * 1024, iterations: 2),
  VaultKdfParams(memory: 32 * 1024, iterations: 3),
  VaultKdfParams(memory: 19 * 1024, iterations: 2),
];
const _runs = 5;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Argon2id unlock cost', (tester) async {
    final results = <String, Object>{};
    await tester.runAsync(() async {
      for (final params in _ladder) {
        final timings = <int>[];
        for (var run = 0; run < _runs; run++) {
          timings.add(await _timeDerivation(params));
        }
        timings.sort();
        final median = timings[_runs ~/ 2];
        final label = '${params.memory ~/ 1024} MiB/t${params.iterations}';
        results[label] = {'medianMs': median, 'runsMs': timings};
        debugPrint('argon2_bench $label median=${median}ms runs=$timings');
      }
    });
    binding.reportData = {...?binding.reportData, 'argon2id': results};
  }, timeout: const Timeout(Duration(minutes: 20)));

  // The whole unlock with VaultKdfParams.defaultParams: secure storage, the
  // clock channel, Argon2id and the DEK unwrap. Erases this app's vault.
  testWidgets('VaultService unlock time', (tester) async {
    final timings = <int>[];
    await tester.runAsync(() async {
      final store = SecureStorageVaultStore();
      await store.clearAll();
      final service = VaultServiceImpl(store);
      await service.createVault('123456');
      for (var run = 0; run < _runs; run++) {
        await service.lock();
        final watch = Stopwatch()..start();
        await service.unlock('123456');
        timings.add(watch.elapsedMilliseconds);
      }
      await store.clearAll();
    });
    timings.sort();
    final median = timings[_runs ~/ 2];
    debugPrint(
      'unlock_bench ${VaultKdfParams.defaultParams} '
      'median=${median}ms runs=$timings',
    );
    binding.reportData = {
      ...?binding.reportData,
      'unlock': {'medianMs': median, 'runsMs': timings},
    };
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Derives a KEK in a background isolate, as unlock does, and returns the
/// milliseconds it took.
Future<int> _timeDerivation(VaultKdfParams params) {
  return Isolate.run(() {
    const crypto = PointyCastleVaultCryptoService();
    final salt = Uint8List(16);
    final watch = Stopwatch()..start();
    crypto.deriveKek('123456', salt, params);
    return watch.elapsedMilliseconds;
  });
}
