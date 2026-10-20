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
│   │   ├── comunicados/          # Comunicados, avisos, mantenimientos, bloqueos y notificaciones (Módulo 2)
│   │   └── pqrs/                 # Peticiones, quejas y reclamos (Módulo PQR)
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
│   ├── lib/features/pqrs/        # Tabla CRUD, radicación, estados y adjuntos de PQR (Módulo PQR)
│   ├── lib/shell/                # AppShell con menú dinámico basado en permisos
│   ├── lib/services/             # Comunicación con la API y manejo de JWT
│   ├── test/                     # Pruebas unitarias y widget
│   └── pubspec.yaml              # Dependencias Flutter
├── docs/
│   ├── MODULO2.md                # Documentación detallada del Módulo 2
│   └── MODULO_PQRS.md            # Documentación detallada del Módulo PQR
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

## Módulo PQR (Peticiones, Quejas y Reclamos)

El módulo (documentado a detalle en [docs/MODULO_PQRS.md](./docs/MODULO_PQRS.md)) permite a los residentes clasificar, radicar y consultar peticiones,
quejas y reclamos, y a los responsables/administradores gestionar su ciclo de
vida (`RECIBIDA` → `EN_REVISION` → `EN_PROCESO` → `ATENDIDA` → `CERRADA`). El
flujo para crear una solicitud es:

1. El formulario carga los tipos activos del catálogo desde
   `GET /api/v1/pqrs/tipos/` y muestra Petición, Queja y Reclamo como opciones.
   La persona debe elegir explícitamente una clasificación; el formulario no
   selecciona una opción por defecto.
2. El formulario valida la clasificación, el asunto (mínimo 5 caracteres) y la
   descripción (mínimo 10 caracteres). Al enviar, muestra todos los errores
   presentes en el mismo formulario.
3. El cliente envía `tipo_id`, asunto, descripción y prioridad a
   `POST /api/v1/pqrs/`. El radicado no se genera ni se acepta desde Flutter.
4. El backend asocia la solicitud al usuario autenticado y al estado inicial del
   proceso PQR. PostgreSQL genera el radicado a partir del prefijo del tipo, el
   año y una secuencia compartida, en el formato `PREFIJO-AAAA-NNNNNN` (por
   ejemplo, `PET-2026-000001`). La columna tiene una restricción única.
5. La respuesta exitosa incluye el tipo y el radicado generado. El formulario
   muestra ese número para confirmación y actualiza la lista de solicitudes
   después de cerrar el mensaje de éxito.

El catálogo inicial contiene los siguientes tipos:

| Código | Nombre | Prefijo de radicado |
|---|---|---|
| `PETICION` | Petición | `PET` |
| `QUEJA` | Queja | `QUE` |
| `RECLAMO` | Reclamo | `REC` |

Si no se puede cargar el catálogo, el formulario presenta el error y permite
reintentar. No permite radicar sin tipos disponibles ni sin una clasificación
seleccionada. El tipo de una PQR ya radicada no se puede cambiar mediante la
edición normal, para mantener coherencia con el prefijo del radicado.

### Endpoints del módulo PQR

| Función | Método | Endpoint | Permiso requerido |
|---|---|---|---|
| Catálogo de tipos de PQR | `GET` | `/api/v1/pqrs/tipos/` | `pqr.radicar` |
| Inmuebles del residente | `GET` | `/api/v1/pqrs/mis-inmuebles/` | `pqr.radicar` |
| Listar PQR radicadas | `GET` | `/api/v1/pqrs/` | `pqr.radicar` / `pqr.gestionar` |
| Radicar PQR mediante formulario | `POST` | `/api/v1/pqrs/` | `pqr.radicar` |
| Consultar detalle de una PQR | `GET` | `/api/v1/pqrs/<id>/` | `pqr.radicar` |
| Editar PQR | `PATCH` | `/api/v1/pqrs/<id>/` | `pqr.radicar` (estado Recibida) |
| Eliminar PQR | `DELETE` | `/api/v1/pqrs/<id>/` | `pqr.radicar` (estado Recibida) |
| Cambiar estado de una PQR | `PATCH` | `/api/v1/pqrs/<id>/estado/` | `pqr.gestionar` |
| Listar metadatos de adjuntos | `GET` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` |
| Adjuntar archivo a una PQR | `POST` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` (estado Recibida) |
| Consultar un adjunto | `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` |
| Reemplazar un adjunto | `PATCH` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` (estado Recibida) |
| Eliminar un adjunto | `DELETE` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` (estado Recibida) |
| Descargar adjunto | `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/descargar/` | `pqr.radicar` |

Todos los endpoints requieren autenticación. Las solicitudes creadas por una
persona residente se asocian automáticamente a su usuario. El permiso
`pqr.gestionar` permite consultar todas las PQR y gestionar sus estados; los
residentes consultan sus propias solicitudes.

