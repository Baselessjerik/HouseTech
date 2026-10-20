import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:housetech_frontend/models/user_model.dart';
import 'package:housetech_frontend/providers/auth_provider.dart';
import 'package:housetech_frontend/shell/app_shell.dart';

UserModel userWith(List<String> permisos, {List<String>? roles}) {
  return UserModel(
    id: 1,
    tipoDocumento: 'CC',
    numeroDocumento: '123',
    nombres: 'Ana',
    apellidos: 'Pérez',
    username: 'ana',
    email: 'ana@example.com',
    telefono: null,
    activo: true,
    roles: roles ?? const ['RESIDENTE'],
    permisos: permisos,
  );
}

class SeededAuthSessionNotifier extends AuthSessionNotifier {
  SeededAuthSessionNotifier(this.user);
  final UserModel user;

  @override
  UserModel build() => user;
}

Future<void> pumpShell(WidgetTester tester, UserModel user) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => SeededAuthSessionNotifier(user),
        ),
      ],
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el menú del residente según sus permisos',
      (tester) async {
    await pumpShell(
        tester,
        userWith(const [
          'comunicados.ver',
          'inmuebles.consultar',
          'pqr.radicar',
          'reservas.solicitar',
        ]));

    expect(find.text('Inicio'), findsNWidgets(2));
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Inmuebles'), findsOneWidget);
    expect(find.text('Usuarios'), findsNothing);
    expect(find.text('Roles y permisos'), findsNothing);
    expect(find.text('Reportes'), findsNothing);
  });

  testWidgets('muestra las opciones administrativas del administrador',
      (tester) async {
    await pumpShell(
      tester,
      userWith(
        const [
          'usuarios.gestionar',
          'inmuebles.consultar',
          'roles.gestionar',
          'configuracion.gestionar',
          'reportes.ver',
          'auditoria.ver',
        ],
        roles: const ['ADMIN'],
      ),
    );

    expect(find.text('Usuarios'), findsOneWidget);
    expect(find.text('Inmuebles'), findsOneWidget);
    expect(find.text('Roles y permisos'), findsOneWidget);
    expect(find.text('Parametrización'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Auditoría'), findsOneWidget);
  });

  testWidgets('conecta las opciones del Módulo 2 en el menú de AppShell',
      (tester) async {
    await pumpShell(
      tester,
      userWith(
        const [
          'comunicados.ver',
          'comunicados.gestionar',
          'bloqueos.gestionar',
        ],
        roles: const ['ADMIN'],
      ),
    );

    expect(find.text('Comunicados'), findsOneWidget);
    expect(find.text('Administrar comunicados'), findsOneWidget);
    expect(find.text('Bloqueos'), findsOneWidget);
  });
}
