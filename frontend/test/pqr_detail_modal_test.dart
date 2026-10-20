import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/features/pqrs/pqr_detail_modal.dart';
import 'package:housetech_frontend/models/pqr_model.dart';
import 'package:housetech_frontend/services/pqr_service.dart';

class _FakePqrService extends PqrService {
  _FakePqrService({
    this.respuestas = const [],
    this.historial = const [],
  });

  List<PqrRespuestaModel> respuestas;
  List<PqrHistorialModel> historial;
  String? respuestaEnviada;
  bool? marcadaComoSolucion;

  @override
  Future<List<PqrHistorialModel>> obtenerHistorialPqr(int pqrId) async {
    return historial;
  }

  @override
  Future<List<PqrRespuestaModel>> obtenerRespuestasPqr(int pqrId) async {
    return respuestas;
  }

  @override
  Future<PqrRespuestaModel> registrarRespuestaPqr({
    required int pqrId,
    required String respuesta,
    required bool esSolucion,
  }) async {
    respuestaEnviada = respuesta;
    marcadaComoSolucion = esSolucion;
    final creada = PqrRespuestaModel(
      id: 10,
      respuesta: respuesta,
      esSolucion: esSolucion,
      responsableNombre: 'Ana Pérez',
      fechaCreacion: '2026-10-19T12:00:00Z',
    );
    respuestas = [...respuestas, creada];
    return creada;
  }
}

const _pqr = Pqr(
  'PET-2026-000010',
  'Petición',
  'Reparar luminaria',
  '2026-10-19T10:00:00Z',
  PqrEstado.enviado,
  id: 10,
);

Future<void> _abrirDetalle(
  WidgetTester tester, {
  required PqrService service,
  required bool puedeResponder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => verDetalle(
              context,
              _pqr,
              service: service,
              puedeResponder: puedeResponder,
            ),
            child: const Text('Ver detalle'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Ver detalle'));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el historial obtenido del backend', (tester) async {
    final service = _FakePqrService(
      historial: const [
        PqrHistorialModel(
          id: 1,
          estadoAnteriorCodigo: null,
          estadoNuevoCodigo: 'RECIBIDA',
          responsableNombre: null,
          usuarioNombre: 'Juan Pérez',
          comentario: 'PQR radicada',
          fecha: '2026-10-19T12:00:00Z',
        ),
        PqrHistorialModel(
          id: 2,
          estadoAnteriorCodigo: 'RECIBIDA',
          estadoNuevoCodigo: 'EN_REVISION',
          responsableNombre: 'Ana Pérez',
          usuarioNombre: 'Carlos Ruiz',
          comentario: 'Cambio de estado',
          fecha: '2026-10-19T13:00:00Z',
        ),
      ],
    );
    await _abrirDetalle(
      tester,
      service: service,
      puedeResponder: false,
    );

    expect(find.text('Historial de cambios'), findsOneWidget);
    expect(find.text('Solicitud radicada'), findsOneWidget);
    expect(find.text('Estado actualizado'), findsOneWidget);
    expect(find.text('Recibida → En revisión'), findsOneWidget);
    expect(find.text('Por Juan Pérez'), findsOneWidget);
    expect(find.text('Por Carlos Ruiz'), findsOneWidget);
  });

  testWidgets('permite registrar respuesta como solución y mostrarla',
      (tester) async {
    final service = _FakePqrService();
    await _abrirDetalle(
      tester,
      service: service,
      puedeResponder: true,
    );

    expect(find.text('Respuestas y soluciones'), findsOneWidget);
    expect(find.text('Registrar respuesta'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Se reparó la luminaria.',
    );
    await tester.dragUntilVisible(
      find.text('Marcar como solución'),
      find.byType(Scrollable).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Marcar como solución'));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Enviar respuesta'),
      find.byType(Scrollable).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('Enviar respuesta'));
    await tester.pumpAndSettle();

    expect(service.respuestaEnviada, 'Se reparó la luminaria.');
    expect(service.marcadaComoSolucion, isTrue);
    expect(find.text('Solución'), findsOneWidget);
    expect(find.text('Se reparó la luminaria.'), findsOneWidget);
    expect(find.text('Atendida'), findsNothing);
  });

  testWidgets('permite consultar respuestas sin mostrar el formulario',
      (tester) async {
    final service = _FakePqrService(
      respuestas: const [
        PqrRespuestaModel(
          id: 4,
          respuesta: 'El equipo revisará la solicitud.',
          esSolucion: false,
          responsableNombre: 'Ana Pérez',
          fechaCreacion: '2026-10-19T11:00:00Z',
        ),
      ],
    );
    await _abrirDetalle(
      tester,
      service: service,
      puedeResponder: false,
    );

    expect(find.text('El equipo revisará la solicitud.'), findsOneWidget);
    expect(find.text('Registrar respuesta'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
