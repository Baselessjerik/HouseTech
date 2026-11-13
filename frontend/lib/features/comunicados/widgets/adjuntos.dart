import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../comunicados_api.dart';
import '../models/modelos.dart';
import '../providers/comunicados_providers.dart';
import 'ui.dart';

const extensionesAdjuntos = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'zip',
};
const maxAdjuntos = 5;
const maxBytesAdjunto = 10 * 1024 * 1024;

String formatoTamano(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData iconoArchivo(String extension) {
  switch (extension) {
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'doc':
    case 'docx':
    case 'txt':
      return Icons.description_rounded;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_rounded;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_rounded;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
      return Icons.image_rounded;
    case 'zip':
      return Icons.folder_zip_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

/// Lista de archivos adjuntos de un comunicado, con botón para abrirlos o descargarlos.
class AdjuntosLista extends ConsumerWidget {
  const AdjuntosLista({super.key, required this.comunicadoId, required this.adjuntos, required this.gestion});

  final int comunicadoId;
  final List<AdjuntoComunicado> adjuntos;

  /// true cuando lo abre un administrador (endpoint de gestión); false para el residente.
  final bool gestion;

  Future<void> _abrir(BuildContext context, WidgetRef ref, AdjuntoComunicado a) async {
    try {
      final url = await ref.read(comunicadosServiceProvider).enlaceAdjunto(comunicadoId, a.id, gestion: gestion);
      final abierto = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!abierto && context.mounted) mostrarMensaje(context, 'No se pudo abrir el archivo.', error: true);
    } on ApiException catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (adjuntos.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 16),
      const Text('Archivos adjuntos', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(height: 6),
      for (final a in adjuntos)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _abrir(context, ref, a),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(iconoArchivo(a.extension), color: AppColors.oceanBlue),
              const SizedBox(width: 10),
              Expanded(child: Text(a.nombre, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(formatoTamano(a.tamano), style: const TextStyle(color: Colors.black45, fontSize: 12)),
              IconButton(
                tooltip: 'Descargar',
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _abrir(context, ref, a),
              ),
            ]),
          ),
        ),
    ]);
  }
}
