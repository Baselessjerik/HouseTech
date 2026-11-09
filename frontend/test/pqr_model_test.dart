import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/models/pqr_model.dart';

void main() {
  test('mapea respuestas y soluciones enviadas por el backend', () {
    final respuesta = PqrRespuestaModel.fromJson({
      'id': 8,
      'respuesta': 'Se reparó la luminaria.',
      'es_solucion': true,
      'responsable_nombre': 'Ana Pérez',
      'created_at': '2026-10-19T12:00:00Z',
    });

    expect(respuesta.id, 8);
    expect(respuesta.respuesta, 'Se reparó la luminaria.');
    expect(respuesta.esSolucion, isTrue);
    expect(respuesta.responsableNombre, 'Ana Pérez');
    expect(respuesta.fechaCreacion, '2026-10-19T12:00:00Z');
  });

  test('mapea y presenta los eventos del historial PQR', () {
    final evento = PqrHistorialModel.fromJson({
      'id': 3,
      'estado_anterior_codigo': 'RECIBIDA',
      'estado_nuevo_codigo': 'EN_REVISION',
      'responsable_nombre': 'Ana Pérez',
      'usuario_nombre': 'Carlos Ruiz',
      'comentario': 'Cambio de estado',
      'fecha': '2026-10-19T12:00:00Z',
    });

    expect(evento.id, 3);
    expect(evento.titulo, 'Estado actualizado');
    expect(evento.detalle, 'Recibida → En revisión');
    expect(evento.actorNombre, 'Carlos Ruiz');
    expect(evento.fecha, '2026-10-19T12:00:00Z');
  });

  test('presenta los detalles de edición y adjuntos en el historial', () {
    final edicion = PqrHistorialModel.fromJson({
      'id': 4,
      'estado_anterior_codigo': 'RECIBIDA',
      'estado_nuevo_codigo': 'RECIBIDA',
      'responsable_nombre': null,
      'usuario_nombre': 'Juan Pérez',
      'comentario': 'PQR editada; campos modificados: asunto, prioridad',
      'fecha': '2026-10-19T12:00:00Z',
    });
    final adjunto = PqrHistorialModel.fromJson({
      'id': 5,
      'estado_anterior_codigo': 'RECIBIDA',
      'estado_nuevo_codigo': 'RECIBIDA',
      'responsable_nombre': null,
      'usuario_nombre': 'Juan Pérez',
      'comentario': 'Adjunto cargado: evidencia.pdf.',
      'fecha': '2026-10-19T12:00:00Z',
    });

    expect(edicion.titulo, 'Solicitud editada');
    expect(edicion.detalle, 'Campos modificados: asunto, prioridad');
    expect(adjunto.titulo, 'Adjunto cargado');
    expect(adjunto.detalle, 'evidencia.pdf');
  });

  test('mapea el responsable PQR entregado por el backend', () {
    final pqr = Pqr.fromJson({
      'id': 15,
      'radicado': 'PET-2026-000015',
      'tipo': {'nombre': 'Petición'},
      'asunto': 'Revisar luminaria',
      'fecha_radicacion': '2026-10-19T12:00:00Z',
      'estado_codigo': 'RECIBIDA',
      'responsable_id': 4,
      'responsable_nombre': 'Ana Pérez',
    });
    final responsable = PqrResponsable.fromJson({
      'id': 4,
      'nombres': 'Ana',
      'apellidos': 'Pérez',
      'email': 'ana@example.com',
    });

    expect(pqr.responsableId, 4);
    expect(pqr.responsableNombre, 'Ana Pérez');
    expect(responsable.nombreCompleto, 'Ana Pérez');
    expect(responsable.email, 'ana@example.com');
  });

  test('mapea cada estado al siguiente estado y código permitido', () {
    expect(PqrEstado.enviado.siguiente, PqrEstado.recibido);
    expect(PqrEstado.enviado.siguienteCodigo, 'EN_REVISION');
    expect(PqrEstado.recibido.siguiente, PqrEstado.visto);
    expect(PqrEstado.recibido.siguienteCodigo, 'EN_PROCESO');
    expect(PqrEstado.visto.siguiente, PqrEstado.respondido);
    expect(PqrEstado.visto.siguienteCodigo, 'ATENDIDA');
    expect(PqrEstado.respondido.siguiente, PqrEstado.resuelto);
    expect(PqrEstado.respondido.siguienteCodigo, 'CERRADA');
    expect(PqrEstado.resuelto.siguiente, isNull);
    expect(PqrEstado.resuelto.siguienteCodigo, isNull);
  });
}
