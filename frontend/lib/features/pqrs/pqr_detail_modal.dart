import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../services/pqr_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trazabilidad.dart';

/// Abre el detalle desplazable de una PQR, sus respuestas y soluciones.
void verDetalle(
  BuildContext context,
  Pqr p, {
  PqrService? service,
  bool puedeResponder = false,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _PqrDetailSheet(
        pqr: p,
        service: service ?? PqrService(),
        puedeResponder: puedeResponder,
      ),
    );

class _PqrDetailSheet extends StatefulWidget {
  final Pqr pqr;
  final PqrService service;
  final bool puedeResponder;

  const _PqrDetailSheet({
    required this.pqr,
    required this.service,
    required this.puedeResponder,
  });

  @override
  State<_PqrDetailSheet> createState() => _PqrDetailSheetState();
}

class _PqrDetailSheetState extends State<_PqrDetailSheet> {
  List<PqrRespuestaModel> _respuestas = [];
  List<PqrHistorialModel> _historial = [];
  final _respuestaController = TextEditingController();
  bool _cargandoRespuestas = true;
  bool _cargandoHistorial = true;
  bool _esSolucion = false;
  bool _guardandoRespuesta = false;
  String? _errorCargaRespuestas;
  String? _errorCargaHistorial;
  String? _errorRespuesta;

  @override
  void initState() {
    super.initState();
    _cargarRespuestas();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _respuestaController.dispose();
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

  Future<void> _registrarRespuesta() async {
    final pqrId = widget.pqr.id;
    final texto = _respuestaController.text.trim();
    if (pqrId == null || texto.isEmpty || _guardandoRespuesta) return;

    setState(() {
      _guardandoRespuesta = true;
      _errorRespuesta = null;
    });

    try {
      final nuevaRespuesta = await widget.service.registrarRespuestaPqr(
        pqrId: pqrId,
        respuesta: texto,
        esSolucion: _esSolucion,
      );
      if (!mounted) return;

      setState(() {
        _respuestaController.clear();
        _esSolucion = false;
        _guardandoRespuesta = false;
        _respuestas = [..._respuestas, nuevaRespuesta];
      });
      await _cargarHistorial();
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
        _guardandoRespuesta = false;
        _errorRespuesta = 'No fue posible registrar la respuesta: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pqr;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      minChildSize: .5,
      maxChildSize: .95,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.radicado,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: primaryBlue,
                    ),
                  ),
                ),
                EstadoChip(p.estado),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${p.tipo} · ${p.fecha}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              p.asunto,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            if (p.descripcion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                p.descripcion,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
            const SizedBox(height: 24),
            const Titulo('Historial de cambios'),
            _contenidoHistorial(p),
            const SizedBox(height: 8),
            const Titulo('Respuestas y soluciones'),
            _contenidoRespuestas(),
            if (widget.puedeResponder) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Registrar respuesta',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _respuestaController,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                enabled: !_guardandoRespuesta,
                decoration: const InputDecoration(
                  labelText: 'Respuesta para el residente',
                  hintText: 'Describe la respuesta o solución proporcionada.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {
                  if (_errorRespuesta != null) _errorRespuesta = null;
                }),
              ),
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _esSolucion,
                  onChanged: _guardandoRespuesta
                      ? null
                      : (value) => setState(() => _esSolucion = value ?? false),
                  title: const Text('Marcar como solución'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              if (_errorRespuesta != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorRespuesta!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _respuestaController.text.trim().isEmpty ||
                          _guardandoRespuesta
                      ? null
                      : _registrarRespuesta,
                  icon: _guardandoRespuesta
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Enviar respuesta'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.black45),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registro inalterable: cada cambio guarda fecha, hora y usuario responsable.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ],
        ),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryBlue.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                left: BorderSide(color: primaryBlue, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      respuesta.esSolucion ? 'Solución' : 'Respuesta',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: primaryBlue,
                      ),
                    ),
                    if (respuesta.responsableNombre != null &&
                        respuesta.responsableNombre!.isNotEmpty)
                      Text(
                        '· ${respuesta.responsableNombre}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    Text(
                      respuesta.fechaCreacion,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  respuesta.respuesta,
                  style: const TextStyle(fontSize: 13, color: textDark),
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

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: primaryBlue.withValues(alpha: .1),
                  child: Icon(icono, size: 15, color: primaryBlue),
                ),
                if (!ultimo)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.black12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: e.color,
                    child: Icon(e.icon, size: 14, color: Colors.white),
                  ),
                  if (!ultimo)
                    Expanded(
                      child: Container(width: 2, color: Colors.black12),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
