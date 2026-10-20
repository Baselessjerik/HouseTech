# HouseTech

Plataforma SaaS de gestión residencial para automatizar y centralizar la
administración de conjuntos residenciales bajo el régimen de propiedad
horizontal en Colombia.

## Estructura del proyecto

```text
HouseTech/
├── backend/
│   ├── apps/
│   │   ├── core/                 # Esquema SQL, auditoría y utilidades comunes
│   │   ├── inmuebles/            # Inmuebles y relación usuario-inmueble
│   │   ├── usuarios/             # Usuarios, roles, permisos y autenticación (Módulo 1)
│   │   └── comunicados/          # Comunicados, avisos, mantenimientos, bloqueos y notificaciones (Módulo 2)
│   ├── config/
│   │   ├── settings/
│   │   │   ├── base.py           # Configuración compartida
│   │   │   ├── dev.py            # Desarrollo local/Docker
│   │   │   └── prod.py           # Producción
│   │   ├── urls.py               # Rutas principales de la API
│   │   ├── asgi.py
│   │   └── wsgi.py
│   ├── manage.py                 # Comandos de administración Django
│   ├── requirements.txt          # Dependencias de ejecución
│   ├── requirements-dev.txt      # Dependencias de pruebas
│   ├── Dockerfile
│   └── .env.example
├── frontend/                     # Cliente web y móvil Flutter
│   ├── Dockerfile                # Compilación Flutter y servidor Nginx
│   ├── nginx.conf                # Configuración del frontend web
│   ├── lib/features/auth/        # Login, registro y recuperación de contraseña
│   ├── lib/features/comunicados/ # Avisos, comunicados, categorías, mantenimientos y bloqueos (Módulo 2)
│   ├── lib/shell/                # AppShell con menú dinámico basado en permisos
│   ├── lib/services/             # Comunicación con la API y manejo de JWT
│   ├── test/                     # Pruebas unitarias y widget
│   └── pubspec.yaml              # Dependencias Flutter
├── docs/
│   └── MODULO2.md                # Documentación detallada del Módulo 2
├── docker-compose.yml            # Backend, frontend y PostgreSQL
└── README.md
```

## Backend

El backend utiliza Django REST Framework, PostgreSQL y JWT. La API incluye
documentación OpenAPI/Swagger y separación de configuraciones para desarrollo y
producción.

### Requisitos

- Docker Desktop, recomendado para ejecutar backend, frontend y base de datos.
- O Python 3.10 o superior y PostgreSQL si se ejecuta sin Docker.
- Flutter 3.47.6 o compatible con Dart 3.13.5 para el frontend.
- Git.

## Ejecutar con Docker

Desde la raíz del repositorio, con Docker Desktop iniciado:

```powershell
docker compose up -d --build
```

El comando construye la imagen del backend, inicia PostgreSQL, espera a que la
base de datos esté saludable, aplica las migraciones y ejecuta Django. También
compila y sirve el frontend Flutter mediante Nginx.

### Servicios y puertos

| Servicio | Descripción | Acceso |
|---|---|---|
| `backend` | API Django en modo desarrollo | `http://localhost:8000` |
| `frontend` | Aplicación Flutter Web servida por Nginx | `http://localhost:8080` |
| `db` | PostgreSQL 16 | `localhost:5432` |

Endpoints útiles:

- Healthcheck: `http://localhost:8000/api/v1/health/`
- Swagger: `http://localhost:8000/api/docs/`
- Esquema OpenAPI: `http://localhost:8000/api/schema/`

Comprobar el estado:

```powershell
docker compose ps
```

Ver logs:

```powershell
docker compose logs -f backend
docker compose logs -f db
docker compose logs -f frontend
```

Detener los servicios sin eliminar los datos:

```powershell
docker compose down
```

Detenerlos y eliminar también el volumen de PostgreSQL:

```powershell
docker compose down -v
```

### Acceder a los contenedores

Abrir una shell en el backend:

```powershell
docker compose exec backend sh
```

Ejecutar comandos de Django directamente:

```powershell
docker compose exec backend python manage.py showmigrations
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py seed_demo
docker compose exec backend python manage.py seed_modulo2
docker compose exec backend python manage.py publicar_comunicados_programados
```

Conectarse a PostgreSQL:

```powershell
docker compose exec db psql -U housetech -d housetech
```

Credenciales de desarrollo:

