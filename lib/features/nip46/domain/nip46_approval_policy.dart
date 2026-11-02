import 'package:symudol/features/nip55/domain/nip55_permission_decision.dart';
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

  /// Decides how to handle [method] from [session]'s client.
  ///
  /// [signEventKind] is the kind of a `sign_event`'s event, which the
  /// controller has already checked is an integer (#28). Remembered grants
  /// apply only under [activeIdentityPubkey], until they expire at [now].
  Nip46ApprovalDecision decide({
    required Nip46Method method,
    required Nip46Session session,
    required VaultState vaultState,
    required String? activeIdentityPubkey,
    int? signEventKind,
    DateTime? now,
  }) {
    if (vaultState is! VaultUnlocked || activeIdentityPubkey == null) {
      return const Nip46RequireUnlock(
        'Unlock Symudol and select an identity before handling this NIP-46 request.',
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

    final requestedScope = scopeFor(method, signEventKind);
    if (requestedScope == null) {
      return const Nip46AutoReject('Unknown method.');
    }

    // A broad sign_event is reviewed before any grant is looked at, so no
    // remembered decision can sign any kind (#5, #6).
    if (requestedScope.isBroad) {
      return const Nip46RequireReview(
        'Broad sign_event requires explicit review.',
        canRemember: false,
      );
    }

    final at = now ?? DateTime.now();
    final live = [
      for (final grant in session.grants)
        if (grant.identityPubkey == activeIdentityPubkey &&
            grant.isRememberable &&
            !grant.isExpiredAt(at) &&
            grant.scope.matches(requestedScope))
          grant,
    ];
    // A remembered reject wins over an allow, and a broad reject refuses
    // every kind. A broad allow is never kept (isRememberable).
    for (final grant in live) {
      if (grant.decision == Nip55PermissionDecision.reject) {
        return const Nip46AutoReject('Rejected by a remembered decision.');
      }
    }
    for (final grant in live) {
      if (grant.decision == Nip55PermissionDecision.allow) {
        return Nip46AutoAllow(grant.scope);
      }
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

  /// The scope [method] needs: for `sign_event`, the event's kind. Null for
  /// a method no grant covers.
  static Nip46PermissionScope? scopeFor(
    Nip46Method method,
    int? signEventKind,
  ) =>
      switch (method) {
    Nip46Method.signEvent => Nip46SignEventScope(signEventKind),
    Nip46Method.nip04Encrypt => const Nip46Nip04EncryptScope(),
    Nip46Method.nip04Decrypt => const Nip46Nip04DecryptScope(),
    Nip46Method.nip44Encrypt => const Nip46Nip44EncryptScope(),
    Nip46Method.nip44Decrypt => const Nip46Nip44DecryptScope(),
    Nip46Method.decryptZapEvent => const Nip46DecryptZapEventScope(),
    _ => null,
  };
}
