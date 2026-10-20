// Ubicación: frontend/test/pqr_form_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:housetech_frontend/features/pqrs/presentation/pqr_form_screen.dart';
import 'package:housetech_frontend/models/pqr_model.dart';
import 'package:housetech_frontend/services/pqr_service.dart';

/// Simula catálogo, radicación y carga para probar el formulario sin red.
class _FakePqrService extends PqrService {
  _FakePqrService({this.failFirstCatalogRequest = false});

  final bool failFirstCatalogRequest;
  int catalogRequests = 0;
  int? submittedTypeId;
  final uploadedFiles = <String>[];

  @override
  Future<List<TipoPqrModel>> obtenerTiposPqr() async {
    catalogRequests++;
    if (failFirstCatalogRequest && catalogRequests == 1) {
      throw Exception('No fue posible cargar el catálogo.');
    }

    return const [
      TipoPqrModel(
        id: 1,
        codigo: 'PETICION',
        nombre: 'Petición',
        prefijo: 'PET',
      ),
      TipoPqrModel(
        id: 2,
        codigo: 'QUEJA',
        nombre: 'Queja',
        prefijo: 'QUE',
      ),
      TipoPqrModel(
        id: 3,
        codigo: 'RECLAMO',
        nombre: 'Reclamo',
        prefijo: 'REC',
      ),
    ];
  }

  @override
  Future<List<InmuebleOpcionModel>> obtenerMisInmuebles() async => [];

  @override
  Future<Map<String, dynamic>> radicarPqr({
    required int tipoId,
    required String asunto,
    required String descripcion,
    String prioridad = 'MEDIA',
    int? inmuebleId,
  }) async {
    submittedTypeId = tipoId;
    return {
      'success': true,
      'radicado': 'QUE-2026-000001',
      'pqr': Pqr(
        'QUE-2026-000001',
        'Queja',
        asunto,
        '2026-10-19T00:00:00Z',
        PqrEstado.enviado,
        id: 42,
        descripcion: descripcion,
        prioridad: prioridad,
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> subirAdjuntoPqr({
    required int pqrId,
    required PlatformFile archivo,
  }) async {
    uploadedFiles.add(archivo.name);
    return {'success': true};
  }
}

void main() {
  // La validación de campos debe aparecer en el formulario simultáneamente.
  testWidgets('Verifica renderizado y validación del formulario de PQR',
      (WidgetTester tester) async {
    var formularioCancelado = false;
    final service = _FakePqrService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PqrFormScreen(
              service: service,
              onCancelar: () => formularioCancelado = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Registrar PQR mediante formulario'), findsOneWidget);
    expect(find.text('Petición'), findsOneWidget);
    expect(find.text('Queja'), findsOneWidget);
    expect(find.text('Reclamo'), findsOneWidget);
    expect(find.text('Asunto *'), findsOneWidget);
    expect(find.text('Descripción detallada *'), findsOneWidget);
    expect(find.text('Radicar PQR'), findsOneWidget);

    final chipPeticion =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Petición'));
    expect(chipPeticion.selected, isFalse);

    await tester.ensureVisible(find.text('Radicar PQR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radicar PQR'));
    await tester.pumpAndSettle();

    expect(find.text('Selecciona un tipo de solicitud.'), findsOneWidget);
    expect(find.text('Ingresa el asunto de la solicitud.'), findsOneWidget);
    expect(find.text('Ingresa una descripción detallada.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Petición'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Petición'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona un tipo de solicitud.'), findsNothing);
    expect(find.text('Ingresa el asunto de la solicitud.'), findsOneWidget);
    expect(find.text('Ingresa una descripción detallada.'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Cerrar formulario'));
    await tester.tap(find.byTooltip('Cerrar formulario'));
    expect(formularioCancelado, isTrue);
  });

  // Confirma que la clasificación seleccionada llega al servicio y se muestra.
  testWidgets('Envía el tipo seleccionado y muestra el radicado del servidor',
      (WidgetTester tester) async {
    final service = _FakePqrService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PqrFormScreen(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Queja'));
    await tester.enterText(
        find.byType(TextFormField).at(0), 'Ruido en zona común');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'El ruido persiste durante la noche en la zona común.',
    );
    await tester.ensureVisible(find.text('Radicar PQR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radicar PQR'));
    await tester.pumpAndSettle();

    expect(service.submittedTypeId, 2);
    expect(find.text('QUE-2026-000001'), findsOneWidget);
    expect(find.text('¡Radicación Exitosa!'), findsOneWidget);
  });

  // El error del catálogo debe permitir reintentar sin cerrar el formulario.
  testWidgets('Permite reintentar si falla la carga del catálogo',
      (WidgetTester tester) async {
    final service = _FakePqrService(failFirstCatalogRequest: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PqrFormScreen(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No fue posible cargar el catálogo.'), findsOneWidget);
    expect(find.text('Volver a cargar'), findsOneWidget);
    expect(find.text('Petición'), findsNothing);

    await tester.tap(find.text('Volver a cargar'));
    await tester.pumpAndSettle();

    expect(service.catalogRequests, 2);
    expect(find.text('Petición'), findsOneWidget);
    expect(find.text('No fue posible cargar el catálogo.'), findsNothing);
  });
}
