import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/modulo1_service.dart';

class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  final Modulo1Service _service = Modulo1Service();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _registros = [];
  bool _loading = true;
  String? _error;
  String? _filtroOperacion;
  String? _filtroTabla;
  DateTime? _filtroFecha;

  static const Map<String, String> _entidadesNombres = {
    'usuarios': 'Usuario',
    'usuarios_roles': 'UsuarioRol',
    'roles': 'Rol',
    'roles_permisos': 'RolPermiso',
    'inmuebles': 'Inmueble',
    'inmuebles_usuarios': 'VínculoInmueble',
    'copropiedades': 'Conjunto',
    'reservas': 'Reserva',
    'amenidades': 'Amenidad',
    'pqr': 'PQR',
    'comunicados': 'Comunicado',
    'mantenimientos': 'Mantenimiento',
    'bloqueos_amenidad': 'Bloqueo',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.listarAuditoria(
        search: _searchCtrl.text.trim(),
        operacion: _filtroOperacion,
        tabla: _filtroTabla,
      );
      if (mounted) {
        setState(() {
          _registros = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _registrosFiltrados {
    if (_filtroFecha == null) return _registros;
    final prefijo =
        '${_filtroFecha!.year.toString().padLeft(4, '0')}-${_filtroFecha!.month.toString().padLeft(2, '0')}-${_filtroFecha!.day.toString().padLeft(2, '0')}';
    return _registros.where((r) {
      final fechaStr = (r['fecha'] ?? '').toString();
      return fechaStr.startsWith(prefijo);
    }).toList();
  }

  String _formatearFechaUtc(dynamic raw) {
    if (raw == null) return '-';
    final str = raw.toString();
    final dt = DateTime.tryParse(str)?.toUtc();
    if (dt == null) return str;
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d\n$hh:$mm:$ss';
  }

  String _etiquetaAccion(String op) {
    switch (op.toUpperCase()) {
      case 'INSERT':
        return 'CREATE';
      case 'UPDATE':
        return 'UPDATE';
      case 'DELETE':
        return 'DELETE';
      default:
        return op.toUpperCase();
    }
  }

  Color _colorAccion(String op) {
    switch (op.toUpperCase()) {
      case 'INSERT':
      case 'CREATE':
        return const Color(0xFF16A34A);
      case 'UPDATE':
        return const Color(0xFF2563EB);
      case 'DELETE':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _nombreEntidad(String tabla) {
    return _entidadesNombres[tabla.toLowerCase()] ?? tabla;
  }

  String _resumenCambio(Map<String, dynamic> r) {
    final op = (r['operacion'] ?? '').toString().toUpperCase();
    final antes = r['datos_anteriores'];
    final nuevos = r['datos_nuevos'];

    if (op == 'INSERT' && nuevos is Map) {
      final claves = nuevos.keys
          .where((k) => k != 'id' && k != 'password' && k != 'created_at')
          .take(3)
          .map((k) => '$k: ${nuevos[k]}')
          .join(', ');
      return claves.isNotEmpty ? 'Creado ($claves)' : 'Registro creado';
    }
    if (op == 'UPDATE' && antes is Map && nuevos is Map) {
      final cambiados = <String>[];
      for (final k in nuevos.keys) {
        if (k == 'updated_at' || k == 'password') continue;
        if (antes[k]?.toString() != nuevos[k]?.toString()) {
          cambiados.add('$k: ${antes[k] ?? "null"} → ${nuevos[k] ?? "null"}');
        }
      }
      if (cambiados.isNotEmpty) {
        return cambiados.take(2).join(' | ');
      }
      return 'Actualización de registro';
    }
    if (op == 'DELETE' && antes is Map) {
      final claves = antes.keys
          .where((k) => k != 'password')
          .take(2)
          .map((k) => '$k: ${antes[k]}')
          .join(', ');
      return claves.isNotEmpty ? 'Eliminado ($claves)' : 'Registro eliminado';
    }
    return 'Evento registrado';
  }

  void _mostrarDetalleJson(Map<String, dynamic> r) {
    const encoder = JsonEncoder.withIndent('  ');
    final tabla = (r['tabla'] ?? '').toString();
    final entidad = _nombreEntidad(tabla);
    final antes = r['datos_anteriores'] != null
        ? encoder.convert(r['datos_anteriores'])
        : 'Sin datos anteriores';
    final nuevos = r['datos_nuevos'] != null
        ? encoder.convert(r['datos_nuevos'])
        : 'Sin datos nuevos';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Evento #${r['id']} • $entidad (#${r['registro_id'] ?? '-'})'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _PillBadge(
                      text: _etiquetaAccion((r['operacion'] ?? '').toString()),
                      color: _colorAccion((r['operacion'] ?? '').toString()),
                    ),
                    _PillBadge(
                      text: 'Actor: ${r['usuario_username'] ?? 'sistema'}',
                      color: const Color(0xFF334155),
                    ),
                    _PillBadge(
                      text: 'Tabla: $tabla',
                      color: const Color(0xFF475569),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Estado Anterior (JSON):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SelectableText(
                    antes,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Estado Nuevo (JSON):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: SelectableText(
                    nuevos,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filtroFecha ?? hoy,
      firstDate: DateTime(2024),
      lastDate: DateTime(hoy.year + 1),
    );
    if (picked != null) {
      setState(() => _filtroFecha = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _registrosFiltrados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Encabezado
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bitácora de Auditoría',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Registro cronológico de eventos por fecha, usuario/actor, acción, entidad e ID afectado.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Barra de filtros (Fecha, Usuario, Acción y Tipo de Recurso)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _cargar(),
                  decoration: InputDecoration(
                    hintText: 'Filtrar por usuario o ID...',
                    prefixIcon: const Icon(Icons.person_search_rounded, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              // Filtro Acción
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButton<String?>(
                    value: _filtroOperacion,
                    hint: const Text('Acción: Todas'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Acción: Todas')),
                      DropdownMenuItem(value: 'INSERT', child: Text('CREATE (Alta)')),
                      DropdownMenuItem(value: 'UPDATE', child: Text('UPDATE (Edición)')),
                      DropdownMenuItem(value: 'DELETE', child: Text('DELETE (Baja)')),
                    ],
                    onChanged: (v) {
                      setState(() => _filtroOperacion = v);
                      _cargar();
                    },
                  ),
                ),
              ),
              // Filtro Módulo / Entidad
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: DropdownButton<String?>(
                    value: _filtroTabla,
                    hint: const Text('Módulo / Entidad: Todos'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Entidad: Todas'),
                      ),
                      ..._entidadesNombres.entries.map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.value} (${e.key})'),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _filtroTabla = v);
                      _cargar();
                    },
                  ),
                ),
              ),
              // Filtro Fecha
              OutlinedButton.icon(
                onPressed: _seleccionarFecha,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  _filtroFecha == null
                      ? 'Fecha: Todas'
                      : 'Fecha: ${_filtroFecha!.year}-${_filtroFecha!.month.toString().padLeft(2, '0')}-${_filtroFecha!.day.toString().padLeft(2, '0')}',
                ),
              ),
              if (_filtroFecha != null ||
                  _filtroOperacion != null ||
                  _filtroTabla != null ||
                  _searchCtrl.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {
                      _filtroOperacion = null;
                      _filtroTabla = null;
                      _filtroFecha = null;
                    });
                    _cargar();
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Limpiar filtros'),
                ),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('Buscar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Tabla de Bitácora estilo Back-Office
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
          )
        else if (filas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(Icons.history_toggle_off_rounded,
                    size: 48, color: Color(0xFF94A3B8)),
                SizedBox(height: 12),
                Text(
                  'No se encontraron eventos en la bitácora con estos filtros.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 1010),
                  child: DataTable(
                    headingRowHeight: 52,
                    dataRowMinHeight: 62,
                    dataRowMaxHeight: 72,
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFF1E293B),
                    ),
                    dividerThickness: 0.6,
                    columns: const [
                      DataColumn(
                        label: Text(
                          'Fecha y Hora (UTC)',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Usuario / Actor',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Acción',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Módulo / Entidad',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'ID Afectado',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Resumen del Cambio / Detalle',
                          style: TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    rows: filas.map((r) {
                      final op = (r['operacion'] ?? '').toString();
                      final tabla = (r['tabla'] ?? '').toString();
                      final actor =
                          (r['usuario_username'] ?? 'sistema').toString();
                      final regId = r['registro_id']?.toString() ?? '-';

                      return DataRow(
                        cells: [
                          DataCell(
                            _DarkCodeBadge(text: _formatearFechaUtc(r['fecha'])),
                          ),
                          DataCell(
                            _DarkCodeBadge(text: actor),
                          ),
                          DataCell(
                            _ActionBadge(
                              text: _etiquetaAccion(op),
                              color: _colorAccion(op),
                            ),
                          ),
                          DataCell(
                            _DarkCodeBadge(text: _nombreEntidad(tabla)),
                          ),
                          DataCell(
                            _DarkCodeBadge(text: regId == '-' ? '-' : '#$regId'),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 240,
                                  child: Text(
                                    _resumenCambio(r),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Ver JSON completo',
                                  onPressed: () => _mostrarDetalleJson(r),
                                  icon: const Icon(
                                    Icons.data_object_rounded,
                                    color: Color(0xFF38BDF8),
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DarkCodeBadge extends StatelessWidget {
  const _DarkCodeBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
