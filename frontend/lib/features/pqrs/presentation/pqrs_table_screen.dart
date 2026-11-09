import 'package:flutter/material.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_theme.dart';
import '../../../models/pqr_model.dart';
import '../../../services/pqr_service.dart';
import '../pqr_detail_modal.dart';
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
class _PqrsTableScreenState extends State<PqrsTableScreen>
    with SingleTickerProviderStateMixin {
  late final PqrService _service;
  late final TabController _tabController;
  List<Pqr> _pqrs = [];
  bool _cargando = true;
  String _busqueda = '';
  String? _estadoFiltro;
  String? _usuarioFiltro;
  String? _tipoFiltro;
  String? _responsableFiltro;
  String? _prioridadFiltro;
  DateTime? _fechaInicioFiltro;
  DateTime? _fechaFinFiltro;
  final TextEditingController _busquedaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PqrService();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _cargarPqrs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PqrsTableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final usuarioCambio = oldWidget.usuarioId != widget.usuarioId;
    final permisosCambian = oldWidget.puedeGestionarEstados !=
            widget.puedeGestionarEstados ||
        oldWidget.puedeAsignarResponsable != widget.puedeAsignarResponsable ||
        oldWidget.esAdministrador != widget.esAdministrador;
    final servicioCambia = oldWidget.service != widget.service;
    if (usuarioCambio || permisosCambian || servicioCambia) {
      _service = widget.service ?? PqrService();
      _pqrs = [];
      _cargarPqrs();
    }
  }

  /// Carga el listado visible y actualiza el indicador de espera de la pantalla.
  Future<void> _cargarPqrs() async {
    if (mounted) {
      setState(() => _cargando = true);
    }
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
      var detalle = await _service.obtenerDetallePqr(pqrId);
      if (!mounted) return;

      if (widget.esAdministrador && detalle.estado == PqrEstado.enviado) {
        detalle = await _service.cambiarEstadoPqr(
          pqrId: pqrId,
          estadoCodigo: 'EN_REVISION',
        );
        if (!mounted) return;
      }

      setState(() {
        _pqrs = _pqrs
            .map(
                (solicitud) => solicitud.id == detalle.id ? detalle : solicitud)
            .toList();
      });
      final usuarioId = widget.usuarioId;
      final abierta = detalle.estado != PqrEstado.resuelto &&
          detalle.estado != PqrEstado.anulado;
      final esResponsableAsignado = widget.puedeGestionarEstados &&
          usuarioId != null &&
          detalle.responsableId == usuarioId;
      final esSolicitante =
          usuarioId != null && detalle.solicitanteId == usuarioId;
      verDetalle(
        context,
        detalle,
        service: _service,
        puedeResponder: abierta &&
            (widget.esAdministrador || esResponsableAsignado || esSolicitante),
        puedeMarcarSolucion: widget.esAdministrador || esResponsableAsignado,
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

  Future<void> _cerrarPqr(Pqr pqr) async {
    final pqrId = pqr.id;
    if (!widget.puedeGestionarEstados || pqrId == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Cerrar solicitud'),
        content: Text(
          '¿Confirmas que la PQR ${pqr.radicado} fue atendida y puede cerrarse?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('Cerrar PQR'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      final actualizada = await _service.cambiarEstadoPqr(
        pqrId: pqrId,
        estadoCodigo: 'CERRADA',
      );
      if (!mounted) return;
      setState(() {
        _pqrs = _pqrs
            .map((solicitud) =>
                solicitud.id == actualizada.id ? actualizada : solicitud)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La solicitud fue cerrada correctamente.'),
          backgroundColor: okGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cerrar la solicitud: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _anularPqr(Pqr pqr) async {
    final pqrId = pqr.id;
    if (pqrId == null) return;

    final motivoController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Anular solicitud'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Confirmas anular la PQR ${pqr.radicado}? Esta acción no se puede deshacer y dejará constancia en el historial.',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: motivoController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Motivo de la anulación *',
                  hintText: 'Ej. Duplicada con radicado #QUE-0012 por error.',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 5) {
                    return 'Debes indicar un motivo detallado (mínimo 5 caracteres).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            icon: const Icon(Icons.block_rounded),
            label: const Text('Anular PQR'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    final motivo =
        motivoController.text.trim(); // <--- Aquí se define la variable motivo

    try {
      final actualizada = await _service.cambiarEstadoPqr(
        pqrId: pqrId,
        estadoCodigo: 'ANULADA',
        motivo: motivo,
        // Si tu servicio o backend admite enviar comentario/motivo de transición, inclúyelo aquí:
        // comentario: motivo,
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
              'Solicitud anulada. Motivo: $motivo'), // <--- Uso de la variable 'motivo' para que no marque warning
          backgroundColor: Colors.orangeAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo anular la solicitud: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<bool> _cambiarPrioridad(Pqr pqr, String prioridad) async {
    if (!widget.puedeGestionarEstados || pqr.id == null) return false;
    if (pqr.prioridad.toUpperCase() == prioridad) return true;

    final resultado = await _service.cambiarPrioridadPqr(
      id: pqr.id!,
      prioridad: prioridad,
    );
    if (!mounted) return false;

    if (resultado['success'] == true) {
      final actualizada = resultado['pqr'] as Pqr;
      setState(() {
        _pqrs = _pqrs
            .map((solicitud) =>
                solicitud.id == actualizada.id ? actualizada : solicitud)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${pqr.radicado} ahora tiene prioridad ${prioridad.toLowerCase()}.',
          ),
          backgroundColor: okGreen,
        ),
      );
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado['message']?.toString() ??
                'No fue posible cambiar la prioridad.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return false;
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
              puedeAsignarPrioridad: widget.puedeGestionarEstados,
              onPqrRadicada: () {
                _cargarPqrs();
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Presenta el formulario de edición y refresca la tabla tras guardar.
  void _abrirDialogoEditar(Pqr pqr) {
    if (pqr.id == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            child: PqrFormScreen(
              service: _service,
              pqrInicial: pqr,
              puedeAsignarPrioridad: widget.puedeGestionarEstados,
              onCancelar: () => Navigator.pop(dialogCtx),
              onPqrActualizada: _cargarPqrs,
            ),
          ),
        ),
      ),
    );
  }

  bool get _hayFiltrosActivos =>
      _estadoFiltro != null ||
      _usuarioFiltro != null ||
      _tipoFiltro != null ||
      _responsableFiltro != null ||
      _prioridadFiltro != null ||
      _fechaInicioFiltro != null ||
      _fechaFinFiltro != null;

  Widget _botonLimpiarFiltros() {
    return OutlinedButton.icon(
      onPressed: _hayFiltrosActivos
          ? () => setState(() {
                _estadoFiltro = null;
                _usuarioFiltro = null;
                _tipoFiltro = null;
                _responsableFiltro = null;
                _prioridadFiltro = null;
                _fechaInicioFiltro = null;
                _fechaFinFiltro = null;
              })
          : null,
      icon: Icon(
        _hayFiltrosActivos ? Icons.filter_alt_off_rounded : Icons.tune_rounded,
        size: 18,
      ),
      label:
          Text(_hayFiltrosActivos ? 'Limpiar filtros' : 'Sin filtros activos'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: AppColors.textDark,
        side: const BorderSide(color: Color(0xFFD7DFE8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _filtroDesplegable({
    required String label,
    required String? value,
    required List<String> opciones,
    required ValueChanged<String?> onChanged,
    bool valueLabels = false,
    bool mostrarPrioridad = false,
  }) {
    String? textoSeleccionado;
    if (value != null) {
      for (final opcion in opciones) {
        if (valueLabels && opcion.contains('|')) {
          final partes = opcion.split('|');
          if (partes.first == value) {
            textoSeleccionado = partes.last;
            break;
          }
        } else if (opcion == value) {
          textoSeleccionado = mostrarPrioridad
              ? '${value[0]}${value.substring(1).toLowerCase()}'
              : value;
        }
      }
    }

    return PopupMenuButton<String>(
      onSelected: (opcion) => onChanged(opcion == '__TODOS__' ? null : opcion),
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          value: '__TODOS__',
          child: Text('Todos'),
        ),
        for (final opcion in opciones)
          PopupMenuItem<String>(
            value: valueLabels ? opcion.split('|').first : opcion,
            child: Text(
              valueLabels ? opcion.split('|').last : opcion,
            ),
          ),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value == null ? Colors.white : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                value == null ? const Color(0xFFD7DFE8) : AppColors.oceanBlue,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              textoSeleccionado == null ? label : '$label: $textoSeleccionado',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: value == null ? AppColors.textDark : AppColors.oceanBlue,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
          ],
        ),
      ),
    );
  }

  /// Formatea una fecha como dd/MM/yyyy.
  static String _formatearFechaCorta(DateTime fecha) {
    final day = fecha.day.toString().padLeft(2, '0');
    final month = fecha.month.toString().padLeft(2, '0');
    return '$day/$month/${fecha.year}';
  }

  /// Abre un selector de rango de fechas compacto y actualiza los filtros al confirmar.
  Future<void> _seleccionarRangoFechas() async {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    DateTime inicio =
        _fechaInicioFiltro ?? hoy.subtract(const Duration(days: 30));
    DateTime fin = _fechaFinFiltro ?? hoy;

    if (inicio.isAfter(fin)) {
      inicio = fin.subtract(const Duration(days: 30));
    }
    if (fin.isAfter(hoy)) {
      fin = hoy;
    }
    if (inicio.isAfter(hoy)) {
      inicio = hoy;
    }

    final rangoInicial = DateTimeRange(start: inicio, end: fin);

    final rangoSeleccionado = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: hoy,
      initialDateRange: rangoInicial,
      helpText: 'Seleccionar rango de fechas',
      cancelText: 'Cancelar',
      confirmText: 'Filtrar',
      builder: (BuildContext context, Widget? child) {
        if (child == null) return const SizedBox.shrink();

        final mediaQuery = MediaQuery.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.oceanBlue,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppColors.textDark,
                ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.oceanBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 400,
                maxHeight: 520,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MediaQuery(
                  data: mediaQuery.copyWith(
                    size: const Size(400, 520),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );

    if (rangoSeleccionado != null) {
      setState(() {
        _fechaInicioFiltro = rangoSeleccionado.start;
        _fechaFinFiltro = rangoSeleccionado.end;
      });
    }
  }

  /// Renderiza el botón de filtro de fechas con el rango seleccionado.
  Widget _botonFiltroFechas() {
    String textoBoton = 'Fecha';
    if (_fechaInicioFiltro != null && _fechaFinFiltro != null) {
      final inicio = _formatearFechaCorta(_fechaInicioFiltro!);
      final fin = _formatearFechaCorta(_fechaFinFiltro!);
      textoBoton = (inicio == fin) ? inicio : '$inicio - $fin';
    } else if (_fechaInicioFiltro != null) {
      textoBoton = 'Desde ${_formatearFechaCorta(_fechaInicioFiltro!)}';
    } else if (_fechaFinFiltro != null) {
      textoBoton = 'Hasta ${_formatearFechaCorta(_fechaFinFiltro!)}';
    }

    final activo = _fechaInicioFiltro != null || _fechaFinFiltro != null;

    return InkWell(
      onTap: _seleccionarRangoFechas,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: activo ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: activo ? AppColors.oceanBlue : const Color(0xFFD7DFE8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 16,
              color: activo ? AppColors.oceanBlue : AppColors.textDark,
            ),
            const SizedBox(width: 6),
            Text(
              textoBoton,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: activo ? AppColors.oceanBlue : AppColors.textDark,
              ),
            ),
            const SizedBox(width: 4),
            if (activo)
              Tooltip(
                message: 'Quitar filtro de fecha',
                child: InkWell(
                  onTap: () => setState(() {
                    _fechaInicioFiltro = null;
                    _fechaFinFiltro = null;
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: AppColors.oceanBlue,
                    ),
                  ),
                ),
              )
            else
              const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
          ],
        ),
      ),
    );
  }

  /// Renderiza búsqueda, acciones y tarjetas con filtros de listado.
  @override
  Widget build(BuildContext context) {
    final inicioFiltroOnly = _fechaInicioFiltro == null
        ? null
        : DateTime(_fechaInicioFiltro!.year, _fechaInicioFiltro!.month,
            _fechaInicioFiltro!.day);
    final finFiltroOnly = _fechaFinFiltro == null
        ? null
        : DateTime(_fechaFinFiltro!.year, _fechaFinFiltro!.month,
            _fechaFinFiltro!.day);

    final filtradas = _pqrs.where((p) {
      final esFinalizada =
          p.estado == PqrEstado.resuelto || p.estado == PqrEstado.anulado;
      if (_tabController.index == 0 && esFinalizada) return false;
      if (_tabController.index == 1 && !esFinalizada) return false;

      final texto =
          '${p.radicado} ${p.asunto} ${p.tipo} ${p.solicitanteNombre ?? ''} ${p.responsableNombre ?? ''}'
              .toLowerCase();
      final coincideBusqueda = texto.contains(_busqueda.toLowerCase());
      final coincideEstado =
          _estadoFiltro == null || p.estado.label == _estadoFiltro;
      final coincideUsuario = _usuarioFiltro == null ||
          (_usuarioFiltro == '__SIN_USUARIO__'
              ? p.solicitanteNombre == null ||
                  p.solicitanteNombre!.trim().isEmpty
              : p.solicitanteNombre == _usuarioFiltro);
      final coincideTipo = _tipoFiltro == null || p.tipo == _tipoFiltro;
      final coincideResponsable = _responsableFiltro == null ||
          (_responsableFiltro == '__SIN_ASIGNAR__'
              ? p.responsableNombre == null ||
                  p.responsableNombre!.trim().isEmpty
              : p.responsableNombre == _responsableFiltro);
      final coincidePrioridad = _prioridadFiltro == null ||
          p.prioridad.toUpperCase() == _prioridadFiltro;

      bool coincideFecha = true;
      if (inicioFiltroOnly != null || finFiltroOnly != null) {
        final fechaPqrStr = p.fecha.trim();
        final fechaPqr = DateTime.tryParse(fechaPqrStr);
        if (fechaPqr != null) {
          final localDate = fechaPqr.toLocal();
          final pqrDateOnly =
              DateTime(localDate.year, localDate.month, localDate.day);
          if (inicioFiltroOnly != null &&
              pqrDateOnly.isBefore(inicioFiltroOnly)) {
            coincideFecha = false;
          }
          if (finFiltroOnly != null && pqrDateOnly.isAfter(finFiltroOnly)) {
            coincideFecha = false;
          }
        } else {
          coincideFecha = false;
        }
      }

      return coincideBusqueda &&
          coincideEstado &&
          coincideUsuario &&
          coincideTipo &&
          coincideResponsable &&
          coincidePrioridad &&
          coincideFecha;
    }).toList();
    final usuarios = {
      for (final pqr in _pqrs)
        if (pqr.solicitanteNombre?.trim().isNotEmpty == true)
          pqr.solicitanteNombre!.trim(),
    }.toList()
      ..sort();
    final tipos = {
      for (final pqr in _pqrs) pqr.tipo,
    }.toList()
      ..sort();
    final responsables = {
      for (final pqr in _pqrs)
        if (pqr.responsableNombre?.trim().isNotEmpty == true)
          pqr.responsableNombre!.trim(),
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Encabezado con título y botón de creación
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
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
              controller: _busquedaController,
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

        //Pestañas de separación visual (Activas vs Historial)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _tabController.index = 0;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tabController.index == 0
                          ? AppColors.oceanBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Bandeja Activa',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _tabController.index == 0
                            ? Colors.white
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _tabController.index = 1;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tabController.index == 1
                          ? AppColors.oceanBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Historial',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _tabController.index == 1
                            ? Colors.white
                            : AppColors.textDark,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7DFE8)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(
                  Icons.filter_list_rounded,
                  size: 18,
                  color: AppColors.oceanBlue,
                ),
                const SizedBox(width: 7),
                const Text(
                  'Filtros',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 12),
                _filtroDesplegable(
                  label: 'Estado',
                  value: _estadoFiltro,
                  opciones: [
                    for (final estado in PqrEstado.values) estado.label,
                  ],
                  onChanged: (value) => setState(() => _estadoFiltro = value),
                ),
                const SizedBox(width: 8),
                _filtroDesplegable(
                  label: 'Usuario',
                  value: _usuarioFiltro,
                  opciones: [
                    '__SIN_USUARIO__|Sin usuario',
                    for (final usuario in usuarios) '$usuario|$usuario',
                  ],
                  valueLabels: true,
                  onChanged: (value) => setState(() => _usuarioFiltro = value),
                ),
                const SizedBox(width: 8),
                _filtroDesplegable(
                  label: 'Tipo',
                  value: _tipoFiltro,
                  opciones: [
                    for (final tipo in tipos) tipo,
                  ],
                  onChanged: (value) => setState(() => _tipoFiltro = value),
                ),
                const SizedBox(width: 8),
                _filtroDesplegable(
                  label: 'Responsable',
                  value: _responsableFiltro,
                  opciones: [
                    '__SIN_ASIGNAR__|Sin asignar',
                    for (final responsable in responsables)
                      '$responsable|$responsable',
                  ],
                  valueLabels: true,
                  onChanged: (value) =>
                      setState(() => _responsableFiltro = value),
                ),
                const SizedBox(width: 8),
                _filtroDesplegable(
                  label: 'Prioridad',
                  value: _prioridadFiltro,
                  opciones: const ['BAJA', 'MEDIA', 'ALTA'],
                  mostrarPrioridad: true,
                  onChanged: (value) =>
                      setState(() => _prioridadFiltro = value),
                ),
                const SizedBox(width: 8),
                _botonFiltroFechas(),
                const SizedBox(width: 12),
                _botonLimpiarFiltros(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Listado responsivo de solicitudes
        if (_cargando)
          Card(
            elevation: 0,
            color: const Color(0xFFF8FAFC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFD5DDE7)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (filtradas.isEmpty)
          Card(
            elevation: 0,
            color: const Color(0xFFF8FAFC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFD5DDE7)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: Colors.black26),
                  SizedBox(height: 12),
                  Text(
                    'No tienes radicados registrados',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Presiona el botón "Nueva PQR" para registrar tu primera petición, queja o reclamo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1500
                  ? 5
                  : constraints.maxWidth >= 1180
                      ? 4
                      : constraints.maxWidth >= 900
                          ? 3
                          : constraints.maxWidth >= 560
                              ? 2
                              : 1;
              final calculatedWidth =
                  (constraints.maxWidth - (16 * (columns - 1))) / columns;
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : calculatedWidth.clamp(230.0, 260.0);
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  for (final pqr in filtradas)
                    SizedBox(
                      width: cardWidth,
                      child: _PqrCard(
                        key: ValueKey(
                          'pqr-${pqr.id ?? pqr.radicado}',
                        ),
                        pqr: pqr,
                        puedeGestionarEstados: widget.puedeGestionarEstados,
                        puedeAsignarResponsable: widget.puedeAsignarResponsable,
                        esAdministrador: widget.esAdministrador,
                        usuarioId: widget.usuarioId,
                        onVerDetalle: () => _consultarDetalle(pqr),
                        onAsignar: () => _asignarResponsable(pqr),
                        onCerrar: () => _cerrarPqr(pqr),
                        onAnular: () => _anularPqr(pqr),
                        onPrioridadChanged: (prioridad) =>
                            _cambiarPrioridad(pqr, prioridad),
                        onEditar: () => _abrirDialogoEditar(pqr),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _PqrCard extends StatefulWidget {
  final Pqr pqr;
  final bool puedeGestionarEstados;
  final bool puedeAsignarResponsable;
  final bool esAdministrador;
  final int? usuarioId;
  final VoidCallback onVerDetalle;
  final VoidCallback onAsignar;
  final VoidCallback onCerrar;
  final Future<bool> Function(String) onPrioridadChanged;
  final VoidCallback onEditar;
  final VoidCallback onAnular;

  const _PqrCard({
    super.key,
    required this.pqr,
    required this.puedeGestionarEstados,
    required this.puedeAsignarResponsable,
    required this.esAdministrador,
    this.usuarioId,
    required this.onVerDetalle,
    required this.onAsignar,
    required this.onCerrar,
    required this.onPrioridadChanged,
    required this.onEditar,
    required this.onAnular,
  });

  @override
  State<_PqrCard> createState() => _PqrCardState();
}

class _PqrCardState extends State<_PqrCard> {
  late String _prioridadLocal;
  bool _guardandoPrioridad = false;

  Pqr get pqr => widget.pqr;
  bool get puedeGestionarEstados => widget.puedeGestionarEstados;
  bool get puedeAsignarResponsable => widget.puedeAsignarResponsable;
  VoidCallback get onVerDetalle => widget.onVerDetalle;
  VoidCallback get onAsignar => widget.onAsignar;
  VoidCallback get onCerrar => widget.onCerrar;
  Future<bool> Function(String) get onPrioridadChanged =>
      widget.onPrioridadChanged;
  VoidCallback get onEditar => widget.onEditar;

  @override
  void initState() {
    super.initState();
    _prioridadLocal = _normalizarPrioridad(pqr.prioridad);
  }

  @override
  void didUpdateWidget(covariant _PqrCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cambioDePqr = oldWidget.pqr.id != widget.pqr.id ||
        oldWidget.pqr.radicado != widget.pqr.radicado;
    final cambioExterno = oldWidget.pqr.prioridad.toUpperCase() !=
        widget.pqr.prioridad.toUpperCase();

    if ((cambioDePqr || cambioExterno) && !_guardandoPrioridad) {
      _prioridadLocal = _normalizarPrioridad(widget.pqr.prioridad);
    }
  }

  String _normalizarPrioridad(String prioridad) {
    final valor = prioridad.trim().toUpperCase();
    if (valor == 'BAJA' || valor == 'MEDIA' || valor == 'ALTA') {
      return valor;
    }
    return 'MEDIA';
  }

  String _fecha() {
    final value = pqr.fecha.trim();
    if (value.isEmpty) return 'Fecha no disponible';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return _PqrsTableScreenState._formatearFechaCorta(parsed.toLocal());
  }

  Color _prioridadColor() {
    switch (_prioridadLocal) {
      case 'ALTA':
        return Colors.redAccent;
      case 'MEDIA':
        return AppColors.sunYellow;
      default:
        return AppColors.oceanBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esCerrada = pqr.estado.label.toLowerCase() == 'cerrada';
    final bool esAnulada = pqr.estado == PqrEstado.anulado;
    final bool bloqueada = esCerrada || esAnulada;
    final usuarioId = widget.usuarioId;
    final esResponsableAsignado = puedeGestionarEstados &&
        usuarioId != null &&
        pqr.responsableId == usuarioId;
    final esSolicitante = usuarioId != null && pqr.solicitanteId == usuarioId;
    final enEtapaInicial =
        pqr.estado == PqrEstado.enviado || pqr.estado == PqrEstado.recibido;
    final puedeEditar =
        puedeGestionarEstados || pqr.estado == PqrEstado.enviado;
    final puedeCerrar = !bloqueada &&
        pqr.estado == PqrEstado.respondido &&
        (widget.esAdministrador || esResponsableAsignado);
    final puedeAnular = !bloqueada &&
        (widget.esAdministrador ||
            ((esSolicitante || esResponsableAsignado) && enEtapaInicial));
    final mostrarAcciones = !bloqueada &&
        (puedeAsignarResponsable || puedeEditar || puedeCerrar || puedeAnular);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color:
                esCerrada ? const Color(0xFFCBD5E1) : const Color(0xFFD8E2EC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onVerDetalle,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FD),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      pqr.radicado,
                      style: const TextStyle(
                        color: AppColors.oceanBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: pqr.estado.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          esCerrada
                              ? Icons.lock_outline_rounded
                              : pqr.estado.icon,
                          size: 16,
                          color: pqr.estado.color,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          pqr.estado.label,
                          style: TextStyle(
                            color: pqr.estado.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Fecha: ${_fecha()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              _PqrCardRow(
                label: 'Usuario',
                value: pqr.solicitanteNombre?.trim().isNotEmpty == true
                    ? pqr.solicitanteNombre!
                    : 'No disponible',
              ),
              const SizedBox(height: 6),
              _PqrCardRow(label: 'Tipo', value: pqr.tipo),
              const SizedBox(height: 6),
              _PqrCardRow(label: 'Asunto', value: pqr.asunto),
              const SizedBox(height: 6),
              _PqrCardRow(
                label: 'Responsable',
                value: pqr.responsableNombre?.trim().isNotEmpty == true
                    ? pqr.responsableNombre!
                    : 'Sin asignar',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (puedeGestionarEstados && !bloqueada)
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: _prioridadColor().withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _prioridadColor().withValues(alpha: .55),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _prioridadLocal,
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: _prioridadColor(),
                          ),
                          style: TextStyle(
                            color: _prioridadColor(),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'BAJA', child: Text('Baja')),
                            DropdownMenuItem(
                                value: 'MEDIA', child: Text('Media')),
                            DropdownMenuItem(
                                value: 'ALTA', child: Text('Alta')),
                          ],
                          onChanged: _guardandoPrioridad
                              ? null
                              : (prioridad) async {
                                  if (prioridad == null ||
                                      prioridad == _prioridadLocal) {
                                    return;
                                  }
                                  final anterior = _prioridadLocal;
                                  setState(() {
                                    _prioridadLocal = prioridad;
                                    _guardandoPrioridad = true;
                                  });
                                  final guardado =
                                      await onPrioridadChanged(prioridad);
                                  if (!mounted) return;
                                  setState(() {
                                    _guardandoPrioridad = false;
                                    if (!guardado) {
                                      _prioridadLocal = anterior;
                                    }
                                  });
                                },
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _prioridadColor().withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _prioridadColor().withValues(alpha: .55),
                        ),
                      ),
                      child: Text(
                        pqr.prioridad,
                        style: TextStyle(
                          color: _prioridadColor(),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: onVerDetalle,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Ver solicitud'),
                  ),
                ],
              ),
              if (mostrarAcciones) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (puedeAsignarResponsable)
                      IconButton(
                        tooltip: 'Asignar responsable',
                        onPressed: onAsignar,
                        icon: const Icon(Icons.assignment_ind_outlined),
                      ),
                    if (puedeEditar)
                      IconButton(
                        tooltip: 'Editar solicitud',
                        onPressed: onEditar,
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    if (puedeCerrar)
                      IconButton(
                        tooltip: 'Cerrar solicitud',
                        onPressed: onCerrar,
                        icon: const Icon(
                          Icons.task_alt_rounded,
                          color: okGreen,
                        ),
                      ),
                    if (puedeAnular)
                      IconButton(
                        tooltip: 'Anular solicitud',
                        onPressed: widget.onAnular,
                        icon: const Icon(
                          Icons.block_rounded,
                          color: Colors.redAccent,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PqrCardRow extends StatelessWidget {
  final String label;
  final String value;

  const _PqrCardRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 13,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
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
  final TextEditingController _busquedaController = TextEditingController();
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

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
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

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    final primera = partes.first.substring(0, 1).toUpperCase();
    final segunda = partes.length > 1 && partes[1].isNotEmpty
        ? partes[1].substring(0, 1).toUpperCase()
        : '';
    return '$primera$segunda';
  }

  // Renderiza el diálogo para asignar o cambiar el responsable de la PQR.
  // ... dentro de _AsignarResponsableDialogState
  @override
  Widget build(BuildContext context) {
    final tieneResponsable =
        widget.pqr.responsableNombre?.trim().isNotEmpty == true;
    final titulo =
        tieneResponsable ? 'Cambiar responsable' : 'Asignar responsable';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Cabecera fija
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.oceanBlue,
                    AppColors.oceanBlue.withValues(alpha: .82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.assignment_ind_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Define la persona encargada de gestionar la solicitud.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed:
                        _guardando ? null : () => Navigator.of(context).pop(),
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            // 2. Contenido principal (Estático: PQR info y buscador)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: FutureBuilder<List<PqrResponsable>>(
                future: _responsablesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'No se pudieron cargar los responsables: ${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _guardando
                              ? null
                              : () => setState(() {
                                    _cargandoResponsables = true;
                                    _responsablesFuture = _cargarResponsables();
                                  }),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    );
                  }

                  final responsables =
                      snapshot.data ?? const <PqrResponsable>[];
                  if (responsables.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: .35)),
                      ),
                      child: const Text(
                        'No hay usuarios activos con el rol Responsable de PQR.',
                      ),
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.bgLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.oceanBlue.withValues(alpha: .12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.pqr.radicado,
                              style: const TextStyle(
                                color: AppColors.oceanBlue,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.pqr.asunto,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Responsable actual: '
                              '${tieneResponsable ? widget.pqr.responsableNombre : "Sin asignar"}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _busquedaController,
                        enabled: !_guardando,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Buscar responsable',
                          hintText: 'Nombre o correo electrónico',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.oceanBlue,
                          ),
                          suffixIcon: _busquedaController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: _guardando
                                      ? null
                                      : () {
                                          _busquedaController.clear();
                                          setState(() {});
                                        },
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 3. Contenedor de la tabla con scroll interno exclusivo (recuadro rojo)
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: FutureBuilder<List<PqrResponsable>>(
                  future: _responsablesFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final responsables = snapshot.data!;
                    final consulta =
                        _busquedaController.text.trim().toLowerCase();
                    final filtrados = responsables.where((responsable) {
                      if (consulta.isEmpty) return true;
                      return responsable.nombreCompleto
                              .toLowerCase()
                              .contains(consulta) ||
                          responsable.email.toLowerCase().contains(consulta);
                    }).toList();

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.oceanBlue.withValues(alpha: .14),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: AppColors.bgLight,
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Responsable',
                                    style: TextStyle(
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${filtrados.length} ${filtrados.length == 1 ? "resultado" : "resultados"}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Seleccionar',
                                  style: TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (filtrados.isEmpty)
                            const Expanded(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'No se encontraron responsables con esa búsqueda.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                shrinkWrap: false,
                                itemCount: filtrados.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final responsable = filtrados[index];
                                  final seleccionado =
                                      _responsableId == responsable.id;

                                  return Material(
                                    color: seleccionado
                                        ? AppColors.oceanBlue
                                            .withValues(alpha: .08)
                                        : Colors.transparent,
                                    child: InkWell(
                                      onTap: _guardando
                                          ? null
                                          : () => setState(() {
                                                _responsableId = responsable.id;
                                                _error = null;
                                              }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: AppColors
                                                  .oceanBlue
                                                  .withValues(alpha: .12),
                                              child: Text(
                                                _iniciales(
                                                  responsable.nombreCompleto,
                                                ),
                                                style: const TextStyle(
                                                  color: AppColors.oceanBlue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    responsable.nombreCompleto,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: AppColors.textDark,
                                                      fontWeight: seleccionado
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  if (responsable
                                                      .email.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 2),
                                                      child: Text(
                                                        responsable.email,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.black54,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Icon(
                                              seleccionado
                                                  ? Icons.check_circle_rounded
                                                  : Icons
                                                      .radio_button_unchecked_rounded,
                                              color: seleccionado
                                                  ? AppColors.oceanBlue
                                                  : Colors.black38,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

            // 4. Pie de página fijo con los botones de acción
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _guardando ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _responsableId == null || _guardando
                          ? null
                          : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _guardando ? 'Guardando...' : 'Guardar asignación',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
