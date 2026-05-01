import 'package:android_diogel/features/nip55/data/nip55_method_channel_gateway.dart';
import 'package:android_diogel/features/requests/application/request_providers.dart';
import 'package:android_diogel/features/vault/application/vault_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'nip55_controller.dart';

final nip55GatewayProvider = Provider<Nip55Gateway>((ref) {
  return Nip55MethodChannelGateway();
});

final nip55ControllerProvider =
    StateNotifierProvider<Nip55Controller, Nip55State>((ref) {
      final gateway = ref.watch(nip55GatewayProvider);
      final vaultController = ref.watch(vaultControllerProvider.notifier);
      final requestController = ref.watch(requestControllerProvider.notifier);
      return Nip55Controller(
        gateway: gateway,
        vaultController: vaultController,
        requestController: requestController,
      );
    });
