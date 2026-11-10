import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../reservas/models/reservas_models.dart';
import '../../reservas/services/reservas_service.dart';
import '../services/modulo1_service.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  final ReservasService _reservasSvc = ReservasService();
  final Modulo1Service _modulo1Svc = Modulo1Service();

  ReporteOcupacionModel? _ocupacion;
  List<AmenidadModel> _amenidades = const [];
  int _totalUsuarios = 0;
  int _totalInmuebles = 0;
  bool _cargando = true;
  String? _error;

  static const List<Color> _paletaColores = [
    Color(0xFF0284C7),
    Color(0xFF16A34A),
    Color(0xFF7C3AED),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF0D9488),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _reservasSvc.reporteOcupacion(),
        _reservasSvc.listarAmenidades(),
        _modulo1Svc.listarUsuarios(),
        _modulo1Svc.listarInmuebles(mios: false),
      ]);
      if (!mounted) return;
      setState(() {
        _ocupacion = results[0] as ReporteOcupacionModel;
        _amenidades = results[1] as List<AmenidadModel>;
        _totalUsuarios = (results[2] as List).length;
        _totalInmuebles = (results[3] as List).length;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final rep = _ocupacion!;
    final mapaReservasPorAmenidad = {
      for (final a in rep.amenidades) a.amenidadId: a.reservas,
    };
    final lugaresSinReservas = _amenidades
        .where((a) => (mapaReservasPorAmenidad[a.id] ?? 0) == 0)
        .toList();
    final lugaresConReservasCount =
        math.max(0, _amenidades.length - lugaresSinReservas.length);

    final maxReservasAmenidad = rep.amenidades.fold<int>(
      1,
      (prev, el) => el.reservas > prev ? el.reservas : prev,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Encabezado
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reportes y Estadísticas Operativas',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Métricas visuales de ocupación, gráficas por zona común, lugares sin uso y comunidad.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
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
        const SizedBox(height: 20),

        // 1. Tarjetas de KPIs
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _KpiCard(
              icon: Icons.event_available_rounded,
              title: 'Reservas efectivas',
              value: '${rep.reservas}',
              subtitle:
                  '${rep.horasReservadas} h de ${rep.horasDisponibles} h disp.',
              color: AppColors.oceanBlue,
            ),
            _KpiCard(
              icon: Icons.pie_chart_rounded,
              title: 'Ocupación global',
              value: rep.ocupacionPct != null ? '${rep.ocupacionPct}%' : '0%',
              subtitle: 'Cancelación: ${rep.tasaCancelacionPct}%',
              color: const Color(0xFF16A34A),
            ),
            _KpiCard(
              icon: Icons.warning_amber_rounded,
              title: 'Lugares sin reservas',
              value: '${lugaresSinReservas.length}',
              subtitle: 'De ${_amenidades.length} zonas comunes',
              color: const Color(0xFFD97706),
            ),
            _KpiCard(
              icon: Icons.people_alt_rounded,
              title: 'Comunidad registrada',
              value: '$_totalUsuarios usuarios',
              subtitle: '$_totalInmuebles inmuebles registrados',
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2. Grilla de 2 columnas con Gráficos Visuales
        LayoutBuilder(
          builder: (context, constraints) {
            final dosColumnas = constraints.maxWidth >= 760;
            final anchoCol = dosColumnas
                ? (constraints.maxWidth - 20) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                // Gráfico 1: Barras verticales de Reservas y Horas por Zona Común
                SizedBox(
                  width: anchoCol,
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bar_chart_rounded,
                                  color: AppColors.oceanBlue, size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Gráfico de Reservas por Zona Común',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Comparativa de reservas efectivas y horas utilizadas por cada amenidad.',
                            style:
                                TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 210,
                            child: rep.amenidades.isEmpty
                                ? const Center(
                                    child: Text('Sin datos de zonas comunes'))
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      for (var i = 0;
                                          i < rep.amenidades.length;
                                          i++)
                                        Expanded(
                                          child: _BarraVerticalAmenidad(
                                            nombre: rep.amenidades[i].amenidad,
                                            reservas:
                                                rep.amenidades[i].reservas,
                                            horas: rep
                                                .amenidades[i].horasReservadas,
                                            proporcion: rep
                                                    .amenidades[i].reservas /
                                                maxReservasAmenidad,
                                            color: _paletaColores[
                                                i % _paletaColores.length],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Gráfico 2: Donut Chart de Uso de Zonas Comunes y Tasa de Cancelación
                SizedBox(
                  width: anchoCol,
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.donut_large_rounded,
                                  color: Color(0xFF16A34A), size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Distribución de Uso y Efectividad',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Proporción de zonas comunes activas con demanda vs. zonas sin reservas.',
                            style:
                                TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 210,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: SizedBox(
                                      width: 155,
                                      height: 155,
                                      child: CustomPaint(
                                        painter: _DonutChartPainter(
                                          segmentos: [
                                            _SegmentoDonut(
                                              valor: lugaresConReservasCount
                                                  .toDouble(),
                                              color: const Color(0xFF16A34A),
                                            ),
                                            _SegmentoDonut(
                                              valor: lugaresSinReservas.length
                                                  .toDouble(),
                                              color: const Color(0xFFF59E0B),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${_amenidades.isEmpty ? 0 : ((lugaresConReservasCount / _amenidades.length) * 100).round()}%',
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.textDark,
                                                ),
                                              ),
                                              const Text(
                                                'Zonas con uso',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _LeyendaDonut(
                                        color: const Color(0xFF16A34A),
                                        titulo: 'Zonas reservadas',
                                        valor:
                                            '$lugaresConReservasCount de ${_amenidades.length} zonas',
                                      ),
                                      const SizedBox(height: 14),
                                      _LeyendaDonut(
                                        color: const Color(0xFFF59E0B),
                                        titulo: 'Zonas SIN reservas',
                                        valor:
                                            '${lugaresSinReservas.length} de ${_amenidades.length} zonas',
                                      ),
                                      const SizedBox(height: 18),
                                      const Divider(
                                          height: 1, color: Color(0xFFE2E8F0)),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Tasa de cancelación: ${rep.tasaCancelacionPct}%',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: (rep.tasaCancelacionPct
                                                  .clamp(0, 100)) /
                                              100.0,
                                          minHeight: 8,
                                          backgroundColor:
                                              const Color(0xFFE2E8F0),
                                          color: const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // 3. Reporte de lugares que NO se reservan
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.unpublished_outlined,
                        color: Color(0xFFD97706)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Lugares / Zonas Comunes que NO se reservan (0 reservas en el periodo)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${lugaresSinReservas.length} sin reservas',
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (lugaresSinReservas.isEmpty)
                  const Text(
                    'Todas las zonas comunes registran al menos una reserva en el periodo.',
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final z in lugaresSinReservas)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off_outlined,
                                  size: 18, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Text(
                                '${z.nombre} (Cap. ${z.capacidad})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 4. Desglose de Ocupación con barras horizontales
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Desglose Detallado de Ocupación por Zona Común',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < rep.amenidades.length; i++) ...[
                  _FilaOcupacionAmenidad(
                    item: rep.amenidades[i],
                    color: _paletaColores[i % _paletaColores.length],
                  ),
                  if (i < rep.amenidades.length - 1)
                    const Divider(height: 24, color: Color(0xFFF1F5F9)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BarraVerticalAmenidad extends StatelessWidget {
  const _BarraVerticalAmenidad({
    required this.nombre,
    required this.reservas,
    required this.horas,
    required this.proporcion,
    required this.color,
  });

  final String nombre;
  final int reservas;
  final num horas;
  final double proporcion;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final alturaMax = 125.0;
    final alturaBarra = reservas == 0
        ? 8.0
        : (proporcion.clamp(0.12, 1.0) * alturaMax);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$reservas res.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: reservas > 0 ? color : const Color(0xFF94A3B8),
            ),
          ),
          Text(
            '${horas}h',
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Container(
            width: 38,
            height: alturaBarra,
            decoration: BoxDecoration(
              color: reservas > 0 ? color : const Color(0xFFE2E8F0),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
                bottom: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentoDonut {
  const _SegmentoDonut({required this.valor, required this.color});
  final double valor;
  final Color color;
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.segmentos});
  final List<_SegmentoDonut> segmentos;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segmentos.fold<double>(0, (s, e) => s + e.valor);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    const strokeWidth = 22.0;

    final basePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, basePaint);

    if (total <= 0) return;

    var startAngle = -math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (final seg in segmentos) {
      if (seg.valor <= 0) continue;
      final sweepAngle = (seg.valor / total) * 2 * math.pi;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => true;
}

class _LeyendaDonut extends StatelessWidget {
  const _LeyendaDonut({
    required this.color,
    required this.titulo,
    required this.valor,
  });

  final Color color;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaOcupacionAmenidad extends StatelessWidget {
  const _FilaOcupacionAmenidad({
    required this.item,
    required this.color,
  });

  final OcupacionAmenidadModel item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (item.ocupacionPct ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withAlpha(25),
              child: Icon(Icons.pool_rounded, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.amenidad,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reservas: ${item.reservas} · Horas: ${item.horasReservadas} h / ${item.horasDisponibles} h · '
                    'Cancelación: ${item.tasaCancelacionPct}%'
                    '${item.horaPico != null ? ' · Hora pico: ${item.horaPico}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${item.ocupacionPct ?? 0}% uso',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: item.reservas > 0 ? (pct / 100.0).clamp(0.04, 1.0) : 0.0,
            minHeight: 7,
            backgroundColor: const Color(0xFFF1F5F9),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withAlpha(25),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.black45, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
