import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../comunicados_api.dart';
import '../providers/comunicados_providers.dart';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _dos(int n) => n.toString().padLeft(2, '0');

String fechaCorta(DateTime d) => '${_dos(d.day)} ${_meses[d.month - 1]} ${d.year}';
String horaCorta(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}';
String fechaHora(DateTime d) => '${fechaCorta(d)}, ${horaCorta(d)}';

String rangoFechas(DateTime a, DateTime b) {
  final mismoDia = a.year == b.year && a.month == b.month && a.day == b.day;
  return mismoDia ? '${fechaCorta(a)}, ${horaCorta(a)} – ${horaCorta(b)}' : '${fechaHora(a)} – ${fechaHora(b)}';
}

const colorAlerta = Color(0xFFE4572E);
const colorOk = Color(0xFF16A34A);

void mostrarMensaje(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? colorAlerta : AppColors.textDark,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoConfirmar = 'Confirmar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: colorAlerta) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Etiqueta de color para estados (PUBLICADO, ACTIVO, CANCELADO...).
class EstadoChip extends StatelessWidget {
  const EstadoChip(this.texto, {super.key, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

Color colorEstado(String estado) {
  switch (estado) {
    case 'PUBLICADO':
    case 'ACTIVO':
    case 'EN_CURSO':
    case 'DISPONIBLE':
    case 'FINALIZADO':
      return colorOk;
    case 'PROGRAMADO':
    case 'RESERVADA':
      return AppColors.skyBlue;
    case 'BORRADOR':
      return Colors.blueGrey;
    case 'BLOQUEADA':
    case 'EN_MANTENIMIENTO':
      return const Color(0xFFD97706);
    case 'CANCELADO':
    case 'ARCHIVADO':
      return Colors.grey;
    default:
      return AppColors.oceanBlue;
  }
}

String nombreEstado(String estado) {
  const nombres = {
    'EN_CURSO': 'En curso',
    'EN_MANTENIMIENTO': 'En mantenimiento',
    'BLOQUEADA': 'Bloqueada',
    'RESERVADA': 'Reservada',
    'DISPONIBLE': 'Disponible',
  };
  if (nombres.containsKey(estado)) return nombres[estado]!;
  if (estado.isEmpty) return '';
  return estado[0] + estado.substring(1).toLowerCase();
}

class CargandoCaja extends StatelessWidget {
  const CargandoCaja({super.key});

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
}

class ErrorCaja extends StatelessWidget {
  const ErrorCaja({super.key, required this.mensaje, this.onReintentar});

  final String mensaje;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: colorAlerta, size: 40),
            const SizedBox(height: 8),
            Text(mensaje, textAlign: TextAlign.center),
            if (onReintentar != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: onReintentar, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
            ],
          ]),
        ),
      );
}

/// Lista paginada simple: muestra los elementos como columna (vive dentro del scroll del shell).
class ListaPaginada<T> extends StatelessWidget {
  const ListaPaginada({
    super.key,
    required this.estado,
    required this.itemBuilder,
    required this.vacio,
    required this.onReintentar,
    required this.onMas,
  });

  final ListaState<T> estado;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget vacio;
  final VoidCallback onReintentar;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    if (!estado.cargado && estado.cargando) return const CargandoCaja();
    if (estado.items.isEmpty) {
      if (estado.error != null) return ErrorCaja(mensaje: estado.error!, onReintentar: onReintentar);
      return estado.cargado ? vacio : const CargandoCaja();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in estado.items) ...[itemBuilder(context, item), const SizedBox(height: 12)],
        if (estado.error != null) ErrorCaja(mensaje: estado.error!, onReintentar: onMas),
        if (estado.hayMas)
          Center(
            child: estado.cargando
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                : OutlinedButton(onPressed: onMas, child: const Text('Cargar más')),
          ),
      ],
    );
  }
}

/// Selector de fecha y hora (usa los pickers de Material).
class SelectorFechaHora extends StatelessWidget {
  const SelectorFechaHora({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.opcional = false,
    this.primera,
  });

  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime?> onCambio;
  final bool opcional;
  final DateTime? primera;

