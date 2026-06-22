/// Short, human-written descriptions for well-known Nostr client package
/// names. Purely local/static — no network lookups for app metadata are
/// performed during an approval flow.
const Map<String, String> _knownAppDescriptions = {
  'com.vitorpamplona.amethyst': 'Nostr client with TOR support and zaps',
  'com.greenart7c3.nostrsigner': 'Nostr event signer (Amber)',
};

/// Returns a short description for [packageName] if it is a recognized
/// Nostr client, or null if the package is unknown.
String? describeKnownPackage(String? packageName) {
  if (packageName == null) return null;
  return _knownAppDescriptions[packageName];
}
