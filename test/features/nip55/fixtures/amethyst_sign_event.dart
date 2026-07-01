/// Amethyst/Quartz-style NIP-55 sign_event fixture data.
///
/// Amethyst passes the unsigned event as JSON in the `content` extra,
/// the logged-in user's pubkey as `current_user`, and a correlation id
/// as `id`. The signer is expected to populate `id`, `pubkey`, `created_at`,
/// and `sig` before returning.
library amethyst_sign_event;

const amethystSignerPubkey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Unsigned kind-1 event as Amethyst would pass it in the `content` extra.
const amethystUnsignedEventJson =
    '{"kind":1,"content":"hello from amethyst","tags":[],"created_at":1777618800,"pubkey":"$amethystSignerPubkey"}';

/// Amethyst login permissions JSON — requests sign_event for all kinds.
const amethystLoginPermissionsJson =
    '[{"type":"sign_event"},{"type":"get_public_key"}]';

/// Extras map matching what Amethyst would put in a foreground sign_event intent.
Map<String, Object?> amethystSignEventExtras({
  String requestToken = 'token-amethyst-sign',
  String id = 'amethyst-req-1',
  String currentUser = amethystSignerPubkey,
}) =>
    {
      'requestToken': requestToken,
      'type': 'sign_event',
      'content': amethystUnsignedEventJson,
      'id': id,
      'currentUser': currentUser,
    };
