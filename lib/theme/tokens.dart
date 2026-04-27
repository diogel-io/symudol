import 'package:flutter/material.dart';

class DiogelColors {
  // Surface
  static const Color surfaceBackground = Color(0xFF0F1115);
  static const Color surfaceBase = Color(0xFF171A21);
  static const Color surfaceContainer = Color(0xFF1D212A);
  static const Color surfaceContainerHigh = Color(0xFF252B36);
  static const Color surfaceOverlay = Color(0xF2111318);

  // Text
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFB7C0CC);
  static const Color textTertiary = Color(0xFF8C97A6);
  static const Color textInverse = Color(0xFF0F1115);

  // Border
  static const Color borderSubtle = Color(0xFF2A313D);
  static const Color borderStrong = Color(0xFF3A4454);

  // Action
  static const Color actionPrimary = Color(0xFFF28C28);
  static const Color actionPrimaryHover = Color(0xFFFF9D40);
  static const Color actionPrimaryActive = Color(0xFFD97514);
  static const Color actionSecondary = Color(0xFF2F3744);
  static const Color actionSecondaryHover = Color(0xFF394253);
  static const Color actionSecondaryActive = Color(0xFF252C37);

  // State
  static const Color stateSuccess = Color(0xFF22C55E);
  static const Color stateWarning = Color(0xFFF59E0B);
  static const Color stateError = Color(0xFFEF4444);
  static const Color stateInfo = Color(0xFF38BDF8);
  static const Color stateFocus = Color(0xFFFFB86B);

  // Nostr
  static const Color nostrAccent = Color(0xFF7C3AED);
  static const Color nostrAccentMuted = Color(0xFFA78BFA);
}

class DiogelSpacing {
  static const double space0 = 0;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;
}

class DiogelRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 20;
}

class DiogelMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOut;
}
