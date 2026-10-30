import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../nip55/application/nip55_providers.dart';
import '../../requests/presentation/approval_screen.dart';
import '../../settings/presentation/settings_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  /// The Approval screen pushed above a screen or dialog that covered this
  /// shell when a request arrived (#121). Null while the shell is on top.
  Route<void>? _approvalRoute;

  final List<Widget> _screens = const [
    AccountsScreen(),
    ApprovalScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // A request may already be waiting when the shell is built, for example
    // one that arrived while the vault was locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(hasPendingApprovalProvider)) _showApproval();
    });
  }

  @override
  void dispose() {
    // The vault locked or was wiped: the approval must not outlive the shell.
    // The navigator is mid-update here, so remove the route after the frame.
    final route = _approvalRoute;
    _approvalRoute = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  /// Switches to the Requests tab and, if a screen pushed from Settings or
  /// Accounts (or a dialog) covers the shell, shows the Approval screen above
  /// it. Pushed screens are kept, so unsaved edits are not lost (#121).
  void _showApproval() {
    if (_currentIndex != 1) setState(() => _currentIndex = 1);
    if (_approvalRoute?.isActive ?? false) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) return;

    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const _PendingApprovalRoute(),
    );
    _approvalRoute = route;
    Navigator.of(context).push(route);
  }

  /// The request settled: the user goes back to the screen they were using.
  void _removeApprovalRoute() {
    final route = _approvalRoute;
    _approvalRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    // After the frame: the navigator may be mid-build when a request lands.
    ref.listen<bool>(hasPendingApprovalProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next && previous != true) {
          _showApproval();
        } else if (!next) {
          _removeApprovalRoute();
        }
      });
    });
    // Stay on the Requests tab while a request is pending.
    if (ref.watch(hasPendingApprovalProvider) && _currentIndex != 1) {
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

/// The Approval screen as a route of its own. Back cannot hide the request
/// again while it is pending: the user approves or rejects it, which removes
/// the route (#121).
class _PendingApprovalRoute extends StatelessWidget {
  const _PendingApprovalRoute();

  @override
  Widget build(BuildContext context) {
    return const PopScope(canPop: false, child: ApprovalScreen());
  }
}
