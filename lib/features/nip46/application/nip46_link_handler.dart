import 'dart:async';

import 'package:symudol/app/diogel_log.dart';

import '../domain/nip46_connection_token.dart';

/// `nostrconnect:` links other apps open Symudol with (diogel-io/symudol#31).
abstract interface class Nip46Links {
  /// The link waiting to be handled, or null. Each is returned once.
  Future<String?> takeLink();

  /// Fires when a link arrives while Symudol is running.
  Stream<void> get linkAvailable;

  /// Whether Symudol is offered for these links at all.
  Future<void> setLinksEnabled(bool enabled);
}

/// Pairs with the client a `nostrconnect:` link names (#31).
///
/// A link only starts a connection: the user still approves it on the
/// approval screen. It is held in memory, never stored, until the vault is
/// unlocked, since a session can't be saved before (#32). It carries the
/// client's secret, so it is never logged or shown.
class Nip46LinkHandler {
  final Nip46Links _links;
  final bool _enabled;
  final bool Function() _isUnlocked;
  final bool Function() _hasPendingApproval;
  final Future<void> Function(String uri) _importLink;
  final void Function() _openApproval;
  final void Function(String message) _showMessage;

  String? _held;
  bool _importing = false;
  // Bumped by a wipe, so an import begun before it opens nothing (#31).
  int _wipes = 0;
  StreamSubscription<void>? _subscription;

  Nip46LinkHandler({
    required Nip46Links links,
    required bool enabled,
    required bool Function() isUnlocked,
    required bool Function() hasPendingApproval,
    required Future<void> Function(String uri) importLink,
    required void Function() openApproval,
    required void Function(String message) showMessage,
  }) : _links = links,
       _enabled = enabled,
       _isUnlocked = isUnlocked,
       _hasPendingApproval = hasPendingApproval,
       _importLink = importLink,
       _openApproval = openApproval,
       _showMessage = showMessage;

  /// Turns link handling on or off to match the build (#26), then handles
  /// the link Symudol was opened with, if any.
  Future<void> start() async {
    await _links.setLinksEnabled(_enabled);
    if (!_enabled) return;
    _subscription = _links.linkAvailable.listen((_) => unawaited(_take()));
    await _take();
  }

  /// Handles a link that arrived while the vault was locked.
  Future<void> onUnlocked() => _handleHeld();

  /// A wiped vault drops a held link, and any link being imported: each was
  /// meant for the old vault.
  void onVaultWiped() {
    _held = null;
    _wipes++;
  }

  void dispose() => unawaited(_subscription?.cancel());

  Future<void> _take() async {
    final link = await _links.takeLink();
    if (link == null) return;
    // The latest link wins, as on the Android side.
    _held = link;
    await _handleHeld();
  }

  Future<void> _handleHeld() async {
    final link = _held;
    if (link == null || !_isUnlocked()) return;
    _held = null;
    if (_importing || _hasPendingApproval()) {
      _showMessage(
        'Another connection is waiting for your answer. Approve or reject '
        'it, then open the link again.',
      );
      return;
    }
    _importing = true;
    final wipes = _wipes;
    String? message;
    try {
      await _importLink(link);
    } on Nip46AlreadyConnectedException {
      message = 'This client is already connected.';
    } on Nip46TokenParseException {
      message = 'This nostrconnect:// link isn’t valid.';
    } on Nip46VaultWipedException {
      // The link was meant for the old vault.
      return;
    } catch (e) {
      // The error, never the link: it carries the client's secret.
      diogelLog(
        'Nip46LinkHandler: could not connect from a link',
        error: e.runtimeType,
      );
      message = 'Symudol couldn’t connect to the client.';
    } finally {
      _importing = false;
    }
    // Wiped during the import, though the import itself finished.
    if (wipes != _wipes) return;
    if (message != null) {
      _showMessage(message);
    } else if (_isUnlocked()) {
      _openApproval();
    }
  }
}
