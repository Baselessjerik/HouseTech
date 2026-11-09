import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../models/pqr_model.dart';
import '../../../config/app_colors.dart';

/// Diálogo para previsualizar imágenes o detalles de un archivo adjunto.
class PqrVisorAdjuntoDialog extends StatelessWidget {
  final PqrAdjuntoModel adjunto;
  final Uint8List bytes;
  final VoidCallback onDescargar;

  const PqrVisorAdjuntoDialog({
    super.key,
    required this.adjunto,
    required this.bytes,
    required this.onDescargar,
  });

  @override
  Widget build(BuildContext context) {
    final esImagen = adjunto.tipoMime.startsWith('image/') ||
        ['jpg', 'jpeg', 'png'].any((ext) => adjunto.nombreArchivo.toLowerCase().endsWith(ext));

    return AlertDialog(
      title: Text(
        adjunto.nombreArchivo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 600,
        height: 450,
        child: Center(
          child: esImagen
              ? InteractiveViewer(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_rounded, size: 64, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No se pudo cargar la imagen.'),
                      ],
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 80,
                      color: AppColors.oceanBlue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Archivo PDF (${adjunto.tamanoLegible})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'La previsualización directa de PDF no está disponible en este entorno. Descárgalo para consultarlo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            onDescargar();
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Descargar archivo'),
        ),
      ],
    );
  }
}