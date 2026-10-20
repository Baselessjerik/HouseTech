import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Abre el selector nativo de destino y guarda los bytes fuera de la web.
Future<bool> savePqrFile(String fileName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: bytes,
  );
  return path != null;
}
