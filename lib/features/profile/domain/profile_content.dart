// The kind 0 profile content (diogel-io/symudol#41): reading it into the
// form, and merging the form back into it. These follow Bancwr's rules
// (`frontend/app/utils/profile.ts`, Bancwr #30) so that the rule that matters
// most, never dropping a field another app set, is tested directly.

/// The text fields the form edits, Porwr's and Bancwr's set, by their kind 0
/// key.
const List<String> profileTextFields = [
  'name',
  'display_name',
  'about',
  'website',
  'picture',
  'banner',
  'nip05',
  'lud16',
];

/// The keys the form owns. Every other key is kept as it is on save.
const Set<String> _ownedKeys = {...profileTextFields, 'bot', 'birthday'};

/// A NIP-24 birthday. Each part is a string because it comes from an input;
/// empty means not set.
class ProfileBirthday {
  const ProfileBirthday({this.year = '', this.month = '', this.day = ''});

  final String year;
  final String month;
  final String day;

  bool get isEmpty =>
      year.trim().isEmpty && month.trim().isEmpty && day.trim().isEmpty;

  ProfileBirthday copyWith({String? year, String? month, String? day}) =>
      ProfileBirthday(
        year: year ?? this.year,
        month: month ?? this.month,
        day: day ?? this.day,
      );

  @override
  bool operator ==(Object other) =>
      other is ProfileBirthday &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// The values the profile editor holds.
class ProfileForm {
  const ProfileForm({
    this.text = const {},
    this.bot = false,
    this.birthday = const ProfileBirthday(),
  });

  /// The text fields by kind 0 key; a missing key is empty.
  final Map<String, String> text;
  final bool bot;
  final ProfileBirthday birthday;

  /// The value of the text field [key], or an empty string.
  String operator [](String key) => text[key] ?? '';

  ProfileForm withText(String key, String value) =>
      ProfileForm(text: {...text, key: value}, bot: bot, birthday: birthday);

  ProfileForm copyWith({bool? bot, ProfileBirthday? birthday}) => ProfileForm(
    text: text,
    bot: bot ?? this.bot,
    birthday: birthday ?? this.birthday,
  );

  @override
  bool operator ==(Object other) =>
      other is ProfileForm &&
      other.bot == bot &&
      other.birthday == birthday &&
      profileTextFields.every((key) => other[key] == this[key]);

