import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../services/pqr_service.dart';
import '../../services/pqr_file_saver.dart';

/// Abre el detalle desplazable de una PQR, sus respuestas y soluciones.
void verDetalle(
  BuildContext context,
  Pqr p, {
  PqrService? service,
  bool puedeResponder = false,
  bool puedeMarcarSolucion = true,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PqrDetailSheet(
        pqr: p,
        service: service ?? PqrService(),
        puedeResponder: puedeResponder,
        puedeMarcarSolucion: puedeMarcarSolucion,
      ),
    );

class _PqrDetailSheet extends StatefulWidget {
  final Pqr pqr;
  final PqrService service;
  final bool puedeResponder;
  final bool puedeMarcarSolucion;

  const _PqrDetailSheet({
    required this.pqr,
    required this.service,
    required this.puedeResponder,
    required this.puedeMarcarSolucion,
  });

  @override
  State<_PqrDetailSheet> createState() => _PqrDetailSheetState();
}

class _PqrDetailSheetState extends State<_PqrDetailSheet> {
  List<PqrRespuestaModel> _respuestas = [];
  List<PqrHistorialModel> _historial = [];
  List<PqrAdjuntoModel> _adjuntos = [];
  final _respuestaController = TextEditingController();
  final _respuestasScrollController = ScrollController();
  bool _cargandoRespuestas = true;
  bool _cargandoHistorial = true;
  bool _cargandoAdjuntos = true;
  bool _esSolucion = false;
  bool _guardandoRespuesta = false;
  bool _subiendoAdjuntos = false;
  bool get _esSoloLectura =>
      widget.pqr.estado == PqrEstado.resuelto ||
      widget.pqr.estado == PqrEstado.anulado;
  List<PlatformFile> _adjuntosRespuesta = [];
  final Map<int, List<PqrAdjuntoModel>> _adjuntosPorRespuesta = {};
  int _tabIndex = 0;
  String? _errorCargaRespuestas;
  String? _errorCargaHistorial;
  String? _errorCargaAdjuntos;
  String? _errorRespuesta;

  void _scrollRespuestasAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_respuestasScrollController.hasClients) {
        _respuestasScrollController.animateTo(
          _respuestasScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _compositorRespuesta() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Registrar respuesta',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Adjuntar archivos',
                onPressed: _guardandoRespuesta || _subiendoAdjuntos
                    ? null
                    : _seleccionarAdjuntosRespuesta,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryBlue,
                  side: const BorderSide(color: Color(0xFFDDE6EF)),
                  minimumSize: const Size(42, 42),
                ),
                icon: const Icon(Icons.attach_file_rounded, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _respuestaController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 5000,
                  enabled: !_guardandoRespuesta && !_subiendoAdjuntos,
                  decoration: InputDecoration(
                    hintText: 'Escribe una respuesta...',
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDDE6EF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFDDE6EF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: primaryBlue, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    if (_errorRespuesta != null) _errorRespuesta = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_respuestaController.text.trim().isEmpty &&
                            _adjuntosRespuesta.isEmpty) ||
                        _guardandoRespuesta ||
                        _subiendoAdjuntos
                    ? null
                    : _registrarRespuesta,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _guardandoRespuesta || _subiendoAdjuntos
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 17),
                label: const Text(
                  'Enviar respuesta',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_adjuntosRespuesta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final archivo in _adjuntosRespuesta)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDDE6EF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined,
                            size: 17, color: primaryBlue),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            archivo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar archivo',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 26,
                            height: 26,
                          ),
                          onPressed: _guardandoRespuesta
                              ? null
                              : () => setState(() {
                                    _adjuntosRespuesta = List.of(
                                      _adjuntosRespuesta,
                                    )..remove(archivo);
                                  }),
                          icon: const Icon(Icons.close_rounded, size: 15),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (widget.puedeMarcarSolucion)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _guardandoRespuesta
                    ? null
                    : () => setState(() => _esSolucion = !_esSolucion),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _esSolucion,
                          onChanged: _guardandoRespuesta
                              ? null
                              : (value) =>
                                  setState(() => _esSolucion = value ?? false),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Marcar como solución',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_errorRespuesta != null) ...[
            const SizedBox(height: 4),
            Text(
              _errorRespuesta!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _cargarRespuestas();
    _cargarHistorial();
    _cargarAdjuntos();
  }

  @override
  void dispose() {
    _respuestaController.dispose();
    _respuestasScrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarRespuestas() async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) {
      setState(() {
        _cargandoRespuestas = false;
        _errorCargaRespuestas = 'No se pudo identificar esta solicitud.';
      });
      return;
    }

    setState(() {
      _cargandoRespuestas = true;
      _errorCargaRespuestas = null;
    });
    try {
      final respuestas = await widget.service.obtenerRespuestasPqr(pqrId);
      if (!mounted) return;
      setState(() {
        _respuestas = respuestas;
        _cargandoRespuestas = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoRespuestas = false;
        _errorCargaRespuestas = error.toString();
      });
    }
  }

  Future<void> _cargarHistorial() async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) {
      setState(() {
        _cargandoHistorial = false;
      });
      return;
    }

    setState(() {
      _cargandoHistorial = true;
      _errorCargaHistorial = null;
    });
    try {
      final historial = await widget.service.obtenerHistorialPqr(pqrId);
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _cargandoHistorial = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoHistorial = false;
        _errorCargaHistorial = error.toString();
      });
    }
  }

  Future<void> _cargarAdjuntos() async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) {
      setState(() => _cargandoAdjuntos = false);
      return;
    }

    setState(() {
      _cargandoAdjuntos = true;
      _errorCargaAdjuntos = null;
    });
    try {
      final adjuntos = await widget.service.obtenerAdjuntosPqr(pqrId);
      if (!mounted) return;
      setState(() {
        _adjuntos = adjuntos;
        _cargandoAdjuntos = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoAdjuntos = false;
        _errorCargaAdjuntos = error.toString();
      });
    }
  }

  bool _esImagen(PqrAdjuntoModel adjunto) {
    final mime = adjunto.tipoMime.toLowerCase();
    final nombre = adjunto.nombreArchivo.toLowerCase();
    return mime.startsWith('image/') ||
        nombre.endsWith('.jpg') ||
        nombre.endsWith('.jpeg') ||
        nombre.endsWith('.png');
  }

  Future<void> _verImagenAdjunta(PqrAdjuntoModel adjunto) async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) return;

    // Mostrar indicador de carga mientras se obtienen los bytes del archivo
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final bytes = await widget.service.descargarAdjuntoPqr(
        pqrId: pqrId,
        adjuntoId: adjunto.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // Cierra el indicador de carga

      // Abrir el visor de imagen con zoom
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      Navigator.of(context).pop(); // Cierra el indicador de carga si falló
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar la imagen: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _fechaLegible(String fecha) {
    final parsed = DateTime.tryParse(fecha)?.toLocal();
    if (parsed == null) return fecha;
    final dia = parsed.day.toString().padLeft(2, '0');
    final mes = parsed.month.toString().padLeft(2, '0');
    final hora = parsed.hour.toString().padLeft(2, '0');
    final minuto = parsed.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${parsed.year}, $hora:$minuto';
  }

  Future<void> _descargarAdjunto(PqrAdjuntoModel adjunto) async {
    final pqrId = widget.pqr.id;
    if (pqrId == null) return;
    try {
      final bytes = await widget.service.descargarAdjuntoPqr(
        pqrId: pqrId,
        adjuntoId: adjunto.id,
      );
      final guardado = await savePqrFile(adjunto.nombreArchivo, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            guardado
                ? 'Archivo descargado correctamente.'
                : 'No se pudo descargar el archivo.',
          ),
          backgroundColor: guardado ? okGreen : Colors.redAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar el archivo: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _seleccionarAdjuntosRespuesta() async {
    try {
      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: true,
        withData: true,
      );
      if (resultado == null || !mounted) return;

      final validos = <PlatformFile>[];
      final errores = <String>[];
      for (final archivo in resultado.files) {
        if (archivo.size > 10 * 1024 * 1024) {
          errores.add('${archivo.name}: supera el límite de 10 MiB.');
        } else {
          validos.add(archivo);
        }
      }
      setState(() {
        _adjuntosRespuesta = validos;
        _errorRespuesta = errores.isEmpty ? null : errores.join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorRespuesta = 'No se pudieron seleccionar los archivos: $error';
      });
    }
  }

  Future<void> _registrarRespuesta() async {
    final pqrId = widget.pqr.id;
    final texto = _respuestaController.text.trim();
    final archivos = List<PlatformFile>.of(_adjuntosRespuesta);
    if (pqrId == null ||
        (texto.isEmpty && archivos.isEmpty) ||
        _guardandoRespuesta ||
        _subiendoAdjuntos) {
      return;
    }

    setState(() {
      _guardandoRespuesta = true;
      _subiendoAdjuntos = archivos.isNotEmpty;
      _errorRespuesta = null;
      // Inmediatamente vaciar texto y archivos para evitar pulsaciones dobles
      _respuestaController.clear();
      _adjuntosRespuesta = [];
    });

    try {
      var textoRespuesta = texto;
      if (archivos.isNotEmpty) {
        final listado =
            archivos.map((archivo) => '• ${archivo.name}').join('\n');
        textoRespuesta = textoRespuesta.isEmpty
            ? 'Archivos adjuntos enviados:\n$listado'
            : '$textoRespuesta\n\nArchivos adjuntos:\n$listado';
      }
      final nuevaRespuesta = await widget.service.registrarRespuestaPqr(
        pqrId: pqrId,
        respuesta: textoRespuesta,
        esSolucion: _esSolucion,
      );
      if (!mounted) return;

      final erroresAdjuntos = <String>[];
      final adjuntosEnviados = <PqrAdjuntoModel>[];
      if (archivos.isNotEmpty) {
        for (final archivo in archivos) {
          final carga = await widget.service.subirAdjuntoPqr(
            pqrId: pqrId,
            archivo: archivo,
          );
          if (carga['success'] != true) {
            erroresAdjuntos.add(
              '${archivo.name}: ${carga['message'] ?? 'No se pudo cargar.'}',
            );
          } else if (carga['adjunto'] is PqrAdjuntoModel) {
            adjuntosEnviados.add(carga['adjunto'] as PqrAdjuntoModel);
          }
        }
      }
      if (!mounted) return;

      setState(() {
        _esSolucion = false;
        if (!_respuestas.any((r) => r.id == nuevaRespuesta.id)) {
          _respuestas = [..._respuestas, nuevaRespuesta];
        }
        if (adjuntosEnviados.isNotEmpty) {
          _adjuntosPorRespuesta[nuevaRespuesta.id] = adjuntosEnviados;
        }
        if (erroresAdjuntos.isNotEmpty) {
          _errorRespuesta =
              'La respuesta se guardó, pero hubo errores: ${erroresAdjuntos.join("; ")}';
        }
      });

      if (archivos.isNotEmpty) {
        await _cargarAdjuntos();
      }
      await _cargarHistorial();
      _scrollRespuestasAbajo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La respuesta se registró correctamente.'),
          backgroundColor: okGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorRespuesta = 'No fue posible registrar la respuesta: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _guardandoRespuesta = false;
          _subiendoAdjuntos = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pqr;
    final screenSize = MediaQuery.sizeOf(context);
    final modalWidth = screenSize.width >= 948 ? 900.0 : screenSize.width - 32;
    final modalHeight =
        screenSize.height >= 712 ? 680.0 : screenSize.height - 32;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: modalWidth,
        height: modalHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF075985), primaryBlue],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.description_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.radicado,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${p.tipo} · ${_fechaLegible(p.fecha)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            //Banner informativo de solo lectura para expedientes cerrados
            if (_esSoloLectura)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFFEF3C7), // Fondo amarillo suave de aviso
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🔒 Solicitud finalizada. Este expediente se encuentra en modo de solo lectura para fines de auditoría.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compacto = constraints.maxWidth < 720;
                  if (compacto) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _contenidoPrincipal(p, modoCompacto: true),
                          const SizedBox(height: 16),
                          _panelEstado(p),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _contenidoPrincipal(p),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 220,
                          child: _panelEstado(p),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenidoPrincipal(Pqr p, {bool modoCompacto = false}) {
    final tabs = const [
      ('Información', Icons.info_outline_rounded),
      ('Respuestas', Icons.forum_outlined),
      ('Seguimiento', Icons.route_outlined),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FBFE),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Wrap(
              spacing: 6,
              children: [
                for (int index = 0; index < tabs.length; index++)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _tabIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _tabIndex == index
                            ? primaryBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _tabIndex == index
                              ? primaryBlue
                              : const Color(0xFFDCE6EF),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tabs[index].$2,
                            size: 15,
                            color:
                                _tabIndex == index ? Colors.white : primaryBlue,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            tabs[index].$1,
                            style: TextStyle(
                              color: _tabIndex == index
                                  ? Colors.white
                                  : const Color(0xFF334155),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (modoCompacto)
            Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_tabIndex) {
                1 => _vistaRespuestas(modoCompacto: true),
                2 => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _contenidoHistorial(p),
                    ],
                  ),
                _ => _vistaInformacion(p),
              },
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: switch (_tabIndex) {
                  1 => _vistaRespuestas(),
                  2 => SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.timeline_rounded,
                                    size: 18, color: primaryBlue),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Historial de cambios',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: textDark,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Historial cronológico de cambios y eventos',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _contenidoHistorial(p),
                        ],
                      ),
                    ),
                  _ => SingleChildScrollView(
                      child: _vistaInformacion(p),
                    ),
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _vistaInformacion(Pqr p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final columnas = ancho >= 560 ? 3 : (ancho >= 360 ? 2 : 1);
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: (ancho - (10 * (columnas - 1))) / columnas,
                  child: _tarjetaResumen(
                    'Estado',
                    p.estado.label,
                    p.estado.icon,
                    p.estado.color,
                  ),
                ),
                SizedBox(
                  width: (ancho - (10 * (columnas - 1))) / columnas,
                  child: _tarjetaResumen(
                    'Prioridad',
                    _nombrePrioridad(p.prioridad),
                    Icons.flag_rounded,
                    _colorPrioridad(p.prioridad),
                  ),
                ),
                SizedBox(
                  width: (ancho - (10 * (columnas - 1))) / columnas,
                  child: _tarjetaResumen(
                    'Radicación',
                    p.fecha.isEmpty ? 'Pendiente' : _fechaLegible(p.fecha),
                    Icons.calendar_today_rounded,
                    primaryBlue,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.asunto,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                p.descripcion.isEmpty ? 'Sin descripción' : p.descripcion,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final columnas = ancho >= 560 ? 2 : 1;
            final items = [
              ('Tipo', p.tipo, Icons.category_outlined),
              (
                'Solicitante',
                p.solicitanteNombre?.isNotEmpty == true
                    ? p.solicitanteNombre!
                    : 'Usuario autenticado',
                Icons.person_outline_rounded,
              ),
              (
                'Responsable',
                p.responsableNombre?.isNotEmpty == true
                    ? p.responsableNombre!
                    : 'Sin asignar',
                Icons.assignment_ind_outlined,
              ),
              (
                'Fecha de cierre',
                p.fechaCierre?.isNotEmpty == true
                    ? _fechaLegible(p.fechaCierre!)
                    : 'En trámite (abierta)',
                Icons.event_available_outlined,
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in items)
                  SizedBox(
                    width: (ancho - (10 * (columnas - 1))) / columnas,
                    child: _detalleCampoCard(
                      item.$1,
                      item.$2,
                      item.$3,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'ADJUNTOS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 8),
        _contenidoAdjuntos(),
      ],
    );
  }

  String _nombrePrioridad(String prioridad) {
    switch (prioridad.toUpperCase()) {
      case 'ALTA':
        return 'Alta';
      case 'BAJA':
        return 'Baja';
      default:
        return 'Media';
    }
  }

  Color _colorPrioridad(String prioridad) {
    switch (prioridad.toUpperCase()) {
      case 'ALTA':
        return const Color(0xFFDC2626);
      case 'BAJA':
        return primaryBlue;
      default:
        return accentSun;
    }
  }

  Widget _tarjetaResumen(
    String etiqueta,
    String valor,
    IconData icono,
    Color color,
  ) {
    return Container(
      height: 84,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF64748B),
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalleCampoCard(String etiqueta, String valor, IconData icono) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 19, color: primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenidoAdjuntos() {
    if (_cargandoAdjuntos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_errorCargaAdjuntos != null) {
      return TextButton(
        onPressed: _cargarAdjuntos,
        child: const Text('No se pudieron cargar los adjuntos. Reintentar'),
      );
    }
    if (_adjuntos.isEmpty) {
      return const Text(
        'Sin archivos adjuntos',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final adjunto in _adjuntos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F1F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _esImagen(adjunto)
                      ? Icons.image_outlined
                      : Icons.description_outlined,
                  size: 16,
                  color: primaryBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  adjunto.nombreArchivo,
                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_esImagen(adjunto)) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Ver imagen',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    onPressed: () => _verImagenAdjunta(adjunto),
                    icon: const Icon(Icons.visibility_rounded,
                        size: 16, color: primaryBlue),
                  ),
                ],
                IconButton(
                  tooltip: 'Descargar ${adjunto.nombreArchivo}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  onPressed: () => _descargarAdjunto(adjunto),
                  icon: const Icon(Icons.download_rounded,
                      size: 17, color: primaryBlue),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _vistaRespuestas({bool modoCompacto = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryBlue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.forum_rounded, color: primaryBlue, size: 19),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Respuestas y soluciones',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Comunicación relacionada con la solicitud',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        modoCompacto
            ? SizedBox(
                height: 480,
                child: _listaRespuestasConCompositor(),
              )
            : Expanded(
                child: _listaRespuestasConCompositor(),
              ),
      ],
    );
  }

  Widget _listaRespuestasConCompositor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            controller: _respuestasScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _respuestasScrollController,
              primary: false,
              padding: const EdgeInsets.only(right: 6),
              child: _contenidoRespuestas(),
            ),
          ),
        ),
        if (widget.puedeResponder && !_esSoloLectura) ...[
          const SizedBox(height: 10),
          _compositorRespuesta(),
        ],
      ],
    );
  }

  Widget _panelEstado(Pqr p) {
    final estadoActual = PqrEstado.values.indexOf(p.estado);
    final esAnulada = p.estado == PqrEstado.anulado;
    var indicePrevio = -1;
    if (esAnulada) {
      for (final evento in _historial) {
        if (evento.estadoNuevoCodigo?.toUpperCase() == 'ANULADA' &&
            evento.estadoAnteriorCodigo != null) {
          indicePrevio = PqrEstado.values
              .indexOf(PqrEstado.fromCodigo(evento.estadoAnteriorCodigo!));
        }
      }
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF6FF), Color(0xFFF8FAFC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBE7F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.estado.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(p.estado.icon, color: p.estado.color, size: 18),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Estado de la solicitud',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: p.estado.color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: p.estado.color.withValues(alpha: .22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: p.estado.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    p.estado.label,
                    style: TextStyle(
                      color: p.estado.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${estadoActual + 1}/${PqrEstado.values.length}',
                  style: const TextStyle(
                    color: Colors.black45,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < PqrEstado.values.length; index++)
            _estadoItem(
              PqrEstado.values[index].label,
              color: esAnulada
                  ? (index == estadoActual
                      ? PqrEstado.values[index].color
                      : okGreen)
                  : index < estadoActual
                      ? okGreen
                      : index == estadoActual
                          ? PqrEstado.values[index].color
                          : const Color(0xFFF1F5F9),
              activo: esAnulada
                  ? (index <= indicePrevio || index == estadoActual)
                  : index <= estadoActual,
              actual: index == estadoActual,
              icono: PqrEstado.values[index].icon,
            ),
        ],
      ),
    );
  }

  Widget _estadoItem(
    String texto, {
    required Color color,
    required bool activo,
    required bool actual,
    required IconData icono,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: activo ? color : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: actual
                  ? Border.all(color: primaryBlue, width: 2)
                  : Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(
              activo ? icono : Icons.circle_outlined,
              size: 15,
              color: activo ? Colors.white : Colors.black38,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: activo ? textDark : Colors.black38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenidoHistorial(Pqr pqr) {
    if (pqr.id == null) {
      return Column(
        children: [
          for (int i = 0; i < pqr.historial.length; i++)
            Evento(
              pqr.historial[i].$1,
              pqr.historial[i].$2,
              ultimo: i == pqr.historial.length - 1,
              orden: i,
            ),
          if (pqr.historial.isEmpty)
            const _MensajeHistorial(
              mensaje: 'Aún no hay eventos registrados para esta solicitud.',
            ),
        ],
      );
    }

    if (_cargandoHistorial) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorCargaHistorial != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No se pudo cargar el historial: $_errorCargaHistorial',
            style: const TextStyle(color: Colors.redAccent),
          ),
          TextButton(
            onPressed: _cargarHistorial,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (_historial.isEmpty) {
      return const _MensajeHistorial(
        mensaje: 'Aún no hay eventos registrados para esta solicitud.',
      );
    }

    return Column(
      children: [
        for (int i = 0; i < _historial.length; i++)
          _EventoHistorial(
            evento: _historial[i],
            ultimo: i == _historial.length - 1,
          ),
      ],
    );
  }

  List<PqrAdjuntoModel> _adjuntosDeRespuesta(
    PqrRespuestaModel respuesta,
  ) {
    final adjuntosPropios = _adjuntosPorRespuesta[respuesta.id];
    if (adjuntosPropios != null && adjuntosPropios.isNotEmpty) {
      final idsVistos = <int>{};
      return adjuntosPropios.where((a) => idsVistos.add(a.id)).toList();
    }
    if (_adjuntos.isEmpty) return const [];
    final texto = respuesta.respuesta.toLowerCase();
    final idsVistos = <int>{};
    final nombresIncluidos = <String>{};
    return _adjuntos.where((adjunto) {
      final nombre = adjunto.nombreArchivo.toLowerCase();
      if (!texto.contains(nombre) ||
          nombresIncluidos.contains(nombre) ||
          idsVistos.contains(adjunto.id)) {
        return false;
      }
      nombresIncluidos.add(nombre);
      idsVistos.add(adjunto.id);
      return true;
    }).toList();
  }

  String _textoRespuestaVisible(String respuesta) {
    if (respuesta.startsWith('Archivos adjuntos enviados:')) {
      return '';
    }
    final marcador = respuesta.indexOf('\n\nArchivos adjuntos:');
    return marcador >= 0 ? respuesta.substring(0, marcador).trim() : respuesta;
  }

  Widget _contenidoRespuestas() {
    if (_cargandoRespuestas) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorCargaRespuestas != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No se pudieron cargar las respuestas: $_errorCargaRespuestas',
            style: const TextStyle(color: Colors.redAccent),
          ),
          TextButton(
            onPressed: _cargarRespuestas,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (_respuestas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Aún no se han registrado respuestas para esta solicitud.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      children: [
        for (final respuesta in _respuestas)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: respuesta.esSolucion
                    ? okGreen.withValues(alpha: .35)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x080F172A),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: respuesta.esSolucion
                          ? okGreen.withValues(alpha: .12)
                          : primaryBlue.withValues(alpha: .1),
                      child: Icon(
                        respuesta.esSolucion
                            ? Icons.verified_rounded
                            : Icons.support_agent_rounded,
                        size: 15,
                        color: respuesta.esSolucion ? okGreen : primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            respuesta.responsableNombre?.isNotEmpty == true
                                ? respuesta.responsableNombre!
                                : 'Equipo de atención',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fechaLegible(respuesta.fechaCreacion),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (respuesta.esSolucion)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: okGreen.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 13, color: okGreen),
                            SizedBox(width: 4),
                            Text(
                              'Solución',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: okGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Builder(
                  builder: (_) {
                    final textoVisible =
                        _textoRespuestaVisible(respuesta.respuesta);
                    if (textoVisible.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 7),
                      child: Text(
                        textoVisible,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: textDark,
                        ),
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (_) {
                    final archivos = _adjuntosDeRespuesta(respuesta);
                    if (archivos.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final archivo in archivos)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9F1F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _esImagen(archivo)
                                        ? Icons.image_rounded
                                        : Icons.attach_file_rounded,
                                    size: 14,
                                    color: primaryBlue,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    archivo.nombreArchivo,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: primaryBlue,
                                    ),
                                  ),
                                  if (_esImagen(archivo)) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'Ver imagen',
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 26,
                                        height: 26,
                                      ),
                                      onPressed: () =>
                                          _verImagenAdjunta(archivo),
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        size: 15,
                                        color: primaryBlue,
                                      ),
                                    ),
                                  ],
                                  IconButton(
                                    tooltip:
                                        'Descargar ${archivo.nombreArchivo}',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 26,
                                      height: 26,
                                    ),
                                    onPressed: () => _descargarAdjunto(archivo),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 15,
                                      color: primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MensajeHistorial extends StatelessWidget {
  final String mensaje;

  const _MensajeHistorial({required this.mensaje});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            mensaje,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
      );
}

class _EventoHistorial extends StatelessWidget {
  final PqrHistorialModel evento;
  final bool ultimo;

  const _EventoHistorial({
    required this.evento,
    required this.ultimo,
  });

  @override
  Widget build(BuildContext context) {
    final icono = _iconoEvento(evento.comentario);
    final detalle = evento.detalle;
    final actor = evento.actorNombre;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: primaryBlue.withValues(alpha: .1),
                child: Icon(icono, size: 15, color: primaryBlue),
              ),
              if (!ultimo)
                Container(
                  width: 2,
                  height: 38,
                  color: Colors.black12,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: ultimo ? 0 : 16, top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  evento.titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                ),
                if (detalle != null && detalle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
                if (actor != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Por $actor',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _fechaLegible(evento.fecha),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static IconData _iconoEvento(String comentario) {
    final texto = comentario.toLowerCase();
    if (texto.contains('radicada')) return Icons.assignment_outlined;
    if (texto.contains('estado')) return Icons.sync_alt_rounded;
    if (texto.contains('responsable')) return Icons.person_add_alt_1_rounded;
    if (texto.contains('editada')) return Icons.edit_note_rounded;
    if (texto.contains('respuesta')) return Icons.forum_outlined;
    if (texto.contains('adjunto')) return Icons.attach_file_rounded;
    return Icons.history_rounded;
  }

  static String _fechaLegible(String fecha) {
    final parsed = DateTime.tryParse(fecha)?.toLocal();
    if (parsed == null) return fecha;
    final dia = parsed.day.toString().padLeft(2, '0');
    final mes = parsed.month.toString().padLeft(2, '0');
    final hora = parsed.hour.toString().padLeft(2, '0');
    final minuto = parsed.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${parsed.year} · $hora:$minuto';
  }
}

/// Representa un hito individual del historial con una entrada animada.
class Evento extends StatelessWidget {
  final PqrEstado e;
  final String fecha;
  final bool ultimo;
  final int orden;

  const Evento(
    this.e,
    this.fecha, {
    super.key,
    required this.ultimo,
    required this.orden,
  });

  /// Dibuja el marcador, la línea de continuidad y la fecha del hito.
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + orden * 120),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - v)),
            child: child,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: e.color,
                  child: Icon(e.icon, size: 14, color: Colors.white),
                ),
                if (!ultimo)
                  Container(
                    width: 2,
                    height: 36,
                    color: Colors.black12,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textDark,
                      ),
                    ),
                    Text(
                      fecha,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
