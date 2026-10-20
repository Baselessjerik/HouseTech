# HouseTech Frontend

Cliente Flutter de HouseTech conectado a la API Django del proyecto. Incluye el
flujo completo de autenticación, navegación principal por permisos (`AppShell`)
y las pantallas del Módulo 2 (Comunicados, Avisos, Notificaciones, Disponibilidad,
Mantenimientos y Bloqueos).

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
| `flutter_riverpod` | Gestión de estado de sesión y datos de módulos |
| `http` | Peticiones HTTP a la API |
| `flutter_secure_storage` | Almacenamiento local seguro de tokens JWT |
| `flutter_test` | Pruebas unitarias y widget |
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

## Autenticación y Menú por Permisos

La pantalla inicial es [AuthScreen](./lib/features/auth/presentation/auth_screen.dart)
y permite cambiar entre inicio de sesión, registro y recuperación de contraseña.
Una vez autenticado, el usuario ingresa a [AppShell](./lib/shell/app_shell.dart),
que construye dinámicamente el menú lateral (escritorio) o drawer (móvil) según
los permisos efectivos devueltos por el backend.

### Inicio de sesión y cierre de sesión

- `POST /api/v1/auth/login/`: acepta `username` (usuario o correo) y `password`,
  almacena `access_token` y `refresh_token` en `flutter_secure_storage` y carga el
  perfil en Riverpod.
- `POST /api/v1/auth/logout/`: revoca los tokens en el backend, elimina
  explícitamente `access_token` y `refresh_token` y limpia la sesión desde el
  botón **Cerrar sesión** del menú lateral.

### Recuperación de contraseña

El enlace **¿Olvidaste tu contraseña?** abre un flujo de tres pasos:

1. Solicita un código mediante `POST /api/v1/auth/recuperar/`.
2. Valida el código de seis dígitos mediante `POST /api/v1/auth/validar-codigo/`.
3. Define la nueva contraseña mediante `POST /api/v1/auth/restablecer/`.

## Módulo 2: Comunicados, Mantenimientos y Bloqueos

Integrado en [AppShell](./lib/shell/app_shell.dart) mediante
[ComunicadosMenu](./lib/features/comunicados/comunicados_menu.dart) según los
permisos del usuario:

- **Comunicados (`comunicados.ver`):** abre `ComunicadosResidentePage` con tres
  vistas:
  - *Avisos*: consulta de comunicados publicados y vigentes con filtro por
    categoría y búsqueda.
  - *Notificaciones*: listado de alertas recibidas con contador de no leídas,
    marcado individual y lectura masiva.
  - *Disponibilidad*: estado actual y próximo de cada amenidad.
- **Administrar comunicados (`comunicados.gestionar`):** abre
  `ComunicadosAdminPage` para crear borradores, segmentar audiencia (`TODOS`,
  `ROL` o `USUARIOS`), publicar, programar, archivar, consultar el historial de
  versiones y gestionar categorías.
- **Bloqueos (`bloqueos.gestionar`):** abre `BloqueosAdminPage` para programar,
  iniciar, finalizar o cancelar mantenimientos y bloqueos temporales de
  amenidades, incluyendo confirmación cuando existen reservas en conflicto.

## Estructura relevante

```text
frontend/
├── lib/
│   ├── config/
│   │   ├── api_config.dart       # URLs base de la API
│   │   ├── app_colors.dart       # Paleta institucional HouseTech
│   │   └── app_theme.dart        # Tema Material 3
│   ├── models/
│   │   └── user_model.dart       # Modelo de usuario, roles y permisos
│   ├── providers/
│   │   └── auth_provider.dart    # Estado de sesión en Riverpod
│   ├── services/
│   │   └── auth_service.dart     # Peticiones y renovación automática de JWT
│   ├── shell/
│   │   └── app_shell.dart        # Navegación responsive basada en permisos
│   ├── features/
│   │   ├── auth/                 # Login, registro y recuperación de contraseña
│   │   └── comunicados/          # Pantallas, modelos, providers y servicios del Módulo 2
│   └── main.dart
├── test/
│   ├── auth_screen_test.dart     # Pruebas de autenticación y recuperación
│   ├── user_model_test.dart      # Pruebas del modelo de usuario y roles
│   ├── app_shell_test.dart       # Pruebas del menú por permisos
│   └── comunicados_test.dart     # Pruebas de modelos y pantallas del Módulo 2
└── pubspec.yaml
```

## Pruebas y análisis

Ejecutar el análisis estático, pruebas y compilación web:

```powershell
flutter analyze
flutter test
flutter build web --no-wasm-dry-run
```