Los adjuntos se cargan individualmente como `multipart/form-data`, usando el
campo `archivo`, en estado `RECIBIDA` para residentes. Se permiten archivos PDF,
JPG y PNG de hasta 10 MiB por archivo; el backend comprueba que la firma del
contenido coincida con la extensión. Los archivos se guardan en el volumen
persistente `pqr_media` y no se publican mediante una URL directa. El listado
devuelve metadatos; para obtener el contenido se debe usar el endpoint de
descarga autenticado. Los residentes solo pueden listar o descargar adjuntos de
sus propias PQR; quienes tienen permiso `pqr.gestionar` pueden acceder a todas.
Los residentes también pueden reemplazar o eliminar adjuntos mientras la PQR
esté en estado `RECIBIDA`; las operaciones sustituyen o borran el archivo en el
almacenamiento junto con sus metadatos. Los gestores pueden realizar estas
operaciones sobre cualquier PQR.
En Flutter, el formulario permite seleccionar varios archivos y los carga
después de crear la PQR; la tabla de solicitudes ofrece una acción para revisar,
descargar o añadir evidencias posteriormente. Si un archivo falla después de
que la PQR ya fue creada, el formulario conserva el radicado e informa que se
puede reintentar desde las acciones de adjuntos.

Ejemplo del cuerpo para radicar una queja:

```json
{
  "tipo_id": 2,
  "asunto": "Ruido en zona común",
  "descripcion": "El ruido persiste durante la noche en la zona común.",
  "prioridad": "MEDIA"
}
```

El `tipo_id` debe corresponder a un registro activo del catálogo. El campo
`inmueble_id` es opcional y, cuando se envía, el backend verifica que la persona
tenga un vínculo vigente con el inmueble o el permiso de gestión PQR. El cliente
no debe enviar `radicado`, `solicitante` ni `estado`: el servidor determina esos
valores.

Una respuesta exitosa (`201 Created`) incluye, entre otros datos:

```json
{
  "id": 42,
  "radicado": "QUE-2026-000001",
  "tipo": {
    "id": 2,
    "codigo": "QUEJA",
    "nombre": "Queja",
    "prefijo": "QUE"
  },
  "asunto": "Ruido en zona común",
  "prioridad": "MEDIA",
  "estado_codigo": "RECIBIDA"
}
```

### Archivos principales del módulo PQR

| Archivo | Responsabilidad |
|---|---|
| `backend/apps/pqrs/models.py` | Modelos `TipoPQR`, `PQR`, `PQRAdjunto`, `PQRRespuesta` y `PQRHistorial`. |
| `backend/apps/pqrs/serializers.py` | Validación y creación de solicitudes, cambios de estado y adjuntos. |
| `backend/apps/pqrs/views.py` | Vistas y permisos de la API. |
| `backend/apps/pqrs/urls.py` | Rutas del módulo. |
| `backend/apps/core/sql/schema.sql` | Tablas, catálogo, secuencia y triggers SQL. |
| `frontend/lib/models/pqr_model.dart` | Modelos del catálogo, de una PQR y de sus adjuntos. |
| `frontend/lib/services/pqr_service.dart` | Comunicación HTTP con la API PQR. |
| `frontend/lib/services/pqr_file_saver.dart` | Guardado de descargas con implementación específica para web y otras plataformas. |
| `frontend/lib/features/pqrs/presentation/pqr_form_screen.dart` | Selección de tipo, validación, archivos, envío y confirmación de radicación. |
| `frontend/lib/features/pqrs/presentation/pqrs_table_screen.dart` | Listado, búsqueda, cambio de estado y acciones sobre las PQR. |
| `frontend/lib/features/pqrs/presentation/pqr_adjuntos_dialog.dart` | Listado, carga, descarga, reemplazo y eliminación de evidencias vinculadas a una PQR. |

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

El frontend Flutter incluye autenticación completa, menú dinámico según permisos (`AppShell`), las vistas del Módulo 2 y el módulo completo de PQR.
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
- [frontend/test/pqr_model_test.dart](./frontend/test/pqr_model_test.dart)
- [frontend/test/pqr_form_test.dart](./frontend/test/pqr_form_test.dart)
- [frontend/test/pqr_adjuntos_dialog_test.dart](./frontend/test/pqr_adjuntos_dialog_test.dart)

## Ramas del proyecto

- `main`: Rama principal con la integración de los módulos verificados.
- `Modulo-1`: Módulo 1 (Administración, Usuarios, Roles, Permisos y Perfiles).
- `Modulo-2`: Módulo 2 (Comunicados, Mantenimientos y Bloqueos).
- `feat/modulo-pqrs`: Módulo PQR (Peticiones, Quejas, Reclamos, Estados y Adjuntos).

## Marco legal de referencia

- Ley 675 de 2001: régimen de propiedad horizontal.
- Ley 1581 de 2012: protección de datos personales.
- Ley 1273 de 2009: delitos informáticos y protección de la información.
