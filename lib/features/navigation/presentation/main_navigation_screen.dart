import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../nip55/application/nip55_providers.dart';
import '../../requests/application/request_providers.dart';
import '../../requests/presentation/requests_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../vault/application/vault_providers.dart';
import '../../vault/domain/vault_state.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    AccountsScreen(),
    RequestsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nip55ControllerProvider.notifier).consumePendingNativeIntent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeRequest = ref.watch(activeRequestProvider);
    final nip55State = ref.watch(nip55ControllerProvider);
    final vaultState = ref.watch(vaultControllerProvider);
    if (nip55State.isWaitingForUnlock &&
        vaultState.vaultState is VaultUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(nip55ControllerProvider.notifier).resumePendingAfterUnlock();
      });
    }
    if ((activeRequest != null || nip55State.pendingPublicKeyRequest != null) &&
        _currentIndex != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 1);
      });
    }

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(
              Icons.account_balance_wallet,
              color: DiogelColors.actionPrimary,
            ),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(
              Icons.receipt_long,
              color: DiogelColors.actionPrimary,
            ),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(
              Icons.settings,
              color: DiogelColors.actionPrimary,
            ),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
