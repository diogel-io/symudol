import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../features/vault/presentation/setup_vault_screen.dart';
import '../features/navigation/presentation/main_navigation_screen.dart';
import '../features/vault/application/vault_providers.dart';
import '../features/vault/domain/vault_state.dart';
import '../theme/app_theme.dart';

class DiogelApp extends ConsumerWidget {
  const DiogelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize vault
    ref.watch(vaultInitializationProvider);
    
    final vaultState = ref.watch(vaultStateProvider);

    return MaterialApp(
      title: 'Android Diogel',
      theme: DiogelTheme.darkTheme,
      home: _getHome(vaultState),
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
