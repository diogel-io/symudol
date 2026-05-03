enum Nip55WebReturnType { signature, event }

enum Nip55WebCompressionType { none, gzip }

class Nip55WebReturnOptions {
  final Uri? callbackUrl;
  final Nip55WebReturnType returnType;
  final Nip55WebCompressionType compressionType;
  final bool isBrowserFlow;

  const Nip55WebReturnOptions({
    this.callbackUrl,
    this.returnType = Nip55WebReturnType.signature,
    this.compressionType = Nip55WebCompressionType.none,
    this.isBrowserFlow = false,
  });

  bool get hasCallback => callbackUrl != null;

  static Nip55WebReturnOptions fromRaw(Map<String, Object?> raw) {
    final callbackUrl = raw['callbackUrl'] as String?;
    final returnType = raw['returnType'] as String?;
    final compressionType = raw['compressionType'] as String?;
    final browserFlow = raw['isBrowserFlow'] == true;
    return Nip55WebReturnOptions(
      callbackUrl: _parseCallback(callbackUrl),
      returnType: switch (returnType?.trim()) {
        'event' => Nip55WebReturnType.event,
        _ => Nip55WebReturnType.signature,
      },
      compressionType: switch (compressionType?.trim()) {
        'gzip' => Nip55WebCompressionType.gzip,
        _ => Nip55WebCompressionType.none,
      },
      isBrowserFlow:
          browserFlow ||
          callbackUrl != null ||
          returnType != null ||
          compressionType != null,
    );
  }

  static Uri? _parseCallback(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    return uri;
  }
}
