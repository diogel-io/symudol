class NostrProfile {
  final String? name;
  final String? displayName;
  final String? picture;
  final String? about;
  final String? nip05;

  const NostrProfile({
    this.name,
    this.displayName,
    this.picture,
    this.about,
    this.nip05,
  });

  /// Reads the string fields of a kind 0 content object. A field another app
  /// wrote with a different type is ignored rather than failing the profile
  /// (diogel-io/symudol#41).
  factory NostrProfile.fromJson(Map<String, dynamic> json) {
    String? text(String key) => switch (json[key]) {
      final String value => value,
      _ => null,
    };
    return NostrProfile(
      name: text('name'),
      displayName: text('display_name'),
      picture: text('picture'),
      about: text('about'),
      nip05: text('nip05'),
    );
  }
}
