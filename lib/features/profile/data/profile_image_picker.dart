import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Where a profile image comes from.
enum ProfileImageSource { photos, camera }

/// Lets the user choose a photo or take one (diogel-io/symudol#43).
abstract class ProfileImagePicker {
  /// The chosen image's bytes, or null when the user cancelled.
  Future<Uint8List?> pick(ProfileImageSource source);
}

/// [ProfileImagePicker] through the system photo picker and the camera
/// app's capture intent, so Symudol needs no storage or camera permission.
/// The file is read as it is: `stripAndResize` removes its metadata.
class SystemProfileImagePicker implements ProfileImagePicker {
  SystemProfileImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(ProfileImageSource source) async {
    final file = await _picker.pickImage(
      source: switch (source) {
        ProfileImageSource.photos => ImageSource.gallery,
        ProfileImageSource.camera => ImageSource.camera,
      },
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
