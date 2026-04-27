import 'package:flutter/material.dart';

import '../../../../theme/tokens.dart';

class PinButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const PinButton(this.text, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: Center(
        child: Text(text, style: Theme.of(context).textTheme.displayMedium),
      ),
    );
  }
}

class PinButtonIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const PinButtonIcon(this.icon, {super.key, required this.onPressed});

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
