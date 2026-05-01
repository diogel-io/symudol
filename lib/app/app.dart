import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _DiogelAppState extends ConsumerState<DiogelApp>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  Timer? _backgroundLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _backgroundLockTimer?.cancel();
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

  void _scheduleBackgroundLock() {
    _backgroundLockTimer?.cancel();
    _inactivityTimer?.cancel();

    final vaultControllerState = ref.read(vaultControllerProvider);
    if (vaultControllerState.vaultState is! VaultUnlocked) {
      return;
    }

    final delayMinutes = vaultControllerState.backgroundLockDelayMinutes;
    if (delayMinutes == -1) {
      return;
    }

    if (delayMinutes == 0) {
      ref.read(vaultControllerProvider.notifier).lock();
      return;
    }

    _backgroundLockTimer = Timer(Duration(minutes: delayMinutes), () {
      ref.read(vaultControllerProvider.notifier).expireSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _scheduleBackgroundLock();
    } else if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel();
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
      _backgroundLockTimer?.cancel();
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
