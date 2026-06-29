import 'package:android_diogel/features/requests/domain/known_app_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeKnownPackage', () {
    test('returns a description for a known client package', () {
      expect(
        describeKnownPackage('com.vitorpamplona.amethyst'),
        isNotNull,
      );
    });

    test('returns null for an unrecognized package', () {
      expect(describeKnownPackage('com.unknown.app'), isNull);
    });

    test('returns null for a null package name', () {
      expect(describeKnownPackage(null), isNull);
    });
  });
}
