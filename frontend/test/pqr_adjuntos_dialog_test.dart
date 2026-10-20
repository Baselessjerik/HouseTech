import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/features/pqrs/presentation/pqr_adjuntos_dialog.dart';
import 'package:housetech_frontend/models/pqr_model.dart';
import 'package:housetech_frontend/services/pqr_service.dart';

/// Sustituye la API por datos locales para probar las acciones del diálogo.
class _FakePqrService extends PqrService {
  int deleteRequests = 0;

  bool adjuntoExiste = true;

  @override
  Future<List<PqrAdjuntoModel>> obtenerAdjuntosPqr(int pqrId) async {
    if (!adjuntoExiste) return [];
    return const [
      PqrAdjuntoModel(
        id: 7,
        nombreArchivo: 'evidencia.pdf',
        tipoMime: 'application/pdf',
        tamanoBytes: 128,
        fechaCreacion: '2026-10-19T12:00:00Z',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> eliminarAdjuntoPqr({
    required int pqrId,
    required int adjuntoId,
  }) async {
    deleteRequests++;
    adjuntoExiste = false;
    return {'success': true};
  }
}

void main() {
  // Verifica que la eliminación requiere confirmación y refresca la lista.
  testWidgets('Muestra acciones CRUD y elimina el adjunto confirmado',
      (WidgetTester tester) async {
    final service = _FakePqrService();
    const pqr = Pqr(
      'PET-2026-000001',
      'Petición',
      'Solicitud de prueba',
      '2026-10-19T12:00:00Z',
      PqrEstado.enviado,
      id: 42,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PqrAdjuntosDialog(
                  pqr: pqr,
                  service: service,
                ),
              ),
              child: const Text('Abrir adjuntos'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir adjuntos'));
    await tester.pumpAndSettle();

    expect(find.text('evidencia.pdf'), findsOneWidget);
    expect(find.byTooltip('Descargar evidencia.pdf'), findsOneWidget);
    expect(find.byTooltip('Reemplazar evidencia.pdf'), findsOneWidget);
    expect(find.byTooltip('Eliminar evidencia.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar evidencia.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('¿Quieres eliminar "evidencia.pdf"?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(service.deleteRequests, 1);
    expect(find.text('evidencia.pdf'), findsNothing);
  });
}
