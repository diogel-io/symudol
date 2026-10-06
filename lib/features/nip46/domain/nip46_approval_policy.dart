import 'package:symudol/features/vault/domain/vault_state.dart';

import 'nip46_method.dart';
import 'nip46_permission_scope.dart';
import 'nip46_session.dart';

sealed class Nip46ApprovalDecision {
  const Nip46ApprovalDecision();
}

final class Nip46AutoAllow extends Nip46ApprovalDecision {
  final Nip46PermissionScope scope;
  const Nip46AutoAllow(this.scope);
}

final class Nip46AutoReject extends Nip46ApprovalDecision {
  final String reason;
  const Nip46AutoReject(this.reason);
}

final class Nip46RequireReview extends Nip46ApprovalDecision {
  final String reason;
  final bool canRemember;
  const Nip46RequireReview(this.reason, {this.canRemember = true});
}

final class Nip46RequireUnlock extends Nip46ApprovalDecision {
  final String reason;
  const Nip46RequireUnlock(this.reason);
}

class Nip46ApprovalPolicy {
  const Nip46ApprovalPolicy();

  Nip46ApprovalDecision decide({
    required Nip46Method method,
    required Nip46Session session,
    required VaultState vaultState,
    required String? activeIdentityPubkey,
  }) {
    if (vaultState is! VaultUnlocked || activeIdentityPubkey == null) {
      return const Nip46RequireUnlock(
        'Unlock Diogel and select an identity before handling this NIP-46 request.',
      );
    }

    if (session.status == Nip46SessionStatus.revoked) {
      return const Nip46AutoReject('Session has been revoked.');
    }

    if (session.status == Nip46SessionStatus.pending) {
      // Only connect is allowed on a pending session.
      if (method != Nip46Method.connect) {
        return const Nip46AutoReject('Session is not yet approved.');
      }
    }

    // ping and get_public_key are always auto-allowed on active sessions.
    if (method == Nip46Method.ping) {
      return Nip46AutoAllow(const Nip46PingScope());
    }
    if (method == Nip46Method.getPublicKey) {
      return Nip46AutoAllow(const Nip46GetPublicKeyScope());
    }

    // get_relays and switch_relays are non-sensitive and auto-allowed.
    if (method == Nip46Method.getRelays) {
      return Nip46AutoAllow(const Nip46GetRelaysScope());
    }
    if (method == Nip46Method.switchRelays) {
      return Nip46AutoAllow(const Nip46SwitchRelaysScope());
    }

    // logout is always allowed.
    if (method == Nip46Method.logout) {
      return Nip46AutoAllow(const Nip46GetRelaysScope());
    }

    final requestedScope = _scopeFor(method);
    if (requestedScope == null) {
      return const Nip46AutoReject('Unknown method.');
    }

    // Check if session grants cover this scope.
    for (final granted in session.grantedScopes) {
      if (granted.matches(requestedScope)) {
        return Nip46AutoAllow(granted);
      }
    }

    // Broad sign_event (no kind) always requires explicit review, even if a
    // broad grant exists — callers must pass the kind in the request for auto-allow.
    if (requestedScope is Nip46SignEventScope && requestedScope.kind == null) {
      return const Nip46RequireReview(
        'Broad sign_event requires explicit review.',
        canRemember: false,
      );
    }

    if (requestedScope.isSensitive) {
      return Nip46RequireReview(
        'Sensitive operation (${requestedScope.wire}) needs explicit review.',
      );
    }

    return Nip46RequireReview(
      'No remembered permission matches this request.',
    );
  }

  Nip46PermissionScope? _scopeFor(Nip46Method method) => switch (method) {
    Nip46Method.signEvent => const Nip46SignEventScope(),
    Nip46Method.nip04Encrypt => const Nip46Nip04EncryptScope(),
    Nip46Method.nip04Decrypt => const Nip46Nip04DecryptScope(),
    Nip46Method.nip44Encrypt => const Nip46Nip44EncryptScope(),
    Nip46Method.nip44Decrypt => const Nip46Nip44DecryptScope(),
    Nip46Method.decryptZapEvent => const Nip46DecryptZapEventScope(),
    _ => null,
  };
}
