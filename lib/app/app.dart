import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/requests/application/request_providers.dart';
import '../features/requests/domain/request_provenance.dart';
import '../features/requests/domain/request_trust_status.dart';
import '../features/requests/domain/signing_action_type.dart';
import '../features/requests/domain/signing_request.dart';
import '../features/requests/domain/signing_request_status.dart';
import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../features/vault/presentation/setup_vault_screen.dart';
import '../features/navigation/presentation/main_navigation_screen.dart';
import '../features/vault/application/vault_providers.dart';
import '../features/vault/domain/vault_state.dart';
import '../theme/app_theme.dart';

class DiogelApp extends ConsumerStatefulWidget {
  const DiogelApp({super.key});

  @override
  ConsumerState<DiogelApp> createState() => _DiogelAppState();
}

class _DiogelAppState extends ConsumerState<DiogelApp> with WidgetsBindingObserver {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Add a sample request for demo purposes if list is empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(requestControllerProvider.notifier);
      if (controller.state.requests.isEmpty) {
        controller.acceptRequest(
          SigningRequest(
            id: 'demo-1',
            provenance: const RequestProvenance(
              sourceDisplayName: 'Amethyst',
              sourceIdentifier: 'nostr:amethyst:client',
              trustStatus: RequestTrustStatus.unknown,
            ),
            actionType: SigningActionType.signEvent,
            eventKind: 1,
            eventPayload: {
              'content': 'Hello Nostr! Signing this message from my secure vault. Security first, always.',
              'created_at': 1715432001,
              'tags': [['t', 'security'], ['t', 'privacy']],
            },
            targetIdentityPublicKey: 'npub1...a4f2',
            targetIdentityLocalId: 'active-id',
            createdAt: DateTime.now(),
            status: SigningRequestStatus.pending,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final vaultControllerState = ref.read(vaultControllerProvider);
    if (vaultControllerState.vaultState is VaultUnlocked) {
      final timeoutMinutes = vaultControllerState.inactivityTimeoutMinutes;
      if (timeoutMinutes > 0) {
        _inactivityTimer = Timer(Duration(minutes: timeoutMinutes), () {
          ref.read(vaultControllerProvider.notifier).expireSession();
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Auto-lock when app goes to background
      ref.read(vaultControllerProvider.notifier).lock();
    } else if (state == AppLifecycleState.resumed) {
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(vaultControllerProvider);
    final vaultState = controllerState.vaultState;
    final isLoading = controllerState.isLoading;

    // Reset timer on any state change that leads to Unlocked
    if (vaultState is VaultUnlocked) {
      _resetInactivityTimer();
    } else {
      _inactivityTimer?.cancel();
    }

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: MaterialApp(
        title: 'Android Diogel',
        theme: DiogelTheme.darkTheme,
        home: isLoading && vaultState is NoVault
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _getHome(vaultState),
      ),
    );
  }

  Widget _getHome(VaultState state) {
    return switch (state) {
      NoVault() => const SetupVaultScreen(),
      VaultLocked() || SessionExpired() => const UnlockVaultScreen(),
      VaultUnlocked() => const MainNavigationScreen(),
    };
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DiogelApp();
  }
}
