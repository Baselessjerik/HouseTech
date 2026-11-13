import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../comunicados/widgets/ui.dart' show fechaCorta;

/// Preferencia de formato de hora del Módulo 3: 24 h (militar) o 12 h (a. m. / p. m.).
///
/// Se guarda en el dispositivo, así que se mantiene entre sesiones.
class FormatoHora {
  FormatoHora._();

  /// `true` = 24 h (militar); `false` = a. m. / p. m. (predeterminado).
  static final ValueNotifier<bool> usar24h = ValueNotifier<bool>(false);

  static const _clave = 'reservas_formato_hora_24h';
  static const _storage = FlutterSecureStorage();
  static bool _cargado = false;

  static Future<void> cargar() async {
    if (_cargado) return;
    _cargado = true;
    try {
      final valor = await _storage.read(key: _clave);
      if (valor != null) usar24h.value = valor == '1';
    } catch (_) {
      // Sin almacenamiento disponible (p. ej. pruebas): se usa el valor por defecto.
    }
  }

  static Future<void> cambiar(bool valor24h) async {
    usar24h.value = valor24h;
    try {
      await _storage.write(key: _clave, value: valor24h ? '1' : '0');
    } catch (_) {}
  }
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// Formatea una hora según la preferencia: `14:30` o `2:30 p. m.`
String formatoHora(int hora, int minuto) {
  if (FormatoHora.usar24h.value) return '${_dos(hora)}:${_dos(minuto)}';
  final h12 = hora % 12 == 0 ? 12 : hora % 12;
  return '$h12:${_dos(minuto)} ${hora < 12 ? 'a. m.' : 'p. m.'}';
}

String horaDe(DateTime d) => formatoHora(d.hour, d.minute);

String horaDeTime(TimeOfDay t) => formatoHora(t.hour, t.minute);

/// Convierte un texto `HH:MM` del backend al formato elegido.
String horaDeTexto(String hhmm) {
  final partes = hhmm.split(':');
  if (partes.length < 2) return hhmm;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null) return hhmm;
  return formatoHora(h, m);
}

String fechaHoraDe(DateTime d) => '${fechaCorta(d)}, ${horaDe(d)}';

/// Selector de hora que respeta el formato elegido (reloj de 24 h o de 12 h).
Future<TimeOfDay?> elegirHora(BuildContext context, TimeOfDay inicial) => showTimePicker(
      context: context,
      initialTime: inicial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: FormatoHora.usar24h.value),
        child: child!,
      ),
    );

/// Interruptor "24 h / a. m.-p. m." para la barra superior de las pantallas de reservas.
class SelectorFormatoHora extends StatelessWidget {
  const SelectorFormatoHora({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: FormatoHora.usar24h,
        builder: (_, usar24h, __) => Tooltip(
          message: 'Formato de hora',
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('a. m./p. m.')),
              ButtonSegment(value: true, label: Text('24 h')),
            ],
            selected: {usar24h},
            onSelectionChanged: (s) => FormatoHora.cambiar(s.first),
          ),
        ),
      );
}

// --- Búsqueda ---------------------------------------------------------------------------

String _normalizar(String texto) {
  const con = 'áéíóúüñÁÉÍÓÚÜÑ';
  const sin = 'aeiouunAEIOUUN';
  final b = StringBuffer();
  for (final c in texto.split('')) {
    final i = con.indexOf(c);
    b.write(i >= 0 ? sin[i] : c);
  }
  return b.toString().toLowerCase().trim();
}

/// `true` si todas las palabras de [consulta] aparecen en alguno de los [campos]
/// (sin distinguir mayúsculas ni tildes).
bool coincideBusqueda(String consulta, List<String?> campos) {
  final palabras = _normalizar(consulta).split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (palabras.isEmpty) return true;
  final texto = _normalizar(campos.whereType<String>().join(' '));
  return palabras.every(texto.contains);
}

/// Barra de búsqueda de la parte superior de las pantallas de reservas.
class BarraBusquedaReservas extends StatelessWidget {
  const BarraBusquedaReservas({
    super.key,
    required this.controlador,
    required this.onCambio,
    this.sugerencia = 'Buscar por amenidad, estado, inmueble…',
  });

  final TextEditingController controlador;
  final ValueChanged<String> onCambio;
  final String sugerencia;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controlador,
        onChanged: onCambio,
        decoration: InputDecoration(
          hintText: sugerencia,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controlador.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controlador.clear();
                    onCambio('');
                  },
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}
