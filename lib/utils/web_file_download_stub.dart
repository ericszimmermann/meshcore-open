import 'dart:typed_data';

/// No-op stub used on non-web platforms. Never called at runtime because
/// callers guard with [kIsWeb] / [PlatformInfo.isWeb].
void downloadFileOnWeb(String filename, Uint8List bytes) {
  throw UnsupportedError('downloadFileOnWeb called on a non-web platform');
}
