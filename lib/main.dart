import 'package:flutter/material.dart';
import 'package:dart_nostr/dart_nostr.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Diogel',
      theme: DiogelTheme.darkTheme,
      home: const UnlockVaultScreen(),
    );
  }
}

class UnlockVaultScreen extends StatefulWidget {
  const UnlockVaultScreen({super.key});

  @override
  State<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends State<UnlockVaultScreen> {
  String _pin = '';

  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
      setState(() {
        _pin += number;
      });
      if (_pin.length == 6) {
        // Automatically proceed for demo purposes
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shield, color: DiogelColors.actionPrimary),
            const SizedBox(width: DiogelSpacing.space3),
            Text('Android Diogel', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DiogelSpacing.space4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: DiogelColors.surfaceContainerHigh,
              child: const Icon(Icons.person, size: 20, color: DiogelColors.textSecondary),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: DiogelColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(DiogelRadius.large),
                    border: Border.all(color: DiogelColors.borderSubtle),
                  ),
                  child: const Icon(Icons.shield, size: 48, color: DiogelColors.actionPrimary),
                ),
                const SizedBox(height: DiogelSpacing.space6),
                Text('Unlock Vault', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: DiogelSpacing.space1),
                Text('Enter security PIN to continue', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DiogelColors.textSecondary)),
              ],
            ),
            const SizedBox(height: DiogelSpacing.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space3),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? DiogelColors.actionPrimary : Colors.transparent,
                    border: Border.all(color: isFilled ? DiogelColors.actionPrimary : DiogelColors.borderStrong, width: 2),
                    boxShadow: isFilled ? [BoxShadow(color: DiogelColors.actionPrimary.withOpacity(0.4), blurRadius: 8)] : null,
                  ),
                );
              }),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space8),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: DiogelSpacing.space4,
                crossAxisSpacing: DiogelSpacing.space8,
                children: [
                  ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((n) => _PinButton(n, onPressed: () => _onNumberPressed(n))),
                  _PinButtonIcon(Icons.fingerprint, onPressed: () {}),
                  _PinButton('0', onPressed: () => _onNumberPressed('0')),
                  _PinButtonIcon(Icons.backspace, onPressed: _onBackspace),
                ],
              ),
            ),
            const SizedBox(height: DiogelSpacing.space8),
            Padding(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _pin.length == 6 ? () {
                         Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
                        );
                      } : null,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Unlock Vault'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Forgot PIN?', style: TextStyle(color: DiogelColors.actionPrimary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const _PinButton(this.text, {required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ),
    );
  }
}