```text
Host: localhost
Puerto: 5432
Base de datos: housetech
Usuario: housetech
Contraseña: housetech
```

Estas credenciales son únicamente para desarrollo local. Deben cambiarse antes
de cualquier despliegue.

## Variables de entorno

La configuración usa `backend/.env` cuando se ejecuta fuera de Docker. Para
crear ese archivo:

```powershell
Copy-Item backend\.env.example backend\.env
```

Variables principales:

| Variable | Uso |
|---|---|
| `SECRET_KEY` | Clave criptográfica de Django |
| `DEBUG` | Activa/desactiva el modo desarrollo |
| `ALLOWED_HOSTS` | Hosts permitidos |
| `DATABASE_URL` | URL de conexión PostgreSQL |
| `JWT_ACCESS_MINUTES` | Duración del token de acceso |
| `JWT_REFRESH_DAYS` | Duración del token de renovación |
| `EMAIL_BACKEND` | Backend de correo; consola o SMTP |
| `EMAIL_HOST` | Servidor SMTP, por ejemplo `smtp.gmail.com` |
| `EMAIL_PORT` | Puerto SMTP, normalmente `587` con TLS |
| `EMAIL_USE_TLS` | Activa TLS para SMTP |
| `EMAIL_HOST_USER` | Cuenta que enviará los correos |
| `EMAIL_HOST_PASSWORD` | Contraseña de aplicación SMTP |
| `DEFAULT_FROM_EMAIL` | Dirección visible del remitente |
| `COMUNICADOS_NOTIFICAR_EMAIL` | Si es `true`, envía también por correo las notificaciones del Módulo 2 |

En Docker estas variables están definidas en
[docker-compose.yml](./docker-compose.yml) para el entorno de desarrollo.
Por defecto se mantiene el backend de consola. Para Gmail, copia
[backend/.env.example](./backend/.env.example) a `backend/.env`, configura
una contraseña de aplicación y cambia `EMAIL_BACKEND` a
`django.core.mail.backends.smtp.EmailBackend`. Nunca subas `backend/.env` al
repositorio.

Para enviar correos reales durante las pruebas, configura una cuenta SMTP
dedicada (por ejemplo, Gmail con una contraseña de aplicación) en
`backend/.env`. El backend usa `EmailMultiAlternatives`: los clientes
compatibles reciben un correo HTML con el código destacado y los demás
reciben la versión de texto plano. Sin SMTP configurado, los mensajes se
muestran en los logs del backend.

## Migraciones, datos demo y pruebas

El esquema inicial se crea desde
[schema.sql](./backend/apps/core/sql/schema.sql). Los modelos que reflejan
tablas existentes usan `managed = False`; la migración SQL inicial se ejecuta
con Django.

Comandos habituales dentro de Docker:

```powershell
docker compose exec backend python manage.py makemigrations
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py seed_demo
docker compose exec backend python manage.py seed_modulo2
docker compose exec -T backend pytest -q
```

- `seed_demo` crea la copropiedad base y los usuarios demo para los roles `ADMIN` (`admin`), `RESIDENTE` (`residente`) y `RESPONSABLE_PQR` (`responsable`). La clave de desarrollo inicial es `HouseTech2026!`; no debe reutilizarse en producción.
- `seed_modulo2` crea amenidades de ejemplo (`Piscina`, `Salón social`, `Gimnasio`, `Cancha múltiple`), mantenimientos, bloqueos y comunicados en distintos estados (`PUBLICADO`, `BORRADOR`, `PROGRAMADO`).

## Módulo 2: Comunicados, Mantenimientos y Bloqueos

El Módulo 2 (documentado a detalle en [docs/MODULO2.md](./docs/MODULO2.md)) incorpora la gestión de comunicados residenciales, disponibilidad y bloqueos temporales de amenidades, mantenimientos programados y notificaciones internas:

### Endpoints principales del Módulo 2 (`/api/v1/`)

