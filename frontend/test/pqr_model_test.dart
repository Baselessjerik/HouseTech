import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/models/pqr_model.dart';

void main() {
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
