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
│   │   ├── reservas/             # Amenidades, reservas, bloqueos, agenda y reportes
│   │   └── usuarios/             # Usuarios, roles, permisos y autenticación
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
│   ├── lib/features/auth/        # Login y registro
│   ├── lib/services/             # Comunicación con la API
│   ├── test/                     # Pruebas widget
│   └── pubspec.yaml              # Dependencias Flutter
├── docker-compose.yml            # Backend, frontend y PostgreSQL
└── README.md
```

## Backend

El backend utiliza Django REST Framework, PostgreSQL y JWT. La API incluye
documentación OpenAPI/Swagger y separación de configuraciones para desarrollo y
producción.

### Requisitos

- Docker Desktop, recomendado para ejecutar backend y base de datos.
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
| `scheduler` | Proceso periódico de reservas (cada 5 min) | sin puerto |
| `frontend` | Flutter Web servido por Nginx | `http://localhost:8080` |
| `db` | PostgreSQL 16 | `localhost:5432` |
| `frontend` | Aplicación Flutter web servida por Nginx | `http://localhost:8080` |

Endpoints útiles:

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
docker compose exec backend pip install -r requirements-dev.txt
docker compose exec backend pytest
```

Los datos demo crean usuarios para los roles `admin`, `residente` y
`responsable`. La clave de desarrollo que muestra el comando es
`HouseTech2026!`; no debe reutilizarse en producción.

## Amenidades y reservas

Módulo `backend/apps/reservas`. El esquema base está en `core/sql/schema.sql`; los ajustes del módulo
(triggers de validación, historial y utilidades) están en
[reservas_v2.sql](./backend/apps/reservas/sql/reservas_v2.sql) y se aplican con
`python manage.py migrate`. Los errores de regla de negocio de los triggers usan el SQLSTATE `23P01`
y la API los devuelve como HTTP 409 con el mensaje.

| Requisito | Qué hace | Endpoint |
|---|---|---|
| Registrar zonas comunes y configurar aforo, horarios y políticas de cancelación | `capacidad` = aforo máximo de personas por reserva; `horarios` = franjas por día (1 = lunes ... 7 = domingo); `reglas` = duración, anticipación, cupo mensual por inmueble, `horas_limite_cancelacion` y `requiere_confirmacion`. Una amenidad no se borra: se desactiva. | `GET/POST /api/v1/amenidades/`, `PATCH /api/v1/amenidades/{id}/`, `POST .../activar/`, `POST .../desactivar/` |
| RF5-RF6 / RF11: verificar disponibilidad y bloquear solapamientos o sobre-reservas, también contra bloqueos | Valida amenidad activa, horario, duración, anticipación, aforo, cupo mensual, choque con otras reservas y con bloqueos (409 si hay conflicto de agenda, 400 si incumple una regla). El trigger `fn_validar_reserva` repite las validaciones críticas como respaldo ante concurrencia. | `GET /api/v1/amenidades/{id}/verificar/?inicio=&fin=&num_personas=`, `POST /api/v1/reservas/` |
| Bloqueos | Un bloqueo con reservas vigentes devuelve 409; con `cancelar_reservas=true` las cancela. | `GET/POST /api/v1/bloqueos/`, `POST .../{id}/cancelar/` |
| RF11: historial de reservas | Línea de tiempo de estados (quién, cuándo, por qué) llenada por trigger. | `GET /api/v1/reservas/{id}/historial/`, `GET /api/v1/reservas/?estado=&amenidad=&desde=&hasta=` |
| RF12: agenda y calendario de disponibilidad | Franjas libres/ocupadas de un día y agenda por rango. El residente ve las reservas ajenas como "Ocupado". | `GET /api/v1/amenidades/{id}/disponibilidad/?fecha=`, `GET /api/v1/amenidades/{id}/calendario/`, `GET /api/v1/agenda/` |
| Reportes de ocupación e históricos, con filtros | Ocupación = horas reservadas / horas de funcionamiento, por amenidad, con serie por día/semana/mes, hora pico, uso de aforo y tasa de cancelación. Histórico paginado. Ambos exportan CSV con `?formato=csv`. Requiere el permiso `reportes.ver`. | `GET /api/v1/reportes/ocupacion/`, `GET /api/v1/reportes/reservas/` |

Filtros de reportes: `desde`, `hasta`, `amenidad` (ids separados por coma), `estado` (códigos separados
por coma), `inmueble`, `usuario`, `agrupar` (`dia`, `semana`, `mes`) e `incluir_inactivas`.

### Solicitar, confirmar, rechazar y cancelar reservas

| Acción | Quién | Endpoint |
|---|---|---|
| Solicitar | Residente (`reservas.solicitar`); la administración puede reservar a nombre de otro con `usuario` | `POST /api/v1/reservas/` |
| Confirmar / rechazar | Administración (`amenidades.gestionar`) | `POST /api/v1/reservas/{id}/confirmar/`, `.../rechazar/` (con `motivo`) |
| Cancelar | El titular hasta `horas_limite_cancelacion` horas antes del inicio; la administración mientras siga vigente | `POST /api/v1/reservas/{id}/cancelar/` |

Ciclo: `SOLICITADA` -> `CONFIRMADA` -> `FINALIZADA`, o `RECHAZADA` / `CANCELADA` / `EXPIRADA`. Si la amenidad
no requiere confirmación (`requiere_confirmacion = false`), la reserva nace `CONFIRMADA`.

**Liberación automática.** Una solicitud sin confirmar pasa a `EXPIRADA` (estado final: libera el horario)
cuando vence su plazo: `horas_limite_confirmacion` de la amenidad (24 h por defecto) contadas desde que se
solicitó, o el inicio de la reserva si llega antes. Una solicitud vencida no puede confirmarse y, aunque el
proceso periódico aún no la haya liberado, tampoco bloquea nuevas reservas. El historial registra el cambio
sin usuario (lo hizo el sistema) y el titular recibe un aviso. Las reservas ya confirmadas nunca se liberan.

**Recordatorios y notificaciones.** Se guardan en la tabla `notificaciones` y se envían también por correo
(según la configuración `EMAIL_*`; con el backend de consola salen en los logs).

| Evento | Destinatario |
|---|---|
| Solicitud creada | Titular y administradores |
| Confirmada, rechazada, cancelada por otra persona o por un bloqueo, liberada por falta de confirmación | Titular |
| Recordatorio `horas_recordatorio` horas antes del inicio de una reserva confirmada (24 h por defecto; `0` = sin recordatorio). Se envía una sola vez | Titular |
| Solicitud por vencer (la mitad del plazo, máximo 6 h antes) | Administradores |

Cada usuario consulta las suyas en `GET /api/v1/notificaciones/` (filtros `leida` y `tipo`),
`GET /api/v1/notificaciones/resumen/` (contador de no leídas), `POST /api/v1/notificaciones/{id}/leer/` y
`POST /api/v1/notificaciones/leer-todas/`.

**Proceso periódico.** `python manage.py procesar_reservas` libera solicitudes vencidas, envía recordatorios y
finaliza las reservas terminadas; es idempotente. En Docker lo ejecuta cada 5 minutos el servicio `scheduler`
(`docker compose up -d --build`). Un administrador también puede lanzarlo a demanda con
`POST /api/v1/reservas/procesar/`. Fuera de Docker, programa el comando con cron o el Programador de tareas.

`seed_demo` crea ahora cuatro amenidades de ejemplo (salón social, piscina, gimnasio y cancha).

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

El frontend Flutter incluye el módulo de autenticación conectado al backend.
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
flutter analyze
flutter test
flutter build web
```

La pantalla de autenticación utiliza:

| Función | Endpoint |
|---|---|
| Inicio de sesión | `POST /api/v1/auth/login/` |
| Registro | `POST /api/v1/auth/registro/` |
| Solicitar recuperación | `POST /api/v1/auth/recuperar/` |
| Validar código | `POST /api/v1/auth/validar-codigo/` |
| Restablecer contraseña | `POST /api/v1/auth/restablecer/` |

El frontend guarda los tokens JWT con `flutter_secure_storage`. Para Android
emulado debe usarse `10.0.2.2:8000` en lugar de `127.0.0.1:8000`; en un
dispositivo físico debe configurarse la IP local del equipo que ejecuta Docker.

El frontend tiene nueve pruebas widget en
[frontend/test/auth_screen_test.dart](./frontend/test/auth_screen_test.dart).

## Rama del módulo

La implementación del primer módulo está en la rama `Modulo-1`.

## Marco legal de referencia

- Ley 675 de 2001: régimen de propiedad horizontal.
- Ley 1581 de 2012: protección de datos personales.
- Ley 1273 de 2009: delitos informáticos y protección de la información.
