import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/features/comunicados/comunicados_api.dart';
import 'package:housetech_frontend/features/comunicados/comunicados_menu.dart';
import 'package:housetech_frontend/features/comunicados/models/modelos.dart';
import 'package:housetech_frontend/features/comunicados/pages/bloqueos_admin_page.dart';
import 'package:housetech_frontend/features/comunicados/pages/comunicados_admin_page.dart';
import 'package:housetech_frontend/features/comunicados/pages/comunicados_residente_page.dart';
import 'package:housetech_frontend/features/comunicados/providers/comunicados_providers.dart';
import 'package:housetech_frontend/features/comunicados/services/comunicados_service.dart';

/// Servicio falso: no usa red.
class FakeServicio extends ComunicadosService {
  @override
  Future<PaginaApi<Comunicado>> avisos({int pagina = 1, String? buscar, int? categoria}) async => PaginaApi(
        resultados: const [
          Comunicado(
            id: 1,
            titulo: 'Corte de agua programado',
            contenido: 'El jueves de 8 a. m. a 2 p. m.',
            categoriaNombre: 'Mantenimiento',
            categoriaColor: '#D97706',
          ),
        ],
        total: 1,
        hayMas: false,
      );

  @override
  Future<PaginaApi<NotificacionApp>> notificaciones({int pagina = 1, bool soloNoLeidas = false}) async => PaginaApi(
        resultados: const [
          NotificacionApp(
              id: 7, tipo: 'BLOQUEO', titulo: 'Bloqueo programado: Piscina', mensaje: 'No disponible el sábado.', leida: false),
        ],
        total: 1,
        hayMas: false,
      );

  @override
  Future<int> conteoNoLeidas() async => 1;

  @override
  Future<List<CategoriaComunicado>> categorias() async =>
      const [CategoriaComunicado(id: 1, nombre: 'Mantenimiento', color: '#D97706')];

  @override
  Future<List<DisponibilidadAmenidad>> disponibilidad({DateTime? momento}) async => const [
        DisponibilidadAmenidad(id: 1, nombre: 'Piscina', estado: 'BLOQUEADA', motivo: 'Pintura'),
        DisponibilidadAmenidad(id: 2, nombre: 'Gimnasio', estado: 'DISPONIBLE'),
      ];

  @override
  Future<PaginaApi<Comunicado>> comunicados({int pagina = 1, String? estado, String? buscar}) async => PaginaApi(
        resultados: const [
          Comunicado(
            id: 10,
            titulo: 'Asamblea ordinaria',
            contenido: 'Convocatoria anual en el salón social.',
            categoriaNombre: 'Asambleas',
            categoriaColor: '#16A34A',
            estado: 'PUBLICADO',
            audiencia: 'TODOS',
          ),
        ],
        total: 1,
        hayMas: false,
      );

  @override
  Future<PaginaApi<Mantenimiento>> mantenimientos({int pagina = 1, String? estado, String? buscar}) async => PaginaApi(
        resultados: [
          Mantenimiento(
            fechaInicio: DateTime.utc(2026, 10, 20, 10),
            fechaFin: DateTime.utc(2026, 10, 20, 14),
            id: 20,
            amenidadId: 1,
            amenidadNombre: 'Piscina',
            titulo: 'Mantenimiento de filtros',
            estado: 'PROGRAMADO',
            estadoNombre: 'Programado',
            responsable: 'Aquaservicios',
            bloqueosActivos: 1,
          ),
        ],
        total: 1,
        hayMas: false,
      );

  @override
  Future<PaginaApi<Bloqueo>> bloqueos({int pagina = 1, bool? activo, String? buscar}) async => PaginaApi(
        resultados: [
          Bloqueo(
            fechaInicio: DateTime.utc(2026, 10, 21, 10),
            fechaFin: DateTime.utc(2026, 10, 21, 14),
            id: 30,
            amenidadId: 1,
            amenidadNombre: 'Piscina',
            motivo: 'Evento de administración',
            estado: 'PROGRAMADO',
          ),
        ],
        total: 1,
        hayMas: false,
      );
}

