import 'dart:typed_data';

import 'pqr_file_saver_stub.dart'
    if (dart.library.js_interop) 'pqr_file_saver_web.dart' as platform;

/// Guarda los bytes usando el mecanismo correspondiente a la plataforma actual.
Future<bool> savePqrFile(String fileName, Uint8List bytes) {
  return platform.savePqrFile(fileName, bytes);
}
