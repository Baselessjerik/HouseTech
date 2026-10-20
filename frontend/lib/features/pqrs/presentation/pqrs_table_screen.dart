import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_theme.dart';
import '../../../models/pqr_model.dart';
import '../../../services/pqr_service.dart';
import '../pqr_detail_modal.dart';
import 'pqr_adjuntos_dialog.dart';
import 'pqr_form_screen.dart';

/// Pantalla principal para consultar y gestionar los radicados PQR del usuario.
class PqrsTableScreen extends StatefulWidget {
  final PqrService? service;
  final bool puedeGestionarEstados;
  final bool puedeAsignarResponsable;
  final int? usuarioId;
  final bool esAdministrador;

  const PqrsTableScreen({
    super.key,
    this.service,
    this.puedeGestionarEstados = false,
    this.puedeAsignarResponsable = false,
    this.usuarioId,
    this.esAdministrador = false,
  });

  @override
  State<PqrsTableScreen> createState() => _PqrsTableScreenState();
}

/// Controla la carga de solicitudes y las acciones CRUD disponibles en la tabla.
class _PqrsTableScreenState extends State<PqrsTableScreen> {
  late final PqrService _service;
  List<Pqr> _pqrs = [];
  bool _cargando = true;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PqrService();
    _cargarPqrs();
  }

  /// Carga el listado visible y actualiza el indicador de espera de la pantalla.
  Future<void> _cargarPqrs() async {
    setState(() => _cargando = true);
    final lista = await _service.obtenerMisPqrs();
    if (mounted) {
      setState(() {
        _pqrs = lista;
        _cargando = false;
      });
    }
  }

  Future<void> _consultarDetalle(Pqr pqr) async {
    final pqrId = pqr.id;
    if (pqrId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo identificar la solicitud.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      final detalle = await _service.obtenerDetallePqr(pqrId);
      if (!mounted) return;

      setState(() {
        _pqrs = _pqrs
            .map(
                (solicitud) => solicitud.id == detalle.id ? detalle : solicitud)
            .toList();
      });
      verDetalle(
        context,
        detalle,
        service: _service,
        puedeResponder: widget.esAdministrador ||
            (widget.puedeGestionarEstados &&
                detalle.responsableId == widget.usuarioId),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo consultar el estado de la PQR: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Confirma y envía el avance de estado autorizado para gestores.
  Future<void> _confirmarCambioEstado(Pqr pqr) async {
    final pqrId = pqr.id;
    final siguienteEstado = pqr.estado.siguiente;
    final siguienteCodigo = pqr.estado.siguienteCodigo;
    if (!widget.puedeGestionarEstados ||
        pqrId == null ||
        siguienteEstado == null ||
        siguienteCodigo == null) {
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cambiar estado de la PQR'),
        content: Text(
          '¿Deseas avanzar ${pqr.radicado} de '
          '${pqr.estado.label} a ${siguienteEstado.label}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Cambiar a ${siguienteEstado.label}'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      final actualizada = await _service.cambiarEstadoPqr(
        pqrId: pqrId,
        estadoCodigo: siguienteCodigo,
      );
      if (!mounted) return;

      setState(() {
        _pqrs = _pqrs
            .map((solicitud) =>
                solicitud.id == actualizada.id ? actualizada : solicitud)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${pqr.radicado} avanzó a ${actualizada.estado.label}.',
          ),
          backgroundColor: okGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar el estado: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Abre el selector de responsables y actualiza la PQR al confirmar.
  Future<void> _asignarResponsable(Pqr pqr) async {
    if (!widget.puedeAsignarResponsable || pqr.id == null) return;

    final actualizada = await showDialog<Pqr>(
      context: context,
      builder: (_) => _AsignarResponsableDialog(
        pqr: pqr,
        service: _service,
      ),
    );
    if (actualizada == null || !mounted) return;

    setState(() {
      _pqrs = _pqrs
          .map((solicitud) =>
              solicitud.id == actualizada.id ? actualizada : solicitud)
          .toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${actualizada.radicado} asignada a '
          '${actualizada.responsableNombre}.',
        ),
        backgroundColor: okGreen,
      ),
    );
  }

  /// Abre el formulario y refresca el listado cuando se confirma una radicación.
  void _abrirFormularioRadicacion() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            child: PqrFormScreen(
              onCancelar: () => Navigator.pop(dialogCtx),
              onPqrRadicada: () {
                _cargarPqrs();
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Abre el gestor de archivos asociado a la solicitud seleccionada.
  void _abrirAdjuntos(Pqr pqr) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: PqrAdjuntosDialog(pqr: pqr, service: _service),
      ),
    );
  }

  /// Presenta el formulario de edición y refresca la tabla tras guardar.
  void _abrirDialogoEditar(Pqr pqr) {
    if (pqr.id == null) return;
    final asuntoCtrl = TextEditingController(text: pqr.asunto);
    final descCtrl = TextEditingController(text: pqr.descripcion);
    String prioridad = pqr.prioridad;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.oceanBlue),
              const SizedBox(width: 10),
              Text('Editar ${pqr.radicado}'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Asunto *',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: asuntoCtrl,
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'Mínimo 5 caracteres'
                        : null,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Descripción *',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 3,
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Mínimo 10 caracteres'
                        : null,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Prioridad',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: prioridad,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: const [
                      DropdownMenuItem(value: 'BAJA', child: Text('Baja')),
                      DropdownMenuItem(value: 'MEDIA', child: Text('Media')),
                      DropdownMenuItem(value: 'ALTA', child: Text('Alta')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => prioridad = v ?? 'MEDIA'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogCtx);
                final res = await _service.actualizarPqr(
                  id: pqr.id!,
                  tipoId: 1,
                  asunto: asuntoCtrl.text,
                  descripcion: descCtrl.text,
                  prioridad: prioridad,
                );
                if (mounted) {
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('PQR actualizada correctamente'),
                          backgroundColor: okGreen),
                    );
                    _cargarPqrs();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(res['message'].toString()),
                          backgroundColor: Colors.redAccent),
                    );
                  }
                }
              },
              child: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  /// Solicita confirmación y comunica el resultado de eliminar la solicitud.
  void _confirmarEliminar(Pqr pqr) {
    if (pqr.id == null) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Eliminar PQR'),
          ],
        ),
        content: Text(
            '¿Estás seguro de que deseas eliminar la solicitud con radicado ${pqr.radicado}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final res = await _service.eliminarPqr(pqr.id!);
              if (mounted) {
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('PQR eliminada correctamente'),
                        backgroundColor: okGreen),
                  );
                  _cargarPqrs();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(res['message'].toString()),
                        backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// Renderiza búsqueda, acciones y tabla con columnas que ocupan el ancho útil.
  @override
  Widget build(BuildContext context) {
    final filtradas = _pqrs.where((p) {
      final texto = '${p.radicado} ${p.asunto} ${p.tipo}'.toLowerCase();
      return texto.contains(_busqueda.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Encabezado con título y botón de creación
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.puedeGestionarEstados
                      ? 'Gestión de solicitudes PQR'
                      : 'Mis Radicados PQR',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gestiona, consulta y da seguimiento a tus solicitudes radicadas.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: _abrirFormularioRadicacion,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Nueva PQR'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Barra de búsqueda
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (val) => setState(() => _busqueda = val.trim()),
              decoration: const InputDecoration(
                icon: Icon(Icons.search, color: AppColors.oceanBlue),
                hintText: 'Buscar por número de radicado, asunto o tipo...',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Tabla de datos
        Card(
          elevation: 0,
          color: const Color(0xFFF1F4F8),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFD5DDE7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _cargando
              ? const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              : filtradas.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 56, color: Colors.black26),
                          const SizedBox(height: 12),
                          const Text(
                            'No tienes radicados registrados',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Presiona el botón "Nueva PQR" para registrar tu primera petición, queja o reclamo.',
                            style:
                                TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const anchoRadicado = 160.0;
                        const anchoTipo = 80.0;
                        const anchoPrioridad = 100.0;
                        const anchoEstado = 110.0;
                        const anchoResponsable = 180.0;
                        const anchoAcciones = 272.0;
                        const anchoBase = anchoRadicado +
                            anchoTipo +
                            anchoPrioridad +
                            anchoEstado +
                            anchoResponsable +
                            anchoAcciones +
                            60 +
                            24;
                        const anchoMinimoTabla = anchoBase + 120;
                        final anchoTabla =
                            constraints.maxWidth < anchoMinimoTabla
                                ? anchoMinimoTabla
                                : constraints.maxWidth;
                        final anchoAsunto = anchoTabla - anchoBase;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: anchoTabla,
                            child: DataTable(
                              horizontalMargin: 12,
                              columnSpacing: 12,
                              headingRowHeight: 56,
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 56,
                              dividerThickness: 0.6,
                              headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFEDF7FD),
                              ),
                              dataRowColor: WidgetStateProperty.all(
                                const Color(0xFFF1F4F8),
                              ),
                              border: const TableBorder(
                                horizontalInside: BorderSide(
                                  color: Color(0xFFE1E6ED),
                                  width: 0.6,
                                ),
                              ),
                              columns: [
                                DataColumn(
                                  columnWidth:
                                      const FixedColumnWidth(anchoRadicado),
                                  label: const Text(
                                    'Radicado',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth:
                                      const FixedColumnWidth(anchoTipo),
                                  label: const Text(
                                    'Tipo',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth: FixedColumnWidth(anchoAsunto),
                                  label: const Text(
                                    'Asunto',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth:
                                      const FixedColumnWidth(anchoPrioridad),
                                  label: const Text(
                                    'Prioridad',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth:
                                      const FixedColumnWidth(anchoEstado),
                                  label: const Text(
                                    'Estado',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth: const FixedColumnWidth(
                                    anchoResponsable,
                                  ),
                                  label: const Text(
                                    'Responsable',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataColumn(
                                  columnWidth:
                                      const FixedColumnWidth(anchoAcciones),
                                  label: const Text(
                                    'Acciones',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                              rows: filtradas.map((pqr) {
                                return DataRow(
                                  cells: [
                                    // Radicado
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDDE6F5),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          pqr.radicado,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.oceanBlue,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Tipo
                                    DataCell(Text(pqr.tipo)),
                                    // Asunto
                                    DataCell(
                                      Text(
                                        pqr.asunto,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    // Prioridad
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          border: Border.all(
                                            color: const Color(0xFFCBD3DE),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          pqr.prioridad,
                                          style: const TextStyle(
                                            color: Color(0xFF596273),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Estado
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(pqr.estado.icon,
                                              color: pqr.estado.color,
                                              size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            pqr.estado.label,
                                            style: TextStyle(
                                              color: pqr.estado.color,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Tooltip(
                                        message: pqr.responsableNombre ??
                                            'Sin responsable asignado',
                                        child: Text(
                                          pqr.responsableNombre ??
                                              'Sin asignar',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: pqr.responsableNombre == null
                                                ? Colors.black54
                                                : AppColors.textDark,
                                            fontStyle:
                                                pqr.responsableNombre == null
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Acciones CRUD
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip:
                                                'Ver o adjuntar evidencias',
                                            icon: const Icon(
                                              Icons.attach_file_rounded,
                                              size: 19,
                                              color: AppColors.oceanBlue,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 36,
                                            ),
                                            onPressed: () =>
                                                _abrirAdjuntos(pqr),
                                          ),
                                          IconButton(
                                            tooltip: 'Ver detalle',
                                            icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 20,
                                                color: AppColors.oceanBlue),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 36,
                                            ),
                                            onPressed: () =>
                                                _consultarDetalle(pqr),
                                          ),
                                          if (widget.puedeGestionarEstados &&
                                              pqr.estado.siguiente != null)
                                            IconButton(
                                              tooltip:
                                                  'Avanzar a ${pqr.estado.siguiente!.label}',
                                              icon: const Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 19,
                                                color: AppColors.oceanBlue,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 36,
                                              ),
                                              onPressed: () =>
                                                  _confirmarCambioEstado(pqr),
                                            ),
                                          if (widget.puedeAsignarResponsable)
                                            IconButton(
                                              tooltip:
                                                  pqr.responsableNombre == null
                                                      ? 'Asignar responsable'
                                                      : 'Cambiar responsable',
                                              icon: const Icon(
                                                Icons.assignment_ind_outlined,
                                                size: 19,
                                                color: AppColors.oceanBlue,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 36,
                                              ),
                                              onPressed: () =>
                                                  _asignarResponsable(pqr),
                                            ),
                                          IconButton(
                                            tooltip: 'Editar',
                                            icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 19,
                                                color: Color(0xFFF59E0B)),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 36,
                                            ),
                                            onPressed: () =>
                                                _abrirDialogoEditar(pqr),
                                          ),
                                          IconButton(
                                            tooltip: 'Eliminar',
                                            icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 19,
                                                color: Colors.redAccent),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 36,
                                            ),
                                            onPressed: () =>
                                                _confirmarEliminar(pqr),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _AsignarResponsableDialog extends StatefulWidget {
  final Pqr pqr;
  final PqrService service;

  const _AsignarResponsableDialog({
    required this.pqr,
    required this.service,
  });

  @override
  State<_AsignarResponsableDialog> createState() =>
      _AsignarResponsableDialogState();
}

class _AsignarResponsableDialogState extends State<_AsignarResponsableDialog> {
  late Future<List<PqrResponsable>> _responsablesFuture;
  int? _responsableId;
  bool _cargandoResponsables = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _responsableId = widget.pqr.responsableId;
    _responsablesFuture = _cargarResponsables();
  }

  Future<List<PqrResponsable>> _cargarResponsables() async {
    try {
      final responsables = await widget.service.obtenerResponsablesPqr();
      if (mounted) {
        setState(() {
          if (_responsableId != null &&
              !responsables
                  .any((responsable) => responsable.id == _responsableId)) {
            _responsableId = null;
          }
          _cargandoResponsables = false;
        });
      }
      return responsables;
    } catch (_) {
      if (mounted) setState(() => _cargandoResponsables = false);
      rethrow;
    }
  }

  Future<void> _guardar() async {
    final pqrId = widget.pqr.id;
    final responsableId = _responsableId;
    if (pqrId == null ||
        responsableId == null ||
        _cargandoResponsables ||
        _guardando) {
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final actualizada = await widget.service.asignarResponsablePqr(
        pqrId: pqrId,
        responsableId: responsableId,
      );
      if (mounted) Navigator.of(context).pop(actualizada);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No fue posible asignar el responsable: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.pqr.responsableNombre == null
            ? 'Asignar responsable'
            : 'Cambiar responsable',
      ),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<PqrResponsable>>(
          future: _responsablesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No se pudieron cargar los responsables: '
                      '${snapshot.error}'),
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () => setState(() {
                              _cargandoResponsables = true;
                              _responsablesFuture = _cargarResponsables();
                            }),
                    child: const Text('Reintentar'),
                  ),
                ],
              );
            }

            final responsables = snapshot.data ?? const <PqrResponsable>[];
            if (responsables.isEmpty) {
              return const Text(
                'No hay usuarios activos con el rol Responsable de PQR.',
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecciona un usuario activo para ${widget.pqr.radicado}.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _responsableId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Responsable PQR',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final responsable in responsables)
                      DropdownMenuItem(
                        value: responsable.id,
                        child: Text(
                          responsable.email.isEmpty
                              ? responsable.nombreCompleto
                              : '${responsable.nombreCompleto} '
                                  '(${responsable.email})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _guardando
                      ? null
                      : (id) => setState(() => _responsableId = id),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _responsableId == null || _cargandoResponsables || _guardando
                  ? null
                  : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar asignación'),
        ),
      ],
    );
  }
}

/// Consulta el estado más reciente antes de mostrar el detalle de una PQR.