Future<void> pumpPagina(WidgetTester tester, Widget pagina) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [comunicadosServiceProvider.overrideWithValue(FakeServicio())],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: pagina))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('modelos', () {
    test('Comunicado.fromJson interpreta fechas, categoría y destinatarios', () {
      final c = Comunicado.fromJson({
        'id': 3,
        'titulo': 'Aviso',
        'contenido': 'Texto',
        'categoria': 2,
        'categoria_nombre': 'General',
        'categoria_color': '#16A34A',
        'estado': 'PROGRAMADO',
        'audiencia': 'USUARIOS',
        'destinatarios': [4, 5],
        'fecha_programada': '2026-10-20T15:00:00-05:00',
      });
      expect(c.id, 3);
      expect(c.estado, 'PROGRAMADO');
      expect(c.destinatarios, [4, 5]);
      expect(c.fechaProgramada!.toUtc().hour, 20);
      expect(c.colorCategoria, const Color(0xFF16A34A));
    });

    test('Bloqueo.fromJson y permisos de edición según el estado', () {
      Bloqueo con(String estado) => Bloqueo.fromJson({
            'id': 1,
            'amenidad': 2,
            'amenidad_nombre': 'Piscina',
            'fecha_inicio': '2026-10-20T10:00:00Z',
            'fecha_fin': '2026-10-20T12:00:00Z',
            'motivo': 'Pintura',
            'estado': estado,
          });
      expect(con('PROGRAMADO').editable, isTrue);
      expect(con('ACTIVO').editable, isTrue);
      expect(con('CANCELADO').editable, isFalse);
      expect(con('FINALIZADO').editable, isFalse);
    });

    test('PaginaApi acepta respuestas paginadas y listas simples', () {
      final paginada = PaginaApi.desde({
        'count': 25,
        'next': 'http://x/?page=2',
        'results': [
          {'id': 1, 'nombre': 'A'}
        ],
      }, CategoriaComunicado.fromJson);
      expect(paginada.total, 25);
      expect(paginada.hayMas, isTrue);
      final simple = PaginaApi.desde([
        {'id': 1, 'nombre': 'A'},
        {'id': 2, 'nombre': 'B'},
      ], CategoriaComunicado.fromJson);
      expect(simple.resultados.length, 2);
      expect(simple.hayMas, isFalse);
    });

    test('colorDesdeHex tolera valores inválidos', () {
      expect(colorDesdeHex('#FF0000', Colors.black), const Color(0xFFFF0000));
      expect(colorDesdeHex('rojo', Colors.black), Colors.black);
      expect(colorDesdeHex(null, Colors.black), Colors.black);
    });
  });

  test('ApiException detecta el conflicto de reservas', () {
    final e = ApiException('Hay reservas', status: 409, datos: {
      'codigo': 'reservas_en_conflicto',
      'reservas': [
        {'id': 1, 'usuario': 'Rosa'}
      ],
    });
    expect(e.esConflictoReservas, isTrue);
    expect(e.reservas.single['usuario'], 'Rosa');
    expect(ApiException('x', status: 409, datos: {'codigo': 'bloqueo_cruzado'}).esConflictoReservas, isFalse);
  });

  test('el menú del módulo cubre los tres permisos', () {
    expect(ComunicadosMenu.paginaPara('comunicados.ver'), isNotNull);
    expect(ComunicadosMenu.paginaPara('comunicados.gestionar'), isNotNull);
    expect(ComunicadosMenu.paginaPara('bloqueos.gestionar'), isNotNull);
    expect(ComunicadosMenu.paginaPara('pqr.radicar'), isNull);
  });

  group('pantalla del residente', () {
    testWidgets('lista los avisos y muestra el contador de notificaciones', (tester) async {
      await pumpPagina(tester, const ComunicadosResidentePage());
      expect(find.text('Corte de agua programado'), findsOneWidget);
      expect(find.text('Notificaciones (1)'), findsOneWidget);
    });

    testWidgets('abre el detalle de un aviso', (tester) async {
      await pumpPagina(tester, const ComunicadosResidentePage());
      await tester.tap(find.text('Corte de agua programado'));
      await tester.pumpAndSettle();
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.textContaining('8 a. m.'), findsWidgets);
    });

    testWidgets('muestra las notificaciones', (tester) async {
      await pumpPagina(tester, const ComunicadosResidentePage());
      await tester.tap(find.text('Notificaciones (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bloqueo programado: Piscina'), findsOneWidget);
    });

    testWidgets('muestra el estado de cada amenidad', (tester) async {
      await pumpPagina(tester, const ComunicadosResidentePage());
      await tester.tap(find.text('Disponibilidad'));
      await tester.pumpAndSettle();
      expect(find.text('Piscina'), findsOneWidget);
      expect(find.text('Bloqueada'), findsOneWidget);
      expect(find.text('Motivo: Pintura'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
    });
  });

  group('formulario de bloqueo', () {
    testWidgets('exige amenidad, fechas y motivo', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BloqueoFormDialog(amenidades: const [DisponibilidadAmenidad(id: 1, nombre: 'Piscina', estado: 'DISPONIBLE')]),
        ),
      ));
      await tester.tap(find.text('Programar bloqueo'));
      await tester.pumpAndSettle();
      expect(find.text('El motivo es obligatorio'), findsOneWidget);
      expect(find.text('Selecciona la amenidad a bloquear.'), findsOneWidget);
    });
  });

  group('pantallas administrativas del Módulo 2', () {
    testWidgets('ComunicadosAdminPage lista comunicados y permite cambiar a Categorías', (tester) async {
      await pumpPagina(tester, const ComunicadosAdminPage());
      expect(find.text('Administrar comunicados'), findsOneWidget);
      expect(find.text('Asamblea ordinaria'), findsOneWidget);
      await tester.tap(find.text('Categorías'));
      await tester.pumpAndSettle();
      expect(find.text('Mantenimiento'), findsOneWidget);
    });

    testWidgets('BloqueosAdminPage muestra bloqueos y permite cambiar a Mantenimientos', (tester) async {
      await pumpPagina(tester, const BloqueosAdminPage());
      expect(find.text('Bloqueos y mantenimientos'), findsOneWidget);
      expect(find.text('Motivo: Evento de administración'), findsOneWidget);
      await tester.tap(find.text('Mantenimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Mantenimiento de filtros'), findsOneWidget);
      expect(find.text('Responsable: Aquaservicios'), findsOneWidget);
    });
  });
}