class _PinButtonIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _PinButtonIcon(this.icon, {required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: Center(
        child: Icon(icon, size: 32, color: DiogelColors.textSecondary),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const AccountsScreen(),
    const RequestsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
            selectedIcon: Icon(Icons.account_balance_wallet, color: DiogelColors.actionPrimary),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: DiogelColors.actionPrimary),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: DiogelColors.actionPrimary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.privacy_tip, color: DiogelColors.actionPrimary),
            const SizedBox(width: DiogelSpacing.space3),
            Text('Diogel', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: DiogelSpacing.space4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: DiogelColors.surfaceContainerHigh,
              child: const Icon(Icons.person, size: 20, color: DiogelColors.textSecondary),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Accounts', style: Theme.of(context).textTheme.headlineLarge),
                  Text('Manage your Nostr identities', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DiogelColors.textSecondary)),
                ],
              ),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add New'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space4, vertical: DiogelSpacing.space2),
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: DiogelSpacing.space8),
          // Active Account Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              side: const BorderSide(color: DiogelColors.actionPrimary, width: 0.5),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space3, vertical: DiogelSpacing.space1),
                    decoration: const BoxDecoration(
                      color: DiogelColors.actionPrimary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(DiogelRadius.medium),
                        topRight: Radius.circular(DiogelRadius.large),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 12, color: DiogelColors.textInverse),
                        const SizedBox(width: DiogelSpacing.space1),
                        Text('Active', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: DiogelColors.textInverse)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(DiogelSpacing.space4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: DiogelColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(DiogelRadius.medium),
                            ),
                            child: const Icon(Icons.person, size: 40, color: DiogelColors.textSecondary),
                          ),
                          const SizedBox(width: DiogelSpacing.space4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('satoshi_vision', style: Theme.of(context).textTheme.titleLarge),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: DiogelSpacing.space2, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: DiogelColors.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(DiogelRadius.small),
                                      ),
                                      child: Text('npub1...7jk9', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: DiogelColors.actionPrimary, fontFamily: 'monospace')),
                                    ),
                                    const SizedBox(width: DiogelSpacing.space2),
                                    const Icon(Icons.content_copy, size: 16, color: DiogelColors.textTertiary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DiogelSpacing.space4),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(DiogelSpacing.space3),
                              decoration: BoxDecoration(
                                color: DiogelColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                              ),
                              child: Column(
                                children: [
                                  Text('Followers', style: Theme.of(context).textTheme.labelSmall),
                                  Text('12.4K', style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: DiogelSpacing.space2),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(DiogelSpacing.space3),
                              decoration: BoxDecoration(
                                color: DiogelColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                              ),
                              child: Column(
                                children: [
                                  Text('Posts', style: Theme.of(context).textTheme.labelSmall),
                                  Text('842', style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DiogelSpacing.space4),
          // Inactive Account 1
          _InactiveAccountTile(name: 'dev_mainnet', npub: 'npub1...a2x4'),
          const SizedBox(height: DiogelSpacing.space4),
          // Inactive Account 2
          _InactiveAccountTile(name: 'creative_soul', npub: 'npub1...q9w1'),
          const SizedBox(height: DiogelSpacing.space4),
          // Import Private Key
          Container(
            padding: const EdgeInsets.all(DiogelSpacing.space6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              border: Border.all(color: DiogelColors.borderSubtle, width: 2, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                const Icon(Icons.add_circle_outline, size: 32, color: DiogelColors.textTertiary),
                const SizedBox(height: DiogelSpacing.space2),
                Text('Import Private Key', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: DiogelSpacing.space8),
          // Security Badge
          Container(
            padding: const EdgeInsets.all(DiogelSpacing.space4),
            decoration: BoxDecoration(
              color: DiogelColors.surfaceBase,
              borderRadius: BorderRadius.circular(DiogelRadius.large),
              border: Border.all(color: DiogelColors.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user, color: DiogelColors.stateInfo),
                const SizedBox(width: DiogelSpacing.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End-to-End Encryption', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: DiogelSpacing.space1),
                      Text('All private keys are encrypted on-device with AES-256 and never leave your secure hardware element.', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InactiveAccountTile extends StatelessWidget {
  final String name;
  final String npub;
  const _InactiveAccountTile({required this.name, required this.npub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceBase,
        borderRadius: BorderRadius.circular(DiogelRadius.large),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: DiogelColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DiogelRadius.medium),
            ),
            child: const Icon(Icons.person, size: 32, color: DiogelColors.textTertiary),
          ),
          const SizedBox(width: DiogelSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DiogelColors.textSecondary)),
                Text(npub, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: DiogelColors.textTertiary),
        ],
      ),
    );
  }
}

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Request'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DiogelSpacing.space4, DiogelSpacing.space4, DiogelSpacing.space4, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning Banner
            Container(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.stateError.withOpacity(0.1),
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(color: DiogelColors.stateError.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning, color: DiogelColors.stateError),
                  const SizedBox(width: DiogelSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Unknown Provenance', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DiogelColors.stateError)),
                        Text('The requesting application is not in your verified list. Exercise caution.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DiogelColors.stateError)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DiogelSpacing.space6),
            // Request Source
            Text('REQUEST SOURCE', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
            const SizedBox(height: DiogelSpacing.space2),
            _RequestDetailItem(
              icon: Icons.apps,
              iconColor: DiogelColors.actionPrimary,
              title: 'Amethyst',
              subtitle: 'nostr:amethyst:client',
            ),
            const SizedBox(height: DiogelSpacing.space4),
            // Action Type
            Text('ACTION TYPE', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
            const SizedBox(height: DiogelSpacing.space2),
            _RequestDetailItem(
              icon: Icons.edit_note,
              iconColor: DiogelColors.nostrAccentMuted,
              title: 'Sign Kind 1 Event',
              subtitle: 'Standard Text Note',
            ),
            const SizedBox(height: DiogelSpacing.space6),
            // Signing with Account
            Text('SIGNING WITH ACCOUNT', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
            const SizedBox(height: DiogelSpacing.space2),
            Container(
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainer,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(color: DiogelColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: DiogelColors.actionPrimary, width: 2),
                    ),
                    child: const Icon(Icons.person, size: 24, color: DiogelColors.actionPrimary),
                  ),
                  const SizedBox(width: DiogelSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Satoshi\'s Vault', style: Theme.of(context).textTheme.titleMedium),
                        Text('npub1...a4f2', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DiogelColors.actionPrimary, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  const Icon(Icons.verified, color: DiogelColors.textSecondary, size: 20),
                ],
              ),
            ),
            const SizedBox(height: DiogelSpacing.space6),
            // Event Details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('EVENT DETAILS', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Text('Raw JSON', style: TextStyle(color: DiogelColors.actionPrimary, fontSize: 12)),
                  label: const Icon(Icons.expand_more, color: DiogelColors.actionPrimary, size: 16),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DiogelSpacing.space4),
              decoration: BoxDecoration(
                color: DiogelColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DiogelRadius.medium),
                border: Border.all(color: DiogelColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONTENT', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: DiogelSpacing.space2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(DiogelSpacing.space3),
                    decoration: BoxDecoration(
                      color: DiogelColors.surfaceBase,
                      borderRadius: BorderRadius.circular(DiogelRadius.small),
                      border: Border.all(color: DiogelColors.borderSubtle.withOpacity(0.5)),
                    ),
                    child: Text(
                      '"Hello Nostr! Signing this message from my secure vault. Security first, always."',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: DiogelSpacing.space4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CREATED AT', style: Theme.of(context).textTheme.labelSmall),
                            Text('1715432001', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TAGS', style: Theme.of(context).textTheme.labelSmall),
                            Text('[]', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        decoration: BoxDecoration(
          color: DiogelColors.surfaceBackground.withOpacity(0.8),
          border: const Border(top: BorderSide(color: DiogelColors.borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: DiogelSpacing.space4),
                      side: const BorderSide(color: DiogelColors.borderStrong, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DiogelRadius.medium)),
                    ),
                  ),
                ),
                const SizedBox(width: DiogelSpacing.space4),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: DiogelSpacing.space4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DiogelRadius.medium)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DiogelSpacing.space2),
            Text(
              'This action will generate a digital signature using your private key.',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestDetailItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _RequestDetailItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiogelSpacing.space4),
      decoration: BoxDecoration(
        color: DiogelColors.surfaceContainer,
        borderRadius: BorderRadius.circular(DiogelRadius.medium),
        border: Border.all(color: DiogelColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(DiogelRadius.small),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: DiogelSpacing.space3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DiogelSpacing.space4),
        children: [
          Text('SECURITY', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
          const SizedBox(height: DiogelSpacing.space2),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Change PIN',
            subtitle: 'Update your security access code',
          ),
          _SettingsTile(
            icon: Icons.fingerprint,
            title: 'Biometric Unlock',
            subtitle: 'Use fingerprint for faster access',
            trailing: Switch(value: true, onChanged: (v) {}),
          ),
          const SizedBox(height: DiogelSpacing.space6),
          Text('VAULT', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DiogelColors.textTertiary, letterSpacing: 1.2)),
          const SizedBox(height: DiogelSpacing.space2),
          _SettingsTile(
            icon: Icons.backup_outlined,
            title: 'Backup Vault',
            subtitle: 'Export your recovery data',
          ),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: 'Wipe Vault',
            subtitle: 'Permanently delete all keys',
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? DiogelColors.stateError : DiogelColors.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color.withOpacity(0.7)),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: DiogelColors.textTertiary),
    );
  }
}
