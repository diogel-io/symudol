import 'package:flutter/widgets.dart';

/// Pops the route [context] belongs to, but only while it is still the top
/// route.
///
/// A vault lock removes every route above the root (diogel-io/symudol#123).
/// A screen or dialog that was awaiting something stays mounted while its exit
/// animation runs, so a plain `Navigator.pop` after the await would pop the
/// unlock screen instead and leave the navigator empty.
void popIfCurrent<T extends Object?>(BuildContext context, [T? result]) {
  if (!context.mounted) return;
  if (ModalRoute.of(context)?.isCurrent != true) return;
  Navigator.of(context).pop<T>(result);
}
