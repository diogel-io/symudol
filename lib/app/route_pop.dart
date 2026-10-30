import 'package:flutter/widgets.dart';

/// Closes the route [context] belongs to, unless it is already gone.
///
/// A vault lock removes every route above the root (diogel-io/symudol#123).
/// A screen or dialog that was awaiting something stays mounted while its exit
/// animation runs, so a plain `Navigator.pop` after the await would pop the
/// unlock screen instead and leave the navigator empty. Such a route is no
/// longer active, so nothing happens.
///
/// A route that is still active but covered (the NIP-46 import sheet under
/// the connect approval it started) is removed from under the route above it,
/// so that route stays on top.
void popIfCurrent<T extends Object?>(BuildContext context, [T? result]) {
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  if (route.isCurrent) {
    Navigator.of(context).pop<T>(result);
  } else {
    Navigator.of(context).removeRoute(route, result);
  }
}
