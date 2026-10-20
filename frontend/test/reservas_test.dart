import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/features/comunicados/comunicados_api.dart';
import 'package:housetech_frontend/features/reservas/models/reservas_models.dart';
import 'package:housetech_frontend/features/reservas/pages/amenidades_admin_page.dart';
import 'package:housetech_frontend/features/reservas/pages/reservas_residente_page.dart';
import 'package:housetech_frontend/features/reservas/services/reservas_service.dart';

class _FakeApiClient extends ApiClient {
  @override
  Future<dynamic> get(String url, {Map<String, String>? query}) async {
    final p = Uri.parse(url).path;
    Map<String, dynamic> body(List<dynamic> d) => {'results': d, 'count': d.length};

    if (p.endsWith('/amenidades/')) {
      return [
        {
          'id': 1,
          'nombre': 'Salón social',
          'descripcion': 'Salón principal de eventos',
          'capacidad': 40,
          'activa': true,
          'horarios': [
            {'dia_semana': 1, 'hora_apertura': '08:00', 'hora_cierre': '22:00', 'activo': true},
          ],
          'reglas': {
            'duracion_min_minutos': 60,
            'duracion_max_minutos': 240,
            'anticipacion_min_horas': 1,
            'anticipacion_max_dias': 30,
            'max_reservas_mes_inmueble': 2,
            'horas_limite_cancelacion': 48,
            'requiere_confirmacion': true,
            'horas_limite_confirmacion': 24,
            'horas_recordatorio': 24,
          },
        }
      ];
    }
    if (p.contains('/disponibilidad/')) {
      return {
        'amenidad_id': 1,
        'amenidad': 'Salón social',
        'fecha': '2026-10-25',
        'activa': true,
        'abierta': true,
        'capacidad': 40,
        'duracion_min_minutos': 60,
        'duracion_max_minutos': 240,
        'horarios': [
          {'apertura': '08:00', 'cierre': '22:00'},
        ],
        'ocupados': [],
        'libres': [
          {'inicio': '2026-10-25T13:00:00Z', 'fin': '2026-10-25T23:00:00Z'},
        ],
      };
    }
    if (p.endsWith('/reservas/')) {
      return body([
        {
          'id': 10,
          'amenidad': 1,
          'amenidad_nombre': 'Salón social',
          'usuario': 2,
          'residente': 'Rosa Residente',
          'inmueble': 1,
          'inmueble_codigo': 'T1-101',
          'fecha_inicio': '2026-10-26T15:00:00Z',
          'fecha_fin': '2026-10-26T17:00:00Z',
          'num_personas': 12,
          'estado': 'SOLICITADA',
          'estado_nombre': 'Solicitada',
          'observaciones': 'Reunión familiar',
          'puede_cancelar': true,
        }
      ]);
    }
    if (p.endsWith('/agenda/')) {
      return {
        'desde': '2026-10-20',
        'hasta': '2026-11-20',
        'eventos': [
          {
            'tipo': 'RESERVA',
            'id': 10,
            'amenidad_id': 1,
            'amenidad': 'Salón social',
            'inicio': '2026-10-26T15:00:00Z',
            'fin': '2026-10-26T17:00:00Z',
            'titulo': 'Salón social · Rosa Residente',
            'estado': 'SOLICITADA',
            'estado_nombre': 'Solicitada',
            'mia': true,
          }
        ],
      };
    }
    if (p.endsWith('/reportes/ocupacion/')) {
      return {
        'resumen': {
          'horas_disponibles': 98.0,
          'horas_reservadas': 12.0,
          'ocupacion_pct': 12.24,
          'reservas': 4,
          'tasa_cancelacion_pct': 20.0,
        },
        'amenidades': [
          {
            'amenidad_id': 1,
            'amenidad': 'Salón social',
            'capacidad': 40,
            'horas_disponibles': 98.0,
            'horas_reservadas': 12.0,
            'ocupacion_pct': 12.24,
            'horas_bloqueadas': 0.0,
            'reservas': 4,
            'tasa_cancelacion_pct': 20.0,
            'hora_pico': '15:00',
          }
        ],
      };
    }
    return <String, dynamic>{};
  }
}

ReservasService _mockServicio() => ReservasService(cliente: _FakeApiClient());

void main() {
  test('AmenidadModel y ReservaModel parsean JSON del backend', () {
    final a = AmenidadModel.fromJson({
      'id': 2,
      'nombre': 'Piscina',
      'capacidad': 25,
      'activa': true,
      'reglas': {'requiere_confirmacion': false, 'horas_limite_cancelacion': 6},
    });
    expect(a.nombre, 'Piscina');
    expect(a.capacidad, 25);
    expect(a.reglas.requiereConfirmacion, isFalse);
    expect(a.reglas.horasLimiteCancelacion, 6);

    final r = ReservaModel.fromJson({
      'id': 5,
      'amenidad': 2,
      'amenidad_nombre': 'Piscina',
      'usuario': 3,
      'residente': 'Rosa Residente',
      'fecha_inicio': '2026-10-25T14:00:00Z',
      'fecha_fin': '2026-10-25T16:00:00Z',
      'num_personas': 4,
      'estado': 'CONFIRMADA',
      'estado_nombre': 'Confirmada',
      'puede_cancelar': true,
    });
    expect(r.amenidadNombre, 'Piscina');
    expect(r.estado, 'CONFIRMADA');
    expect(r.puedeCancelar, isTrue);
  });

  testWidgets('ReservasResidentePage muestra las reservas del residente y su agenda',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReservasResidentePage(servicio: _mockServicio())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Salón social'), findsOneWidget);
    expect(find.text('Solicitada'), findsOneWidget);
    expect(find.text('Inmueble: T1-101'), findsOneWidget);

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Salón social · Rosa Residente'), findsOneWidget);
  });

  testWidgets('AmenidadesAdminPage muestra zonas comunes, reservas y ocupación',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AmenidadesAdminPage(servicio: _mockServicio())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Salón social'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);

    await tester.tap(find.text('Solicitudes y reservas'));
    await tester.pumpAndSettle();
    expect(find.text('Salón social · Rosa Residente'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);

    await tester.tap(find.text('Ocupación'));
    await tester.pumpAndSettle();
    expect(find.text('12.24%'), findsNWidgets(2));
  });
}