  @override
  int get hashCode => Object.hash(
    bot,
    birthday,
    Object.hashAll(profileTextFields.map((key) => this[key])),
  );
}

/// The form for [content]: string text fields, `bot` when it is `true`, and
/// integer birthday parts. Values of any other type are ignored.
ProfileForm formFromContent(Map<String, Object?>? content) {
  if (content == null) return const ProfileForm();
  final text = <String, String>{
    for (final key in profileTextFields)
      if (content[key] case final String value) key: value,
  };
  var birthday = const ProfileBirthday();
  if (content['birthday'] case final Map<String, Object?> parts) {
    String part(String key) => switch (parts[key]) {
      final int value => '$value',
      _ => '',
    };
    birthday = ProfileBirthday(
      year: part('year'),
      month: part('month'),
      day: part('day'),
    );
  }
  return ProfileForm(
    text: text,
    bot: content['bot'] == true,
    birthday: birthday,
  );
}

/// [latest] with only the fields the user changed from [loaded] to [edited].
/// A field left as it was loaded takes its value from [latest], so a save
/// does not revert what another app changed after the form was loaded.
ProfileForm applyEdits(
  ProfileForm latest,
  ProfileForm loaded,
  ProfileForm edited,
) {
  var form = latest;
  for (final key in profileTextFields) {
    if (edited[key] != loaded[key]) form = form.withText(key, edited[key]);
  }
  if (edited.bot != loaded.bot) form = form.copyWith(bot: edited.bot);
  // Each birthday part on its own, so changing the month keeps a year
  // another app changed.
  final birthday = form.birthday.copyWith(
    year: edited.birthday.year != loaded.birthday.year
        ? edited.birthday.year
        : null,
    month: edited.birthday.month != loaded.birthday.month
        ? edited.birthday.month
        : null,
    day: edited.birthday.day != loaded.birthday.day
        ? edited.birthday.day
        : null,
  );
  return form.copyWith(birthday: birthday);
}

/// The content to publish: [latest] as it stands, with only the form's keys
/// changed. A form field left empty is removed, as is `bot` when false and a
/// birthday with no parts. `about` keeps its inner whitespace; the other text
/// fields are trimmed.
///
/// A key the form edits but could not read, because another app wrote it
/// with a different type (`"name": 42`, `"bot": "yes"`), is kept as it is
/// while its form value is still empty: the user never saw it, so leaving the
/// field empty is not a request to delete it.
Map<String, Object?> mergeProfile(
  Map<String, Object?>? latest,
  ProfileForm form,
) {
  final previous = latest ?? const <String, Object?>{};
  final read = formFromContent(previous);
  final merged = <String, Object?>{
    for (final entry in previous.entries)
      if (!_ownedKeys.contains(entry.key)) entry.key: entry.value,
  };
  void keepUnread(String key) {
    if (previous.containsKey(key)) merged[key] = previous[key];
  }

  for (final key in profileTextFields) {
    final value = key == 'about' ? form[key].trimRight() : form[key].trim();
    if (value.isNotEmpty) {
      merged[key] = value;
    } else if (previous[key] is! String) {
      keepUnread(key);
    }
  }
  if (form.bot) {
    merged['bot'] = true;
  } else if (previous['bot'] is! bool) {
    keepUnread('bot');
  }
  // Birthday parts the form could not read (not integers), and any other
  // keys another app put in the object, are kept while the matching form
  // part is empty.
  final previousBirthday = switch (previous['birthday']) {
    final Map<String, Object?> parts => parts,
    _ => const <String, Object?>{},
  };
  const parts = ['year', 'month', 'day'];
  final birthday = <String, Object?>{
    for (final entry in previousBirthday.entries)
      if (!parts.contains(entry.key)) entry.key: entry.value,
    for (final (key, value) in [
      ('year', form.birthday.year),
      ('month', form.birthday.month),
      ('day', form.birthday.day),
    ])
      if (int.tryParse(value.trim()) case final int number)
        key: number
      else if (previousBirthday.containsKey(key) &&
          previousBirthday[key] is! int)
        key: previousBirthday[key],
  };
  if (birthday.isNotEmpty) {
    merged['birthday'] = birthday;
  } else if (read.birthday.isEmpty) {
    keepUnread('birthday');
  }
  return merged;
}

/// Problems that stop a save, by kind 0 key (`birthday` for the birthday).
/// Empty when the form can be saved.
Map<String, String> validateProfileForm(ProfileForm form) {
  final errors = <String, String>{};
  for (final key in const ['website', 'picture', 'banner']) {
    final value = form[key].trim();
    if (value.isNotEmpty && !isHttpUrl(value)) {
      errors[key] = 'Enter a full address starting with https://';
    }
  }
  final lud16 = form['lud16'].trim();
  if (lud16.isNotEmpty &&
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(lud16)) {
    errors['lud16'] = 'A lightning address looks like name@domain.com';
  }
  bool inRange(String value, int min, int max) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    // tryParse, not parse: a long run of digits does not fit in an int.
    final number = RegExp(r'^\d+$').hasMatch(trimmed)
        ? int.tryParse(trimmed)
        : null;
    return number != null && number >= min && number <= max;
  }

  final birthday = form.birthday;
  if (!inRange(birthday.year, 1, 9999) ||
      !inRange(birthday.month, 1, 12) ||
      !inRange(birthday.day, 1, 31)) {
    errors['birthday'] =
        'Use a year, a month from 1 to 12 and a day from 1 to 31, '
        'or leave them empty.';
  }
  return errors;
}

/// Whether [value] is an absolute http or https URL with a host.
bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}