  Future<void> _elegir(BuildContext context) async {
    final ahora = DateTime.now();
    final base = valor ?? ahora.add(const Duration(hours: 1));
    final inicio = primera ?? DateTime(ahora.year, ahora.month, ahora.day);
    final fecha = await showDatePicker(
      context: context,
      initialDate: base.isBefore(inicio) ? inicio : base,
      firstDate: inicio.isBefore(base) ? inicio : base.subtract(const Duration(days: 1)),
      lastDate: DateTime(ahora.year + 3),
    );
    if (fecha == null || !context.mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (hora == null) return;
    onCambio(DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _elegir(context),
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            border: const OutlineInputBorder(),
            suffixIcon: opcional && valor != null
                ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onCambio(null))
                : const Icon(Icons.event_rounded),
          ),
          child: Text(valor == null ? 'Seleccionar' : fechaHora(valor!),
              style: TextStyle(color: valor == null ? Colors.black45 : AppColors.textDark)),
        ),
      );
}

class OpcionSelector<T> {
  const OpcionSelector(this.valor, this.etiqueta);

  final T valor;
  final String etiqueta;
}

/// Lista desplegable basada en PopupMenuButton (sin depender de APIs de Dropdown).
class CampoSelector<T> extends StatelessWidget {
  const CampoSelector({
    super.key,
    required this.etiqueta,
    required this.opciones,
    required this.valor,
    required this.onCambio,
    this.habilitado = true,
  });

  final String etiqueta;
  final List<OpcionSelector<T>> opciones;
  final T valor;
  final ValueChanged<T> onCambio;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final actual = opciones.where((o) => o.valor == valor);
    final texto = actual.isEmpty ? 'Seleccionar' : actual.first.etiqueta;
    return PopupMenuButton<T>(
      enabled: habilitado,
      onSelected: onCambio,
      itemBuilder: (_) => [for (final o in opciones) PopupMenuItem<T>(value: o.valor, child: Text(o.etiqueta))],
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          enabled: habilitado,
        ),
        child: Text(texto, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Barra de selección de vista (reemplaza a las pestañas porque el shell ya hace scroll vertical).
class SelectorVista extends StatelessWidget {
  const SelectorVista({super.key, required this.etiquetas, required this.indice, required this.onCambio});

  final List<String> etiquetas;
  final int indice;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (var i = 0; i < etiquetas.length; i++) ButtonSegment<int>(value: i, label: Text(etiquetas[i]))],
          selected: {indice},
          onSelectionChanged: (s) => onCambio(s.first),
        ),
      );
}

class Encabezado extends StatelessWidget {
  const Encabezado({super.key, required this.titulo, required this.subtitulo, this.accion});

  final String titulo;
  final String subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(subtitulo, style: TextStyle(color: Colors.blueGrey.shade700)),
            ]),
          ),
          if (accion != null) accion!,
        ],
      );
}

/// Ejecuta [accion]; si la API avisa de reservas en conflicto (HTTP 409) pide confirmación
/// y la repite con `confirmar = true`. Devuelve true si la operación terminó bien.
Future<bool> ejecutarConConfirmacion(
  BuildContext context,
  Future<void> Function(bool confirmar) accion, {
  required String exito,
}) async {
  try {
    try {
      await accion(false);
    } on ApiException catch (e) {
      if (!e.esConflictoReservas) rethrow;
      if (!context.mounted) return false;
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hay reservas en ese horario'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Si continúas, se avisará a sus dueños para que reprogramen. Reservas afectadas:'),
                const SizedBox(height: 10),
                for (final r in e.reservas)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('• ${r['usuario'] ?? 'Usuario'} · ${_rangoIso(r)}'),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar y avisar')),
          ],
        ),
      );
      if (seguir != true) return false;
      await accion(true);
    }
    if (context.mounted) mostrarMensaje(context, exito);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    return false;
  }
}

String _rangoIso(Map<String, dynamic> r) {
  final a = DateTime.tryParse('${r['fecha_inicio']}')?.toLocal();
  final b = DateTime.tryParse('${r['fecha_fin']}')?.toLocal();
  return a != null && b != null ? rangoFechas(a, b) : '';
}

/// Ejecuta una acción simple mostrando el error en un SnackBar. Devuelve true si salió bien.
Future<bool> ejecutarSimple(BuildContext context, Future<void> Function() accion, {String? exito}) async {
  try {
    await accion();
    if (exito != null && context.mounted) mostrarMensaje(context, exito);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    return false;
  }
}
