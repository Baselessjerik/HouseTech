import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:housetech_frontend/features/auth/presentation/auth_screen.dart';

void main() {
  Widget buildSubject() => const MaterialApp(home: AuthScreen());

  testWidgets('muestra el formulario de inicio de sesión', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byIcon(Icons.apartment_rounded), findsOneWidget);
    expect(find.text('Usuario o correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('permite cambiar al formulario de registro', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre de usuario'), findsOneWidget);
    expect(find.text('Documento'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Ingresar'), findsNothing);
  });

  testWidgets('valida campos obligatorios del login', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Completa usuario y contraseña'), findsOneWidget);
  });

  testWidgets('valida campos obligatorios del registro', (tester) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.text('Registrarse'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Crear cuenta'));
    await tester.tap(find.text('Crear cuenta'));
    await tester.pump();

    expect(find.text('Completa los campos obligatorios'), findsOneWidget);
  });

  testWidgets('permite mostrar y ocultar la contraseña', (tester) async {
    await tester.pumpWidget(buildSubject());

    final passwordField = tester.widget<TextField>(
      find.byType(TextField).at(1),
    );
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();

    final visibleField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(visibleField.obscureText, isFalse);
  });
}
