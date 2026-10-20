import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/pqr_model.dart';
import '../../../services/pqr_file_saver.dart';
import '../../../services/pqr_service.dart';

/// Diálogo para consultar y gestionar las evidencias vinculadas a una PQR.
class PqrAdjuntosDialog extends StatefulWidget {
  final Pqr pqr;
  final PqrService service;

  const PqrAdjuntosDialog({
    super.key,
    required this.pqr,
    required this.service,
  });

  @override
  State<PqrAdjuntosDialog> createState() => _PqrAdjuntosDialogState();
}

/// Mantiene el listado sincronizado con las operaciones sobre archivos.
class _PqrAdjuntosDialogState extends State<PqrAdjuntosDialog> {
  List<PqrAdjuntoModel> _adjuntos = [];
  bool _cargando = true;
  bool _subiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarAdjuntos();
  }

  /// Actualiza los metadatos visibles y conserva un mensaje de error opcional.
  Future<void> _cargarAdjuntos({String? error}) async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) {
      setState(() {
        _cargando = false;
        _error = 'No se pudo identificar la solicitud.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final adjuntos = await widget.service.obtenerAdjuntosPqr(pqrId);
      if (!mounted) return;
      setState(() {
        _adjuntos = adjuntos;
        _error = error;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  /// Carga los archivos elegidos y presenta los errores individuales al terminar.
  Future<void> _seleccionarYSubir() async {
    final FilePickerResult? resultado;
    try {
      resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: true,
        withData: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudieron seleccionar archivos: $error');
      return;
    }
    if (resultado == null || !mounted) return;

    final pqrId = widget.pqr.id;
    if (pqrId == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    final errores = <String>[];
    for (final archivo in resultado.files) {
      if (archivo.size > 10 * 1024 * 1024) {
        errores.add('${archivo.name}: supera el límite de 10 MiB.');
        continue;
      }

      final respuesta = await widget.service.subirAdjuntoPqr(
        pqrId: pqrId,
        archivo: archivo,
      );
      if (respuesta['success'] != true) {
        errores.add(
          '${archivo.name}: ${respuesta['message'] ?? 'No se pudo cargar.'}',
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _subiendo = false;
    });
    await _cargarAdjuntos(
      error: errores.isEmpty ? null : errores.join('\n'),
    );
  }

  /// Descarga el contenido por la API autenticada y lo guarda en el dispositivo.
  Future<void> _descargar(PqrAdjuntoModel adjunto) async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) return;

    try {
      final bytes = await widget.service.descargarAdjuntoPqr(
        pqrId: pqrId,
        adjuntoId: adjunto.id,
      );
      final guardado = await savePqrFile(adjunto.nombreArchivo, bytes);
      if (!mounted || !guardado) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${adjunto.nombreArchivo} descargado.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo descargar el archivo: $error';
      });
    }
  }

  /// Reemplaza un adjunto manteniendo su identidad dentro de la PQR.
  Future<void> _reemplazar(PqrAdjuntoModel adjunto) async {
    final FilePickerResult? resultado;
    try {
      resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo seleccionar el archivo: $error');
      return;
    }
    if (resultado == null || resultado.files.isEmpty || !mounted) return;

    final archivo = resultado.files.single;
    if (archivo.size > 10 * 1024 * 1024) {
      setState(() => _error = '${archivo.name}: supera el límite de 10 MiB.');
      return;
    }

    final pqrId = widget.pqr.id;
    if (pqrId == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    final respuesta = await widget.service.actualizarAdjuntoPqr(
      pqrId: pqrId,
      adjuntoId: adjunto.id,
      archivo: archivo,
    );
    if (!mounted) return;

    setState(() => _subiendo = false);
    await _cargarAdjuntos(
      error: respuesta['success'] == true
          ? null
          : '${respuesta['message'] ?? 'No se pudo reemplazar el archivo.'}',
    );
  }

  /// Solicita confirmación antes de eliminar el adjunto y su contenido asociado.
  Future<void> _eliminar(PqrAdjuntoModel adjunto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar adjunto'),
        content: Text('¿Quieres eliminar "${adjunto.nombreArchivo}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final pqrId = widget.pqr.id;
    if (pqrId == null) return;

    setState(() {
      _subiendo = true;
      _error = null;
    });

    final respuesta = await widget.service.eliminarAdjuntoPqr(
      pqrId: pqrId,
      adjuntoId: adjunto.id,
    );
    if (!mounted) return;

    setState(() => _subiendo = false);
    await _cargarAdjuntos(
      error: respuesta['success'] == true
          ? null
          : '${respuesta['message'] ?? 'No se pudo eliminar el archivo.'}',
    );
  }

  /// Presenta listado, estados de carga, errores y acciones CRUD disponibles.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjuntos de ${widget.pqr.radicado}'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_adjuntos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Esta PQR todavía no tiene archivos adjuntos.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _adjuntos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final adjunto = _adjuntos[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.insert_drive_file_outlined,
                        color: AppColors.oceanBlue,
                      ),
                      title: Text(
                        adjunto.nombreArchivo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${adjunto.tipoMime} · ${adjunto.tamanoLegible}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Descargar ${adjunto.nombreArchivo}',
                            onPressed:
                                _subiendo ? null : () => _descargar(adjunto),
                            icon: const Icon(Icons.download_rounded),
                          ),
                          IconButton(
                            tooltip: 'Reemplazar ${adjunto.nombreArchivo}',
                            onPressed:
                                _subiendo ? null : () => _reemplazar(adjunto),
                            icon: const Icon(Icons.drive_file_rename_outline),
                          ),
                          IconButton(
                            tooltip: 'Eliminar ${adjunto.nombreArchivo}',
                            onPressed:
                                _subiendo ? null : () => _eliminar(adjunto),
                            color: Colors.redAccent,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _subiendo ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: _cargando || _subiendo ? null : _seleccionarYSubir,
          icon: _subiendo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.attach_file_rounded),
          label: Text(_subiendo ? 'Subiendo...' : 'Adjuntar archivos'),
        ),
      ],
    );
  }
}
