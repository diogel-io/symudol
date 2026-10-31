import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The profile images that can be uploaded, with the longest side each is
/// scaled down to (diogel-io/symudol#43).
enum ProfileImageKind {
  picture('picture', 1024),
  banner('banner', 1920);

  const ProfileImageKind(this.field, this.maxSide);

  /// The kind 0 key the uploaded URL goes in.
  final String field;

  /// The longest side, in pixels, of the image uploaded.
  final int maxSide;
}

/// The largest file accepted for re-encoding.
const int maxProfileImageBytes = 25 * 1024 * 1024;

/// The image could not be read or is too large.
class ProfileImageException implements Exception {
  const ProfileImageException(this.message);

  final String message;

  @override
  String toString() => 'ProfileImageException: $message';
}

/// [bytes] re-encoded as a fresh JPEG for upload: upright, its longest side
/// at most [maxSide], and carrying no metadata at all (EXIF, location, XMP,
/// ICC profile or text chunks), because the pixels are drawn onto a new image
/// (diogel-io/symudol#43). Transparency is flattened onto white, and an
/// animation becomes its first frame. Runs in a separate isolate.
///
/// Throws [ProfileImageException] when the image is too large or can't be
/// decoded.
Future<Uint8List> stripAndResize(
  Uint8List bytes, {
  required int maxSide,
}) async {
  if (bytes.length > maxProfileImageBytes) {
    throw const ProfileImageException(
      'That image is too large. Choose one under 25 MB.',
    );
  }
  return Isolate.run(() => reencodeProfileImage(bytes, maxSide: maxSide));
}

/// [stripAndResize] on the current isolate.
Uint8List reencodeProfileImage(Uint8List bytes, {required int maxSide}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const ProfileImageException("Symudol couldn't read that image.");
  }
  if (decoded == null) {
    throw const ProfileImageException("Symudol couldn't read that image.");
  }

  var source = _rgb8(img.bakeOrientation(decoded.frames.first));
  // An opaque image is scaled before it is copied, so a large photo isn't
  // drawn at full size. One with transparency is flattened onto white
  // first, so averaging can't darken the edges of transparent areas.
  if (!source.hasAlpha) source = _scaledDown(source, maxSide);
  final clean = img.Image(width: source.width, height: source.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, source);

  return img.encodeJpg(_scaledDown(clean, maxSide), quality: 85);
}

/// [image] as 8-bit RGB or RGBA. `compositeImage` reads two-channel grey
/// as opaque and one-channel grey as red, so greyscale, palette and 16-bit
/// images are converted first (in two steps: one conversion of both the
/// format and the channels loses 16-bit grey).
img.Image _rgb8(img.Image image) {
  var out = image;
  if (out.format != img.Format.uint8 || out.hasPalette) {
    out = out.convert(format: img.Format.uint8);
  }
  if (out.numChannels < 3) out = out.convert(numChannels: 4);
  return out;
}

/// [image] with its longest side at most [maxSide]. Averaging, not the
/// default nearest-neighbour sampling, so a large photo does not alias.
img.Image _scaledDown(img.Image image, int maxSide) {
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= maxSide) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: maxSide,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: maxSide,
          interpolation: img.Interpolation.average,
        );
}
