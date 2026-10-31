import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:symudol/features/profile/data/profile_image_picker.dart';

/// Records what [pickImage] was asked for, and picks nothing.
class _RecordingImagePicker extends ImagePicker {
  final calls = <Map<String, Object?>>[];

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
}
