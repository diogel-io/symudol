import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Scans a client's `nostrconnect://` QR code with the camera (#31).
///
/// Behind an interface, so tests need no camera.
abstract interface class Nip46QrScanner {
  /// Whether this device has a camera to scan with.
  Future<bool> isAvailable();

  /// Opens the scanner and returns the scanned `nostrconnect://` URI, or
  /// null when the user leaves without one.
  Future<String?> scan(BuildContext context);
}

final nip46QrScannerProvider = Provider<Nip46QrScanner>(
  (ref) => const ZxingNip46QrScanner(),
);

/// [Nip46QrScanner] with `flutter_zxing`: zxing-cpp, with no Google code.
class ZxingNip46QrScanner implements Nip46QrScanner {
  const ZxingNip46QrScanner();

  @override
  Future<bool> isAvailable() async {
    try {
      return (await availableCameras()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<String>(builder: (_) => const Nip46QrScanScreen()),
  );
}

/// The camera view. Pops with the first `nostrconnect://` code it reads.
class Nip46QrScanScreen extends StatefulWidget {
  /// The camera view, replaceable in tests. It calls `onCode` with each code
  /// read, and `onCameraError` when the camera can't be used, such as when
  /// the permission is refused.
  @visibleForTesting
  final Widget Function(
    void Function(String code) onCode,
    void Function() onCameraError,
  )?
  readerBuilder;

  const Nip46QrScanScreen({super.key, this.readerBuilder});

  @override
  State<Nip46QrScanScreen> createState() => _Nip46QrScanScreenState();
}

class _Nip46QrScanScreenState extends State<Nip46QrScanScreen> {
  bool _wrongCode = false;
  bool _cameraError = false;
  bool _done = false;

  void _onCode(String code) {
    if (_done || !mounted) return;
    if (code.trim().startsWith('nostrconnect://')) {
      _done = true;
      Navigator.of(context).pop(code.trim());
    } else if (!_wrongCode) {
      setState(() => _wrongCode = true);
    }
  }

  void _onCameraError() {
    if (mounted) setState(() => _cameraError = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan nostrconnect:// code')),
      body: _cameraError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Symudol can’t use the camera. Allow camera access in '
                  'Android settings, or go back and paste the URI.',
                  key: const Key('nip46ScanCameraError'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child:
                      widget.readerBuilder?.call(_onCode, _onCameraError) ??
                      ReaderWidget(
                        codeFormat: Format.qrCode,
                        showGallery: false,
                        showToggleCamera: false,
                        onScan: (code) {
                          final text = code.text;
                          if (code.isValid && text != null) _onCode(text);
                        },
                        onControllerCreated: (_, error) {
                          if (error != null) _onCameraError();
                        },
                      ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 16,
                  child: Text(
                    _wrongCode
                        ? 'That isn’t a nostrconnect:// code. Scan the code '
                              'your client shows for a remote signer.'
                        : 'Point the camera at the nostrconnect:// code your '
                              'client shows.',
                    key: const Key('nip46ScanHint'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      shadows: const [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
