import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

class PinButton extends StatelessWidget {
  final String text;

  /// `null` disables the button, as during a PIN lockout.
  final VoidCallback? onPressed;

  const PinButton(this.text, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displayMedium;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: Center(
        child: Text(
          text,
          style: onPressed == null
              ? style?.copyWith(color: DiogelColors.textTertiary)
              : style,
        ),
      ),
    );
  }
}

class PinButtonIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  const PinButtonIcon(
    this.icon, {
    super.key,
    required this.onPressed,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: Center(
        child: Icon(
          icon,
          semanticLabel: semanticLabel,
          size: 32,
          color: onPressed == null
              ? DiogelColors.textTertiary
              : DiogelColors.textSecondary,
        ),
      ),
    );
  }
}
