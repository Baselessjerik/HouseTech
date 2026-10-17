# HouseTech Frontend

Cliente Flutter de HouseTech. Actualmente incluye el módulo de autenticación
con conexión a la API Django del proyecto.

## Requisitos

- Flutter 3.47.6 o compatible con Dart 3.13.5.
- Dart SDK incluido con Flutter.
- Docker Desktop si se utilizará el backend local.
- Un dispositivo o navegador compatible con Flutter.

Verificar la instalación:

```powershell
flutter --version
flutter doctor
```

## Instalación

Desde esta carpeta:

```powershell
flutter pub get
```

Las dependencias principales son:

| Paquete | Uso |
|---|---|
| `flutter_riverpod` | Estado de la aplicación existente |
| `http` | Peticiones HTTP a la API |
| `flutter_secure_storage` | Almacenamiento local de tokens JWT |
| `flutter_test` | Pruebas widget |
| `flutter_lints` | Análisis estático |

## Ejecutar con el backend local

Primero inicia el backend desde la raíz del repositorio:

```powershell
docker compose up -d --build
```

La API debe responder en `http://127.0.0.1:8000`. La configuración está en
[api_config.dart](./lib/config/api_config.dart).

Después, desde `frontend`:

```powershell
flutter run -d chrome
```

También se puede usar Edge:

```powershell
flutter run -d edge
```

Para Android emulado, `127.0.0.1` apunta al propio emulador. En ese caso usa
`10.0.2.2:8000` en `ApiConfig.baseUrl`. En un dispositivo físico, utiliza la
IP local del equipo que ejecuta Docker.

## Autenticación implementada

La pantalla inicial es [AuthScreen](./lib/features/auth/presentation/auth_screen.dart)
y permite cambiar entre inicio de sesión y registro.

### Inicio de sesión

```http
POST /api/v1/auth/login/
```

Envía `username` (usuario o correo) y `password`. Al recibir los tokens, el
servicio los guarda con `flutter_secure_storage`.

### Registro

```http
POST /api/v1/auth/registro/
```

Envía:

```json
{
  "tipo_documento": "CC",
  "numero_documento": "123456789",
  "nombres": "Ana",
  "apellidos": "Pérez",
  "username": "ana",
  "email": "ana@example.com",
  "telefono": "3000000000",
  "password": "ClaveSegura123!"
}
```

El backend asigna automáticamente el rol `RESIDENTE`.

### Recuperación de contraseña

El enlace **¿Olvidaste tu contraseña?** abre un flujo de dos pasos que solo
solicita el correo electrónico asociado a la cuenta:

1. Solicita un código de recuperación:

   ```http
   POST /api/v1/auth/recuperar/
   ```

   ```json
   {
     "identificador": "ana@example.com"
   }
   ```

2. Valida el código de seis dígitos recibido por correo:

   ```http
   POST /api/v1/auth/validar-codigo/
   ```

   La validación confirma el código sin consumirlo y habilita el formulario
   para crear la nueva contraseña.

3. Introduce la nueva contraseña:

   ```http
   POST /api/v1/auth/restablecer/
   ```

   ```json
   {
     "identificador": "ana@example.com",
     "codigo": "123456",
     "password_nueva": "NuevaClaveSegura123!"
   }
   ```

El código tiene una vigencia de 15 minutos. Por seguridad, la interfaz muestra
el mismo mensaje de confirmación tanto si el correo existe como si no existe.
En el entorno local, el backend puede mostrar el código en la consola de
Django en lugar de enviarlo a un proveedor de correo real.

## Estructura relevante

```text
frontend/
├── lib/
│   ├── config/
│   │   ├── api_config.dart       # URL de la API
│   │   ├── app_colors.dart       # Colores de autenticación
│   │   └── app_theme.dart        # Tema general
│   ├── features/auth/
│   │   └── presentation/
│   │       ├── auth_screen.dart
│   │       ├── forgot_password_screen.dart
│   │       └── widgets/
│   │           ├── housetech_logo.dart
│   │           ├── login_form.dart
│   │           └── register_form.dart
│   ├── services/
│   │   └── auth_service.dart     # Peticiones y tokens JWT
│   └── main.dart
├── test/
│   └── auth_screen_test.dart      # Pruebas widget
└── pubspec.yaml
```

## Pruebas y análisis

Ejecutar todas las pruebas:

```powershell
flutter test
```

Ejecutar el análisis:

```powershell
flutter analyze
```

Crear una compilación web:

```powershell
flutter build web
```

El módulo de autenticación cuenta actualmente con siete pruebas widget que
validan el renderizado, cambio de formulario, validaciones, visibilidad de la
contraseña y navegación al flujo de recuperación.

## Estado actual

- Login conectado al backend.
- Registro conectado al backend.
- Tokens JWT almacenados localmente.
- Pruebas widget implementadas.
- Recuperación y restablecimiento de contraseña conectados al backend.
- La navegación posterior al login y el consumo de los endpoints protegidos
  quedan para el siguiente módulo.
