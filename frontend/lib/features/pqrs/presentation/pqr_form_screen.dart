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

  const PqrFormScreen({
    super.key,
    this.service,
    this.onCancelar,
    this.onPqrRadicada,
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

  TipoPqrModel? _tipoSeleccionado;
  InmuebleOpcionModel? _inmuebleSeleccionado;
  String _prioridadSeleccionada = 'MEDIA';

  bool _cargandoDatos = true;
  bool _enviando = false;
  String? _errorCatalogo;
  String? _errorTipoSolicitud;
  String? _errorAdjuntos;

  @override
  void initState() {
    super.initState();
    _pqrService = widget.service ?? PqrService();
    _cargarCatalogos();
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
        _tipoSeleccionado = null;
        _inmuebleSeleccionado = _inmuebles.isNotEmpty ? _inmuebles.first : null;
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
      final resultado = await _pqrService.radicarPqr(
        tipoId: _tipoSeleccionado!.id,
        asunto: _asuntoCtrl.text,
        descripcion: _descripcionCtrl.text,
        prioridad: _prioridadSeleccionada,
        inmuebleId: _inmuebleSeleccionado?.id,
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        final radicado = resultado['radicado'] as String;
        final pqr = resultado['pqr'] as Pqr?;
        final erroresAdjuntos = <String>[];

        if (_adjuntosSeleccionados.isNotEmpty && pqr?.id == null) {
          erroresAdjuntos.add(
            'No se recibio el identificador de la PQR para asociar los archivos.',
          );
        } else if (pqr?.id != null) {
          for (final archivo in _adjuntosSeleccionados) {
            final carga = await _pqrService.subirAdjuntoPqr(
              pqrId: pqr!.id!,
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
        _mostrarDialogoExito(
          radicado,
          archivosSeleccionados: _adjuntosSeleccionados.length,
          erroresAdjuntos: erroresAdjuntos,
        );
      } else {
        setState(() => _enviando = false);
        _mostrarMensaje(resultado['message'].toString(), esError: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _mostrarMensaje(
        'No fue posible radicar la solicitud: $error',
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rate_review_rounded,
                      color: AppColors.oceanBlue, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Registrar PQR mediante formulario',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  if (widget.onCancelar != null)
                    IconButton(
                      tooltip: 'Cerrar formulario',
                      onPressed: _enviando ? null : widget.onCancelar,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Diligencia este formulario para radicar peticiones, quejas o reclamos ante la administración de la copropiedad.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const Divider(height: 36, color: Colors.black12),

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
                      onSelected: (val) {
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

              // Selector de Inmueble (si el residente tiene inmuebles asignados)
              if (_inmuebles.isNotEmpty) ...[
                const Text('Inmueble relacionado (Opcional)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textDark)),
                const SizedBox(height: 8),
                DropdownButtonFormField<InmuebleOpcionModel>(
                  value: _inmuebleSeleccionado,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.apartment_rounded,
                        color: AppColors.oceanBlue),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
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
                  onChanged: (val) =>
                      setState(() => _inmuebleSeleccionado = val),
                ),
                const SizedBox(height: 20),
              ],

              // Prioridad
              const Text('Nivel de Prioridad',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'BAJA',
                      label: Text('Baja'),
                      icon: Icon(Icons.arrow_downward, size: 16)),
                  ButtonSegment(
                      value: 'MEDIA',
                      label: Text('Media'),
                      icon: Icon(Icons.remove, size: 16)),
                  ButtonSegment(
                      value: 'ALTA',
                      label: Text('Alta'),
                      icon: Icon(Icons.priority_high, size: 16)),
                ],
                selected: {_prioridadSeleccionada},
                onSelectionChanged: (val) =>
                    setState(() => _prioridadSeleccionada = val.first),
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
              if (_adjuntosSeleccionados.isNotEmpty) ...[
                const SizedBox(height: 6),
                ..._adjuntosSeleccionados.asMap().entries.map((entry) {
                  final index = entry.key;
                  final archivo = entry.value;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.insert_drive_file_outlined,
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
                    trailing: IconButton(
                      tooltip: 'Quitar ${archivo.name}',
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
                          : const Icon(Icons.send_rounded),
                      label: Text(_enviando
                          ? 'Radicando en el sistema...'
                          : 'Radicar PQR'),
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
