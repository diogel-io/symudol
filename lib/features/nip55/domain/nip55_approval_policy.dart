import 'package:symudol/features/vault/domain/vault_state.dart';

import 'nip55_client.dart';
import 'nip55_client_permission.dart';
import 'nip55_failure.dart';
import 'nip55_incoming_request.dart';
import 'nip55_method.dart';
import 'nip55_permission_decision.dart';
import 'nip55_permission_scope.dart';
import 'symudol_package.dart';

sealed class Nip55ApprovalDecision {
  const Nip55ApprovalDecision();
}

final class AutoAllow extends Nip55ApprovalDecision {
  final Nip55PermissionGrant grant;

  const AutoAllow(this.grant);
}

final class AutoReject extends Nip55ApprovalDecision {
  final Nip55PermissionGrant grant;
  final String reason;

  const AutoReject(this.grant, this.reason);
}

final class RequireReview extends Nip55ApprovalDecision {
  final String reason;
  final bool canRemember;

  const RequireReview(this.reason, {this.canRemember = true});
}

final class RequireUnlock extends Nip55ApprovalDecision {
  final String reason;

  const RequireUnlock(this.reason);
}

class Nip55ApprovalPolicy {
  const Nip55ApprovalPolicy();

  Nip55ApprovalDecision decide({
    required Nip55IncomingRequest request,
    required VaultState vaultState,
    required String? activeIdentityPubkey,
    required List<Nip55PermissionGrant> grants,
  }) {
    if (vaultState is! VaultUnlocked || activeIdentityPubkey == null) {
      return const RequireUnlock(
        '$nip55UnlockMessagePrefix and select an identity before handling this NIP-55 request.',
      );
    }

    final requestedUser = request.currentUser;
    if (requestedUser != null && requestedUser != activeIdentityPubkey) {
      return const RequireReview(
        'Requested current_user does not match the active Symudol identity.',
        canRemember: false,
      );
    }

    if (request.method == Nip55Method.signEvent) {
      final eventPubkey = request.eventJson?['pubkey'];
      if (eventPubkey != null && eventPubkey != activeIdentityPubkey) {
        return const RequireReview(
          'Requested event pubkey does not match the active Symudol identity.',
          canRemember: false,
        );
      }
    }

    final scope = _scopeFor(request);
    final matching = grants.where(
      (grant) =>
          !_isExpired(grant) &&
          grant.identityPubkey == activeIdentityPubkey &&
          _matchesClient(grant, request.clientIdentity) &&
          grant.scope.matches(scope),
    );

    for (final grant in matching) {
      if (grant.decision == Nip55PermissionDecision.reject) {
        return AutoReject(grant, 'User remembered rejection for this client.');
      }
    }

    for (final grant in matching) {
      if (grant.decision == Nip55PermissionDecision.allow) {
        return AutoAllow(grant);
      }
    }

    return RequireReview(
      _reviewReasonFor(scope, request.clientIdentity),
      canRemember: request.clientIdentity.packageName != null,
    );
  }

  Nip55PermissionScope _scopeFor(Nip55IncomingRequest request) {
    if (request.method == Nip55Method.getPublicKey) {
      return const GetPublicKeyScope();
    }
    if (request.method == Nip55Method.signEvent) {
      final eventJson = request.eventJson;
      final kind = eventJson?['kind'];
      final kindInt = kind is int ? kind : null;
      String? relayUrl;
      if (kindInt == 22242) {
        final tags = eventJson?['tags'];
        if (tags is List) {
          for (final tag in tags) {
            if (tag is List && tag.length >= 2 && tag[0] == 'relay') {
              final url = tag[1];
              if (url is String) {
                relayUrl = _normalizeRelayUrl(url);
                break;
              }
            }
          }
        }
      }
      return SignEventScope(kindInt, relayUrl);
    }
    final peerPubkey = request.pubkey;
    return switch (request.method) {
      Nip55Method.signMessage => const SignMessageScope(),
      Nip55Method.nip04Encrypt => Nip04EncryptScope(peerPubkey),
      Nip55Method.nip04Decrypt => Nip04DecryptScope(peerPubkey),
      Nip55Method.nip44Encrypt => Nip44EncryptScope(peerPubkey),
      Nip55Method.nip44Decrypt => Nip44DecryptScope(peerPubkey),
      Nip55Method.decryptZapEvent => const DecryptZapEventScope(),
      Nip55Method.getPublicKey ||
      Nip55Method.signEvent ||
      Nip55Method.unsupported => UnsupportedScope(request.method.wireName),
    };
  }

  String _reviewReasonFor(
    Nip55PermissionScope scope,
    Nip55ClientIdentity clientIdentity,
  ) {
    if (scope is SignEventScope && scope.kind == null) {
      return 'Broad sign_event request needs explicit review.';
    }
    if (scope.isSensitive) {
      return 'Sensitive NIP-55 request needs explicit review.';
    }
    if (!clientIdentity.provenanceVerified) {
      return 'Caller provenance is weak; review before approving.';
    }
    return 'No remembered permission matches this request.';
  }

  bool _matchesClient(
    Nip55PermissionGrant grant,
    Nip55ClientIdentity clientIdentity,
  ) {
    if (grant.packageName == null ||
        grant.packageName == symudolPackageName ||
        grant.packageName != clientIdentity.packageName) {
      return false;
    }
    final grantCert = grant.certificateSha256;
    if (grantCert != null && grantCert != clientIdentity.certificateSha256) {
      return false;
    }
    return true;
  }

  bool _isExpired(Nip55PermissionGrant grant) {
    final expiry = grant.expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }

  /// Normalizes a relay URL for consistent comparison when storing and matching
  /// kind 22242 permission grants. Trims whitespace, lowercases, strips trailing slash.
  String? _normalizeRelayUrl(String url) {
    var normalized = url.trim().toLowerCase();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.isEmpty ? null : normalized;
  }
}
