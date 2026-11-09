import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../config/app_colors.dart';
import '../../../models/pqr_model.dart';
import '../../../services/pqr_service.dart';

/// Formulario para clasificar, describir y radicar una solicitud PQR.
class PqrFormScreen extends StatefulWidget {
  final PqrService? service;
  final VoidCallback? onCancelar;
  final VoidCallback? onPqrRadicada;
  final VoidCallback? onPqrActualizada;
  final bool puedeAsignarPrioridad;
  final Pqr? pqrInicial;

  const PqrFormScreen({
    super.key,
    this.service,
    this.onCancelar,
    this.onPqrRadicada,
    this.onPqrActualizada,
    this.puedeAsignarPrioridad = false,
    this.pqrInicial,
  });

  @override
  State<PqrFormScreen> createState() => _PqrFormScreenState();
}

/// Controla catálogos, validación, envío y carga posterior de evidencias.
class _PqrFormScreenState extends State<PqrFormScreen> {
  // El tipo es obligatorio; los archivos se conservan en memoria hasta recibir el ID de la PQR.
  final _formKey = GlobalKey<FormState>();
  late final PqrService _pqrService;

  final _asuntoCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();

  static const _tamanoMaximoAdjunto = 10 * 1024 * 1024;
  static const _extensionesAdjuntas = ['pdf', 'jpg', 'jpeg', 'png'];

  List<TipoPqrModel> _tipos = [];
  List<InmuebleOpcionModel> _inmuebles = [];
  List<PlatformFile> _adjuntosSeleccionados = [];
  List<PqrAdjuntoModel> _adjuntosExistentes = [];

  TipoPqrModel? _tipoSeleccionado;
  InmuebleOpcionModel? _inmuebleSeleccionado;
  String _prioridadSeleccionada = 'MEDIA';

