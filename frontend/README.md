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

La API responde en `http://127.0.0.1:8000` y el frontend Dockerizado en
`http://127.0.0.1:8080`. La configuración de la API está en
[api_config.dart](./lib/config/api_config.dart).

Después, desde `frontend`:

```powershell
flutter run -d chrome
```

También se puede usar Edge:

```powershell
flutter run -d edge
```

### Ejecutar todo con Docker

Desde la raíz del repositorio:

```powershell
docker compose up -d --build
```

Esto inicia PostgreSQL, el backend Django y el frontend Flutter compilado y
servido por Nginx. Abre `http://localhost:8080` para revisar la aplicación.

Comandos útiles:

```powershell
docker compose ps
docker compose logs -f frontend
docker compose up -d --build frontend
docker compose down
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

El enlace **¿Olvidaste tu contraseña?** abre un flujo de tres pasos:

1. Solicita un código mediante `POST /api/v1/auth/recuperar/`.
2. Valida el código de seis dígitos mediante
   `POST /api/v1/auth/validar-codigo/`.
3. Define la nueva contraseña mediante
   `POST /api/v1/auth/restablecer/`.

El código vence en 15 minutos y solo se consume al restablecer la contraseña.
La interfaz no revela si el correo existe. El correo enviado por SMTP incluye
una versión HTML con el código destacado en negrita y una versión de texto
plano. Si SMTP no está configurado, el backend muestra el mensaje en sus logs.

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

El módulo de autenticación cuenta actualmente con nueve pruebas widget que
validan el renderizado, formularios, validaciones, visibilidad de la contraseña
y navegación del flujo de recuperación.

## Estado actual

- Login conectado al backend.
- Registro conectado al backend.
- Tokens JWT almacenados localmente.
- Pruebas widget implementadas.
- Recuperación y restablecimiento de contraseña conectados al backend.
- La navegación posterior al login y el consumo de los endpoints protegidos
  quedan para el siguiente módulo.
