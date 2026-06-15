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

  factory NostrProfile.fromJson(Map<String, dynamic> json) {
    return NostrProfile(
      name: json['name'] as String?,
      displayName: json['display_name'] as String?,
      picture: json['picture'] as String?,
      about: json['about'] as String?,
      nip05: json['nip05'] as String?,
    );
  }
}
