import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:symudol/features/profile/domain/profile_image.dart';

/// Whether [bytes] contains [marker] anywhere.
bool _contains(Uint8List bytes, String marker) {
  final needle = latin1.encode(marker);
  outer:
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// A [width] by [height] photo whose EXIF names a camera, a location and
/// [orientation].
Uint8List _photoWithExif({
  required int width,
  required int height,
  int orientation = 1,
}) {
  final photo = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(200, 30, 30));
  photo.exif.imageIfd['Make'] = img.IfdValueAscii('SecretCam');
  photo.exif.imageIfd.orientation = orientation;
  photo.exif.gpsIfd[0x0001] = img.IfdValueAscii('N-SECRET');
  return img.encodeJpg(photo);
}

/// A 16-bit greyscale image at [value], set pixel by pixel: `clear` with
/// an RGB colour leaves a one-channel 16-bit image black.
img.Image _grey16({
  required int width,
  required int height,
  required int value,
}) {
  final grey = img.Image(
    width: width,
    height: height,
    numChannels: 1,
    format: img.Format.uint16,
  );
  for (final pixel in grey) {
    pixel.r = value;
  }
  return grey;
}

void main() {
  group('reencodeProfileImage (#43)', () {
    test('the fixture carries the EXIF the re-encode must drop', () {
      final original = _photoWithExif(width: 40, height: 20);
      expect(_contains(original, 'SecretCam'), isTrue);
      expect(_contains(original, 'N-SECRET'), isTrue);
    });

    test('drops EXIF, camera and location data', () {
      final out = reencodeProfileImage(
        _photoWithExif(width: 40, height: 20),
        maxSide: 1024,
      );

      expect(_contains(out, 'Exif'), isFalse);
      expect(_contains(out, 'SecretCam'), isFalse);
      expect(_contains(out, 'N-SECRET'), isFalse);
      expect(img.decodeJpg(out)!.exif.isEmpty, isTrue);
    });

    test('applies the EXIF orientation before dropping it', () {
      // Orientation 6 means the stored pixels are rotated 90 degrees.
      final out = reencodeProfileImage(
        _photoWithExif(width: 40, height: 20, orientation: 6),
        maxSide: 1024,
      );

      final decoded = img.decodeJpg(out)!;
      expect((decoded.width, decoded.height), (20, 40));
    });

    test('scales the longest side down to maxSide', () {
      final out = reencodeProfileImage(
        _photoWithExif(width: 300, height: 120),
        maxSide: 100,
      );

      final decoded = img.decodeJpg(out)!;
      expect((decoded.width, decoded.height), (100, 40));
    });

    test('keeps a smaller image at its size', () {
      final out = reencodeProfileImage(
        _photoWithExif(width: 30, height: 60),
        maxSide: 100,
      );

      final decoded = img.decodeJpg(out)!;
      expect((decoded.width, decoded.height), (30, 60));
    });

    test('drops PNG text chunks and an ICC profile, and flattens alpha', () {
      final png = img.Image(width: 10, height: 10, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0))
        ..textData = {'Comment': 'HOME-ADDRESS'}
        ..iccProfile = img.IccProfile(
          'SECRET-ICC',
          img.IccProfileCompression.none,
          Uint8List.fromList(List.filled(64, 7)),
        );
      final source = img.encodePng(png);
      expect(_contains(source, 'HOME-ADDRESS'), isTrue);

      final out = reencodeProfileImage(source, maxSide: 1024);

      expect(_contains(out, 'HOME-ADDRESS'), isFalse);
      expect(_contains(out, 'ICC_PROFILE'), isFalse);
      // Transparent pixels come out white, not black.
      final pixel = img.decodeJpg(out)!.getPixel(5, 5);
      expect(pixel.r, greaterThan(240));
    });

    test('flattens transparency before scaling, so edges stay white', () {
      // Opaque white columns between fully transparent black ones.
      final png = img.Image(width: 400, height: 40, numChannels: 4);
      for (var y = 0; y < png.height; y++) {
        for (var x = 0; x < png.width; x++) {
          png.setPixelRgba(
            x,
            y,
            x.isEven ? 255 : 0,
            x.isEven ? 255 : 0,
            x.isEven ? 255 : 0,
            x.isEven ? 255 : 0,
          );
        }
      }

      final out = img.decodeJpg(
        reencodeProfileImage(img.encodePng(png), maxSide: 100),
      )!;

      for (var x = 0; x < out.width; x++) {
        expect(out.getPixel(x, 5).r, greaterThan(235), reason: 'column $x');
      }
    });

    test('a transparent greyscale PNG comes out white, not black', () {
      final png = img.Image(width: 10, height: 10, numChannels: 2)
        ..clear(img.ColorUint8.rgba(0, 0, 0, 0));

      final out = img.decodeJpg(
        reencodeProfileImage(img.encodePng(png), maxSide: 1024),
      )!;

      final pixel = out.getPixel(5, 5);
      expect([pixel.r, pixel.g, pixel.b], everyElement(greaterThan(240)));
    });

    test('a greyscale image stays grey, not red', () {
      for (final grey in [
        img.Image(width: 10, height: 10, numChannels: 1)
          ..clear(img.ColorUint8.rgb(128, 128, 128)),
        _grey16(width: 10, height: 10, value: 32896),
      ]) {
        final out = img.decodeJpg(
          reencodeProfileImage(img.encodePng(grey), maxSide: 1024),
        )!;

        final pixel = out.getPixel(5, 5);
        expect(
          [pixel.r, pixel.g, pixel.b],
          everyElement(inInclusiveRange(118, 138)),
          reason: '${grey.format} grey',
        );
      }
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => reencodeProfileImage(
          Uint8List.fromList(utf8.encode('not an image')),
          maxSide: 1024,
        ),
        throwsA(isA<ProfileImageException>()),
      );
    });
  });

  group('stripAndResize (#43)', () {
    test('re-encodes on another isolate', () async {
      final out = await stripAndResize(
        _photoWithExif(width: 40, height: 20),
        maxSide: 1024,
      );

      expect(_contains(out, 'SecretCam'), isFalse);
    });

    test('refuses a file over 25 MB before decoding it', () {
      expect(
        stripAndResize(
          Uint8List(maxProfileImageBytes + 1),
          maxSide: 1024,
        ),
        throwsA(isA<ProfileImageException>()),
      );
    });
  });
}
