import 'package:flutter/material.dart';

import '../features/unlock/presentation/unlock_vault_screen.dart';
import '../theme/app_theme.dart';

class DiogelApp extends StatelessWidget {
  const DiogelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Diogel',
      theme: DiogelTheme.darkTheme,
      home: const UnlockVaultScreen(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DiogelApp();
  }
}
