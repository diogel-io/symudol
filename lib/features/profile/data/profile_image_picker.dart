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
///
/// The picker scales the image to at most [maxPickedSide] and re-encodes it
/// natively. That lets Android decode formats Dart can't, such as HEIC, and
/// keeps a 48 MP photo from being decoded at full size in Dart. Android
/// copies the EXIF into its copy, so `stripAndResize` still removes it.
class SystemProfileImagePicker implements ProfileImagePicker {
  SystemProfileImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// The longest side, in pixels, of the image the picker hands over.
  static const double maxPickedSide = 4096;

  @override
  Future<Uint8List?> pick(ProfileImageSource source) async {
    final file = await _picker.pickImage(
      source: switch (source) {
        ProfileImageSource.photos => ImageSource.gallery,
        ProfileImageSource.camera => ImageSource.camera,
      },
      maxWidth: maxPickedSide,
      maxHeight: maxPickedSide,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
