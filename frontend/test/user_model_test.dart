import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/models/user_model.dart';

void main() {
  test('construye el usuario con roles y permisos del backend', () {
    final user = UserModel.fromJson({
      'id': 7,
      'tipo_documento': 'CC',
      'numero_documento': '123',
      'nombres': 'Ana',
      'apellidos': 'Pérez',
      'username': 'ana',
      'email': 'ana@example.com',
      'telefono': null,
      'activo': true,
      'roles': ['RESPONSABLE_PQR'],
      'permisos': ['pqr.gestionar', 'inmuebles.consultar'],
    });

    expect(user.nombreCompleto, 'Ana Pérez');
    expect(user.iniciales, 'AP');
    expect(user.rolesVisibles, 'Responsable de PQR');
    expect(user.tienePermiso('pqr.gestionar'), isTrue);
    expect(user.tienePermiso('usuarios.gestionar'), isFalse);
  });

  test('traduce los roles reales y conserva roles desconocidos', () {
    expect(UserModel.nombreRol('ADMIN'), 'Administrador');
    expect(UserModel.nombreRol('RESIDENTE'), 'Residente');
    expect(UserModel.nombreRol('RESPONSABLE_PQR'), 'Responsable de PQR');
    expect(UserModel.nombreRol('OTRO'), 'OTRO');
  });

  test('decodifica foto_perfil en formato data URI base64', () {
    const png1x1 =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    final user = UserModel.fromJson({
      'id': 1,
      'tipo_documento': 'CC',
      'numero_documento': '100',
      'nombres': 'Carlos',
      'apellidos': 'Ruiz',
      'username': 'carlos',
      'email': 'carlos@example.com',
      'activo': true,
      'foto_perfil': png1x1,
      'roles': ['RESIDENTE'],
      'permisos': [],
    });

    expect(user.fotoPerfil, png1x1);
    expect(user.fotoBytes, isNotNull);
    expect(user.fotoBytes!.isNotEmpty, isTrue);
  });
}