| Recurso | Métodos | Permiso requerido | Descripción |
|---|---|---|---|
| `mantenimientos/` | `GET`, `POST`, `PATCH`, `POST {id}/iniciar\|finalizar\|cancelar/` | `bloqueos.gestionar` | Programación y ciclo de vida de mantenimientos de zonas comunes |
| `bloqueos/` | `GET`, `POST`, `PATCH`, `POST {id}/cancelar/` | `bloqueos.gestionar` | Bloqueos temporales de amenidades con detección de cruces (`409`) y reservas en conflicto |
| `amenidades/disponibilidad/` | `GET` (`?momento=`) | Autenticado | Consulta en tiempo real del estado de cada amenidad (`DISPONIBLE`, `RESERVADA`, `BLOQUEADA`, `EN_MANTENIMIENTO`) |
| `categorias-comunicado/` | `GET` / `POST`, `PATCH`, `DELETE` | `comunicados.ver` / `comunicados.gestionar` | Clasificación de avisos con etiquetas de color |
| `comunicados/` | `GET`, `POST`, `PATCH`, `POST {id}/publicar\|programar\|archivar/`, `GET {id}/historial/` | `comunicados.gestionar` | Gestión administrativa de comunicados, programación, archivo y trazabilidad de versiones |
| `avisos/` | `GET` | `comunicados.ver` | Consulta de avisos publicados, vigentes y segmentados según la audiencia del usuario (`TODOS`, `ROL`, `USUARIOS`) |
| `notificaciones/` | `GET`, `POST {id}/leer/`, `POST leer-todas/`, `GET no-leidas/conteo/` | Autenticado | Bandeja de notificaciones de comunicados, mantenimientos, bloqueos y reservas afectadas |
| `comunicados-opciones/roles/` y `usuarios/` | `GET` | `comunicados.gestionar` | Opciones de audiencia por rol o destinatarios específicos |

## Ejecución local sin Docker

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
Copy-Item .env.example .env
python manage.py migrate
python manage.py runserver
```

Para Linux/macOS, el equivalente para activar el entorno es
`source .venv/bin/activate`.

## Frontend Flutter

El frontend Flutter incluye autenticación completa, menú dinámico según permisos (`AppShell`) y las vistas del Módulo 2 para residentes y administradores.
Consulta la documentación específica en
[frontend/README.md](./frontend/README.md).

Desde la raíz del repositorio, inicia primero la API:

```powershell
docker compose up -d --build
```

Después ejecuta el cliente:

```powershell
cd frontend
flutter pub get
flutter run -d chrome
```

Para ejecutar backend, base de datos y frontend juntos usando Docker:

```powershell
docker compose up -d --build
```

Abre la aplicación en `http://localhost:8080`. Para reconstruir únicamente el
frontend después de cambios:

```powershell
docker compose up -d --build frontend
```

Comandos de validación del frontend:

```powershell
cd frontend
flutter analyze
flutter test
flutter build web --no-wasm-dry-run
```

Endpoints de autenticación y perfil utilizados en el frontend:

| Función | Endpoint |
|---|---|
| Inicio de sesión | `POST /api/v1/auth/login/` |
| Renovación de token | `POST /api/v1/auth/refresh/` |
| Cierre de sesión | `POST /api/v1/auth/logout/` |
| Perfil autenticado | `GET / PATCH /api/v1/auth/me/` |
| Cambiar contraseña | `POST /api/v1/auth/cambiar-password/` |
| Registro | `POST /api/v1/auth/registro/` |
| Solicitar recuperación | `POST /api/v1/auth/recuperar/` |
| Validar código | `POST /api/v1/auth/validar-codigo/` |
| Restablecer contraseña | `POST /api/v1/auth/restablecer/` |

El frontend guarda los tokens JWT con `flutter_secure_storage`. Para Android
emulado debe usarse `10.0.2.2:8000` en lugar de `127.0.0.1:8000`; en un
dispositivo físico debe configurarse la IP local del equipo que ejecuta Docker.

Las pruebas automatizadas del frontend están en:
- [frontend/test/auth_screen_test.dart](./frontend/test/auth_screen_test.dart)
- [frontend/test/user_model_test.dart](./frontend/test/user_model_test.dart)
- [frontend/test/app_shell_test.dart](./frontend/test/app_shell_test.dart)
- [frontend/test/comunicados_test.dart](./frontend/test/comunicados_test.dart)

## Ramas del proyecto

- `main`: Rama principal con la integración de los módulos verificados.
- `Modulo-1`: Módulo 1 (Administración, Usuarios, Roles, Permisos y Perfiles).
- `Modulo-2`: Módulo 2 (Comunicados, Mantenimientos y Bloqueos).

## Marco legal de referencia

- Ley 675 de 2001: régimen de propiedad horizontal.
- Ley 1581 de 2012: protección de datos personales.
- Ley 1273 de 2009: delitos informáticos y protección de la información.
