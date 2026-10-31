import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:symudol/features/profile/data/profile_image_picker.dart';

/// Records what [pickImage] was asked for, and picks nothing.
class _RecordingImagePicker extends ImagePicker {
  final calls = <Map<String, Object?>>[];

  /// The sources this platform supports.
  Set<ImageSource> supported = {ImageSource.gallery, ImageSource.camera};

  @override
  bool supportsImageSource(ImageSource source) => supported.contains(source);

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add({
      'source': source,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'imageQuality': imageQuality,
      'requestFullMetadata': requestFullMetadata,
    });
    return null;
  }
}

/// The picker bounds the image so Android decodes and scales it first
/// (diogel-io/symudol#43).
void main() {
  for (final (source, expected) in [
    (ProfileImageSource.photos, ImageSource.gallery),
    (ProfileImageSource.camera, ImageSource.camera),
  ]) {
    test('${source.name} asks Android for a JPEG of at most 4096 px', () async {
      final picker = _RecordingImagePicker();

      final bytes = await SystemProfileImagePicker(picker: picker).pick(source);

      expect(bytes, isNull);
      expect(picker.calls.single, {
        'source': expected,
        'maxWidth': 4096.0,
        'maxHeight': 4096.0,
        'imageQuality': 95,
        'requestFullMetadata': false,
      });
    });
  }

  test('reports the camera missing where the platform has none', () {
    final picker = _RecordingImagePicker()..supported = {ImageSource.gallery};
    final system = SystemProfileImagePicker(picker: picker);

    expect(system.supports(ProfileImageSource.photos), isTrue);
    expect(system.supports(ProfileImageSource.camera), isFalse);
  });
}