  bool _cargandoDatos = true;
  bool _cargandoAdjuntos = false;
  bool _enviando = false;
  String? _errorCatalogo;
  String? _errorTipoSolicitud;
  String? _errorAdjuntos;
  final DateTime _fechaRadicacion = DateTime.now();
  bool get _modoEdicion => widget.pqrInicial != null;

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}, $hora:$minuto';
  }

  String _formatearFechaTexto(String fecha) {
    final valor = fecha.trim();
    if (valor.isEmpty) return 'Sin fecha';
    final parsed = DateTime.tryParse(valor);
    if (parsed == null) return valor;
    return _formatearFecha(parsed.isUtc ? parsed : parsed.toLocal());
  }

  @override
  void initState() {
    super.initState();
    _pqrService = widget.service ?? PqrService();
    final pqr = widget.pqrInicial;
    if (pqr != null) {
      _asuntoCtrl.text = pqr.asunto;
      _descripcionCtrl.text = pqr.descripcion;
      _prioridadSeleccionada = pqr.prioridad.toUpperCase();
    }
    _cargarCatalogos();
    if (_modoEdicion && pqr?.id != null) {
      _cargarAdjuntosExistentes(pqr!.id!);
    }
  }

  @override
  void dispose() {
    _asuntoCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  /// Carga en paralelo tipos e inmuebles antes de habilitar la radicación.
  Future<void> _cargarCatalogos() async {
    setState(() {
      _cargandoDatos = true;
      _errorCatalogo = null;
    });

    try {
      final resultados = await Future.wait([
        _pqrService.obtenerTiposPqr(),
        _pqrService.obtenerMisInmuebles(),
      ]);

      if (!mounted) return;

      final tiposCargados = resultados[0] as List<TipoPqrModel>;
      final inmueblesCargados = resultados[1] as List<InmuebleOpcionModel>;

      setState(() {
        _tipos = tiposCargados;
        _inmuebles = inmueblesCargados;
        final pqr = widget.pqrInicial;
        if (pqr != null) {
          _tipoSeleccionado = tiposCargados
              .where(
                (tipo) => tipo.nombre.toLowerCase() == pqr.tipo.toLowerCase(),
              )
              .firstOrNull;
          _inmuebleSeleccionado = inmueblesCargados
              .where(
                (inmueble) => inmueble.id == pqr.inmuebleId,
              )
              .firstOrNull;
        } else {
          _tipoSeleccionado = null;
          _inmuebleSeleccionado = null;
        }
        _cargandoDatos = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _tipos = [];
        _tipoSeleccionado = null;
        _errorCatalogo = error.toString().replaceFirst('Exception: ', '');
        _cargandoDatos = false;
      });
    }
  }

  Future<void> _cargarAdjuntosExistentes(int pqrId) async {
    if (!mounted) return;
    setState(() {
      _cargandoAdjuntos = true;
      _errorAdjuntos = null;
    });
    try {
      final adjuntos = await _pqrService.obtenerAdjuntosPqr(pqrId);
      if (!mounted) return;
      setState(() {
        _adjuntosExistentes = adjuntos;
        _cargandoAdjuntos = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoAdjuntos = false;
        _errorAdjuntos = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _eliminarAdjuntoExistente(PqrAdjuntoModel adjunto) async {
    final pqrId = widget.pqrInicial?.id;
    if (pqrId == null || _enviando) return;
    setState(() => _enviando = true);
    try {
      final resultado = await _pqrService.eliminarAdjuntoPqr(
        pqrId: pqrId,
        adjuntoId: adjunto.id,
      );
      if (!mounted) return;
      if (resultado['success'] == true) {
        setState(() {
          _adjuntosExistentes = _adjuntosExistentes
              .where((item) => item.id != adjunto.id)
              .toList();
          _enviando = false;
        });
      } else {
        setState(() {
          _enviando = false;
          _errorAdjuntos = resultado['message']?.toString() ??
              'No se pudo eliminar el archivo.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorAdjuntos = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool _esImagenLocal(PlatformFile archivo) {
    final nombre = archivo.name.toLowerCase();
    return nombre.endsWith('.jpg') ||
        nombre.endsWith('.jpeg') ||
        nombre.endsWith('.png');
  }

  bool _esImagenAdjunto(PqrAdjuntoModel adjunto) {
    final mime = adjunto.tipoMime.toLowerCase();
    final nombre = adjunto.nombreArchivo.toLowerCase();
    return mime.startsWith('image/') ||
        nombre.endsWith('.jpg') ||
        nombre.endsWith('.jpeg') ||
        nombre.endsWith('.png');
  }

  void _verImagenLocal(PlatformFile archivo) {
    final bytes = archivo.bytes;
    if (bytes == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: .9),
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(bytes),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  archivo.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verImagenAdjuntaExistente(PqrAdjuntoModel adjunto) async {
    final pqrId = widget.pqrInicial?.id;
    if (pqrId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final bytes = await _pqrService.descargarAdjuntoPqr(
        pqrId: pqrId,
        adjuntoId: adjunto.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // Cierra indicador de carga

      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.black.withValues(alpha: .9),
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.memory(bytes),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    adjunto.nombreArchivo,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar la imagen: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Valida los campos, crea la PQR y luego asocia las evidencias seleccionadas.
  Future<void> _enviarFormulario() async {
    final formularioValido = _formKey.currentState!.validate();
    final tipoValido = _tipoSeleccionado != null;

    setState(() {
      _errorTipoSolicitud =
          tipoValido ? null : 'Selecciona un tipo de solicitud.';
    });

    if (!formularioValido || !tipoValido) return;

    setState(() => _enviando = true);

    try {
      final pqrInicial = widget.pqrInicial;
      final resultado = _modoEdicion
          ? await _pqrService.actualizarPqr(
              id: pqrInicial!.id!,
              tipoId: _tipoSeleccionado!.id,
              asunto: _asuntoCtrl.text,
              descripcion: _descripcionCtrl.text,
              prioridad: widget.puedeAsignarPrioridad
                  ? _prioridadSeleccionada
                  : pqrInicial.prioridad,
              inmuebleId: _inmuebleSeleccionado?.id,
            )
          : await _pqrService.radicarPqr(
              tipoId: _tipoSeleccionado!.id,
              asunto: _asuntoCtrl.text,
              descripcion: _descripcionCtrl.text,
              prioridad: widget.puedeAsignarPrioridad
                  ? _prioridadSeleccionada
                  : 'MEDIA',
              inmuebleId: _inmuebleSeleccionado?.id,
            );

      if (!mounted) return;

      if (resultado['success'] == true) {
        final erroresAdjuntos = <String>[];
        final pqr = resultado['pqr'] as Pqr?;
        final idObjetivo = _modoEdicion ? pqrInicial?.id : pqr?.id;

        if (_adjuntosSeleccionados.isNotEmpty && idObjetivo == null) {
          erroresAdjuntos.add(
            'No se recibió el identificador de la PQR para asociar los archivos.',
          );
        } else if (idObjetivo != null) {
          for (final archivo in _adjuntosSeleccionados) {
            final carga = await _pqrService.subirAdjuntoPqr(
              pqrId: idObjetivo,
              archivo: archivo,
            );
            if (carga['success'] != true) {
              erroresAdjuntos.add(
                '${archivo.name}: ${carga['message'] ?? 'No se pudo cargar.'}',
              );
            }
          }
        }

        if (!mounted) return;
        setState(() => _enviando = false);
        if (_modoEdicion) {
          if (erroresAdjuntos.isNotEmpty) {
            _mostrarMensaje(
              'La PQR se actualizó, pero ${erroresAdjuntos.join("; ")}',
              esError: true,
            );
          } else {
            _mostrarMensaje('PQR actualizada correctamente');
          }
          widget.onPqrActualizada?.call();
          widget.onCancelar?.call();
        } else {
          final radicado = resultado['radicado'] as String;
          _mostrarDialogoExito(
            radicado,
            archivosSeleccionados: _adjuntosSeleccionados.length,
            erroresAdjuntos: erroresAdjuntos,
          );
        }
      } else {
        setState(() => _enviando = false);
        _mostrarMensaje(resultado['message'].toString(), esError: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarMensaje(
        _modoEdicion
            ? 'No fue posible actualizar la solicitud: $error'
            : 'No fue posible radicar la solicitud: $error',
        esError: true,
      );
    }
  }

  /// Selecciona múltiples evidencias y descarta las que incumplen límites locales.
  Future<void> _seleccionarAdjuntos() async {
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _extensionesAdjuntas,
        allowMultiple: true,
        withData: true,
      );
      if (resultado == null || !mounted) return;

      final errores = <String>[];
      final seleccionados = <PlatformFile>[];
      for (final archivo in resultado.files) {
        if (archivo.size > _tamanoMaximoAdjunto) {
          errores.add('${archivo.name}: supera el límite de 10 MiB.');
        } else if (archivo.bytes == null) {
          errores.add('${archivo.name}: no se pudo leer el archivo.');
        } else {
          seleccionados.add(archivo);
        }
      }

      setState(() {
        _adjuntosSeleccionados = [
          ..._adjuntosSeleccionados,
          ...seleccionados,
        ];
        _errorAdjuntos = errores.isEmpty ? null : errores.join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(
          () => _errorAdjuntos = 'No se pudieron seleccionar archivos: $error');
    }
  }

  /// Muestra errores de operación sin ocultar la validación junto a los campos.
  void _mostrarMensaje(String texto, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? Colors.redAccent : AppColors.oceanBlue,
      ),
    );
  }

  /// Confirma el radicado y comunica por separado cualquier fallo parcial de adjuntos.
  void _mostrarDialogoExito(
    String radicado, {
    required int archivosSeleccionados,
    required List<String> erroresAdjuntos,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('¡Radicación Exitosa!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tu solicitud ha sido registrada correctamente en el sistema.',
              style: TextStyle(fontSize: 14),
            ),
            if (erroresAdjuntos.isEmpty && archivosSeleccionados > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Se adjuntaron $archivosSeleccionados archivo(s).',
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ],
            if (erroresAdjuntos.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'La PQR se radicó, pero algunos archivos no se pudieron adjuntar:',
                style: TextStyle(color: Colors.deepOrange, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...erroresAdjuntos.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $error',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Podrás intentar cargarlos desde las acciones de la PQR.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.oceanBlue.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined,
                      color: AppColors.oceanBlue),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Número de Radicado:',
                          style:
                              TextStyle(fontSize: 11, color: Colors.black54)),
                      Text(
                        radicado,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.oceanBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Podrás hacer seguimiento al estado de esta PQR desde tu panel en cualquier momento.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _asuntoCtrl.clear();
              _descripcionCtrl.clear();
              setState(() {
                _adjuntosSeleccionados = [];
                _errorAdjuntos = null;
                _tipoSeleccionado = null;
                _errorTipoSolicitud = null;
              });
              if (widget.onPqrRadicada != null) {
                widget.onPqrRadicada!();
              }
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Construye el formulario y mantiene las validaciones visibles en su contexto.
  @override
  Widget build(BuildContext context) {
    if (_cargandoDatos) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.oceanBlue.withAlpha(18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.oceanBlue,
                      AppColors.oceanBlue.withAlpha(210),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.rate_review_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _modoEdicion
                                ? 'Editar solicitud'
                                : 'Nueva solicitud',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _modoEdicion
                                ? 'Actualiza los datos permitidos de esta PQR.'
                                : 'Radica una petición, queja o reclamo ante la administración.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onCancelar != null)
                      IconButton(
                        tooltip: 'Cerrar formulario',
                        onPressed: _enviando ? null : widget.onCancelar,
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
              const Divider(height: 36, color: Colors.black12),

              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.oceanBlue.withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        color: AppColors.oceanBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fecha de radicación',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _modoEdicion
                                ? '${_formatearFechaTexto(widget.pqrInicial!.fecha)} · Automática'
                                : '${_formatearFecha(_fechaRadicacion)} · Automática',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Colors.black38,
                    ),
                  ],
                ),
              ),

              // Selector de Tipo de PQR (Petición, Queja, Reclamo)
              const Text('Tipo de Solicitud *',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              if (_errorCatalogo != null) ...[
                Text(
                  _errorCatalogo!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                TextButton.icon(
                  onPressed: _cargarCatalogos,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a cargar'),
                ),
              ] else if (_tipos.isEmpty) ...[
                const Text(
                  'No hay tipos de solicitud disponibles en este momento.',
                  style: TextStyle(color: Colors.black54),
                ),
                TextButton.icon(
                  onPressed: _cargarCatalogos,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a cargar'),
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tipos.map((tipo) {
                    final seleccionado = _tipoSeleccionado?.id == tipo.id;
                    return ChoiceChip(
                      label: Text(tipo.nombre),
                      selected: seleccionado,
                      selectedColor: AppColors.oceanBlue,
                      labelStyle: TextStyle(
                        color: seleccionado ? Colors.white : AppColors.textDark,
                        fontWeight:
                            seleccionado ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: _modoEdicion
                          ? null
                          : (val) {
                              if (val) {
                                setState(() {
                                  _tipoSeleccionado = tipo;
                                  _errorTipoSolicitud = null;
                                });
                              }
                            },
                    );
                  }).toList(),
                ),
              ],
              if (_errorTipoSolicitud != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _errorTipoSolicitud!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
              if (_tipoSeleccionado?.descripcion != null) ...[
                const SizedBox(height: 6),
                Text(
                  _tipoSeleccionado!.descripcion!,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 20),

              const Text(
                'Inmueble relacionado (Opcional)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<InmuebleOpcionModel>(
                initialValue: _inmuebleSeleccionado,
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.apartment_rounded,
                    color: AppColors.oceanBlue,
                  ),
                  hintText: 'Selecciona un inmueble',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  const DropdownMenuItem<InmuebleOpcionModel>(
                    value: null,
                    child: Text('Ninguno / Zonas comunes generales'),
                  ),
                  ..._inmuebles.map(
                    (inm) => DropdownMenuItem(
                      value: inm,
                      child: Text(inm.etiquetaPresentacion),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _inmuebleSeleccionado = val),
              ),
              const SizedBox(height: 20),

              // Asunto
              const Text('Asunto *',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _asuntoCtrl,
                decoration: InputDecoration(
                  hintText: 'Ej. Reparación de luminaria en pasillo torre 2',
                  prefixIcon: const Icon(Icons.title_rounded,
                      color: AppColors.oceanBlue),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa el asunto de la solicitud.';
                  }
                  if (val.trim().length < 5) {
                    return 'El asunto debe tener al menos 5 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Descripción Detallada
              const Text('Descripción detallada *',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descripcionCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText:
                      'Describe con claridad y detalle los hechos o la solicitud concreta...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa una descripción detallada.';
                  }
                  if (val.trim().length < 10) {
                    return 'La descripción debe tener al menos 10 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Permite adjuntar evidencia que se subirá luego de crear la PQR.
              const Text(
                'Archivos y evidencias (opcional)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'PDF, JPG o PNG; máximo 10 MiB por archivo.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _enviando ? null : _seleccionarAdjuntos,
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Seleccionar archivos'),
              ),
              if (_modoEdicion) ...[
                const SizedBox(height: 10),
                Text(
                  'Archivos actuales',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (_cargandoAdjuntos)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_adjuntosExistentes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Esta solicitud no tiene archivos adjuntos.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  )
                else
                  ..._adjuntosExistentes.map(
                    (adjunto) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        _esImagenAdjunto(adjunto)
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                        color: AppColors.oceanBlue,
                      ),
                      title: Text(
                        adjunto.nombreArchivo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(adjunto.tamanoLegible),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_esImagenAdjunto(adjunto))
                            IconButton(
                              tooltip: 'Ver imagen',
                              visualDensity: VisualDensity.compact,
                              onPressed: _enviando
                                  ? null
                                  : () => _verImagenAdjuntaExistente(adjunto),
                              icon: const Icon(
                                Icons.visibility_rounded,
                                color: AppColors.oceanBlue,
                                size: 20,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Eliminar ${adjunto.nombreArchivo}',
                            visualDensity: VisualDensity.compact,
                            onPressed: _enviando
                                ? null
                                : () => _eliminarAdjuntoExistente(adjunto),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (_adjuntosSeleccionados.isNotEmpty) ...[
                const SizedBox(height: 6),
                ..._adjuntosSeleccionados.asMap().entries.map((entry) {
                  final index = entry.key;
                  final archivo = entry.value;
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        _esImagenLocal(archivo)
                            ? Icons.image_rounded
                            : Icons.insert_drive_file_outlined,
                        color: AppColors.oceanBlue,
                      ),
                      title: Text(
                        archivo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${(archivo.size / 1024).toStringAsFixed(1)} KB',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_esImagenLocal(archivo))
                            IconButton(
                              tooltip: 'Ver imagen',
                              visualDensity: VisualDensity.compact,
                              onPressed: _enviando
                                  ? null
                                  : () => _verImagenLocal(archivo),
                              icon: const Icon(
                                Icons.visibility_rounded,
                                color: AppColors.oceanBlue,
                                size: 20,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Quitar ${archivo.name}',
                            visualDensity: VisualDensity.compact,
                            onPressed: _enviando
                                ? null
                                : () => setState(() {
                                      _adjuntosSeleccionados.removeAt(index);
                                    }),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              if (_errorAdjuntos != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorAdjuntos!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Botón de Envío
              Row(
                children: [
                  if (widget.onCancelar != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _enviando ? null : widget.onCancelar,
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _enviando ||
                              _cargandoDatos ||
                              _errorCatalogo != null ||
                              _tipos.isEmpty
                          ? null
                          : _enviarFormulario,
                      icon: _enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(_modoEdicion
                              ? Icons.save_rounded
                              : Icons.send_rounded),
                      label: Text(_enviando
                          ? (_modoEdicion
                              ? 'Guardando cambios...'
                              : 'Radicando en el sistema...')
                          : (_modoEdicion ? 'Guardar cambios' : 'Radicar PQR')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
