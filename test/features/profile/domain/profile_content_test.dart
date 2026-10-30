import 'package:flutter_test/flutter_test.dart';
import 'package:symudol/features/profile/domain/profile_content.dart';

/// Reading a kind 0 into the form and merging the form back into it, without
/// dropping what other apps set (diogel-io/symudol#41).
void main() {
  group('mergeProfile', () {
    test('editing one field keeps every field other apps set', () {
      final latest = <String, Object?>{
        'name': 'alice',
        'about': 'old about',
        'lud06': 'lnurl1xyz',
        'pronouns': 'she/her',
        'custom': {'nested': true},
      };
      final form = formFromContent(latest).withText('about', 'new about');

      final merged = mergeProfile(latest, form);

      expect(merged, {
        'name': 'alice',
        'about': 'new about',
        'lud06': 'lnurl1xyz',
        'pronouns': 'she/her',
        'custom': {'nested': true},
      });
    });

    test('an emptied field is removed', () {
      final latest = <String, Object?>{'name': 'alice', 'website': 'https://a'};
      final form = formFromContent(latest).withText('website', '  ');

      expect(mergeProfile(latest, form), {'name': 'alice'});
    });

    test('text is trimmed, but about keeps its inner whitespace', () {
      final form = const ProfileForm()
          .withText('name', '  alice ')
          .withText('about', '  line one\n\nline two  \n');

      expect(mergeProfile(null, form), {
        'name': 'alice',
        'about': '  line one\n\nline two',
      });
    });

    test('bot is written only when true', () {
      final latest = <String, Object?>{'name': 'b', 'bot': true};

      expect(
        mergeProfile(latest, formFromContent(latest).copyWith(bot: false)),
        {'name': 'b'},
      );
      expect(mergeProfile(null, const ProfileForm().copyWith(bot: true)), {
        'bot': true,
      });
    });

    test('a birthday keeps only the parts that are set', () {
      final form = const ProfileForm().copyWith(
        birthday: const ProfileBirthday(month: '4', day: ' 9 '),
      );

      expect(mergeProfile(null, form), {
        'birthday': {'month': 4, 'day': 9},
      });
    });

    test('a birthday with no parts is removed', () {
      final latest = <String, Object?>{
        'birthday': {'year': 1990},
      };
      final form = formFromContent(
        latest,
      ).copyWith(birthday: const ProfileBirthday());

      expect(mergeProfile(latest, form), isEmpty);
    });
  });

  group('mergeProfile with values the form could not read', () {
    final latest = <String, Object?>{
      'name': 42,
      'bot': 'yes',
      'birthday': '1990-04-09',
      'about': 'hi',
    };

    test('they are kept while their fields are left empty', () {
      final form = formFromContent(latest).withText('about', 'hello');

      expect(mergeProfile(latest, form), {
        'name': 42,
        'bot': 'yes',
        'birthday': '1990-04-09',
        'about': 'hello',
      });
    });

    test('they are replaced once the user fills the field in', () {
      final form = formFromContent(latest)
          .withText('name', 'alice')
          .copyWith(bot: true, birthday: const ProfileBirthday(year: '1990'));

      expect(mergeProfile(latest, form), {
        'name': 'alice',
        'bot': true,
        'birthday': {'year': 1990},
        'about': 'hi',
      });
    });
  });

  group('applyEdits', () {
    test('only the fields the user changed replace the latest values', () {
      final loaded = formFromContent({'name': 'alice', 'picture': 'old.png'});
      final latest = formFromContent({
        'name': 'alice',
        'picture': 'changed-elsewhere.png',
      });
      final edited = loaded.withText('name', 'Alice');

      final form = applyEdits(latest, loaded, edited);

      expect(form['name'], 'Alice');
      expect(form['picture'], 'changed-elsewhere.png');
    });

    test('birthday parts are applied one by one', () {
      final loaded = formFromContent({
        'birthday': {'year': 1990, 'month': 4},
      });
      final latest = formFromContent({
        'birthday': {'year': 1991, 'month': 4},
      });
      final edited = loaded.copyWith(
        birthday: loaded.birthday.copyWith(month: '5'),
      );

      final form = applyEdits(latest, loaded, edited);

      expect(form.birthday, const ProfileBirthday(year: '1991', month: '5'));
    });

    test('clearing a field is a change', () {
      final loaded = formFromContent({'website': 'https://a'});
      final latest = formFromContent({'website': 'https://b'});

      final form = applyEdits(latest, loaded, loaded.withText('website', ''));

      expect(form['website'], isEmpty);
    });
  });

  group('formFromContent', () {
    test('reads the fields the form edits', () {
      final form = formFromContent({
        'name': 'alice',
        'display_name': 'Alice',
        'lud16': 'alice@example.com',
        'bot': true,
        'birthday': {'year': 1990, 'month': 4, 'day': 9},
      });

      expect(form['name'], 'alice');
      expect(form['display_name'], 'Alice');
      expect(form['lud16'], 'alice@example.com');
      expect(form.bot, isTrue);
      expect(
        form.birthday,
        const ProfileBirthday(year: '1990', month: '4', day: '9'),
      );
    });

    test('values of the wrong type are ignored', () {
      final form = formFromContent({
        'name': 42,
        'about': ['a'],
        'bot': 'yes',
        'birthday': {'year': '1990', 'month': 4.5},
      });

      expect(form['name'], isEmpty);
      expect(form['about'], isEmpty);
      expect(form.bot, isFalse);
      expect(form.birthday.isEmpty, isTrue);
    });

    test('no content is an empty form', () {
      expect(formFromContent(null), const ProfileForm());
    });
  });

  group('validateProfileForm', () {
    test('a valid form has no errors', () {
      final form = const ProfileForm()
          .withText('website', 'https://example.com')
          .withText('picture', 'https://example.com/a.png')
          .withText('lud16', 'alice@example.com')
          .copyWith(
            birthday: const ProfileBirthday(year: '1990', month: '12'),
          );

      expect(validateProfileForm(form), isEmpty);
    });

    test('links must be full http(s) addresses', () {
      final form = const ProfileForm()
          .withText('website', 'example.com')
          .withText('banner', 'ftp://example.com/b.png');

      expect(
        validateProfileForm(form).keys,
        containsAll(['website', 'banner']),
      );
    });

    test('a lightning address must look like name@domain', () {
      final form = const ProfileForm().withText('lud16', 'alice');

      expect(validateProfileForm(form).keys, ['lud16']);
    });

    test('birthday parts must be in range', () {
      for (final birthday in const [
        ProfileBirthday(month: '13'),
        ProfileBirthday(day: '0'),
        ProfileBirthday(year: 'nineteen'),
        // Too long to fit in an int: an error, not an exception.
        ProfileBirthday(year: '123456789012345678901234567890'),
      ]) {
        final form = const ProfileForm().copyWith(birthday: birthday);
        expect(validateProfileForm(form).keys, ['birthday']);
      }
    });
  });
}
