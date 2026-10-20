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
│   │   ├── pqrs/                 # Peticiones, quejas y reclamos (PQR)
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
│   ├── lib/features/pqrs/        # Tabla CRUD y radicación de PQR
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

### Módulo PQR (Peticiones, Quejas y Reclamos)

El módulo permite a los residentes clasificar, radicar y consultar peticiones,
quejas y reclamos. El flujo para crear una solicitud es:

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

#### Endpoints del módulo

| Función | Método | Endpoint | Permiso requerido |
|---|---|---|---|
| Catálogo de tipos de PQR | `GET` | `/api/v1/pqrs/tipos/` | `pqr.radicar` |
| Inmuebles del residente | `GET` | `/api/v1/pqrs/mis-inmuebles/` | `pqr.radicar` |
| Listar mis PQR radicadas | `GET` | `/api/v1/pqrs/` | `pqr.radicar` |
| Radicar PQR mediante formulario | `POST` | `/api/v1/pqrs/` | `pqr.radicar` |
| Consultar detalle de una PQR | `GET` | `/api/v1/pqrs/<id>/` | `pqr.radicar` |
| Editar PQR | `PATCH` | `/api/v1/pqrs/<id>/` | `pqr.radicar` (estado Recibida) |
| Consultar historial de eventos | `GET` | `/api/v1/pqrs/<id>/historial/` | `pqr.radicar` |
| Eliminar PQR | `DELETE` | `/api/v1/pqrs/<id>/` | `pqr.radicar` (estado Recibida); gestores pueden borrar |
| Consultar respuestas | `GET` | `/api/v1/pqrs/<id>/respuestas/` | `pqr.radicar` |
| Registrar respuesta | `POST` | `/api/v1/pqrs/<id>/respuestas/` | Administrador o responsable asignado |
| Listar metadatos de adjuntos | `GET` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` |
| Adjuntar archivo a una PQR | `POST` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` (estado Recibida) |
| Consultar un adjunto | `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` |
| Reemplazar un adjunto | `PATCH` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` (estado Recibida) |
| Eliminar un adjunto | `DELETE` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` (estado Recibida) |
| Descargar adjunto | `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/descargar/` | `pqr.radicar` |

Todos los endpoints requieren autenticación. Las solicitudes creadas por una
persona residente se asocian automáticamente a su usuario. El permiso
`pqr.gestionar` permite consultar las PQR para gestión; los residentes consultan
sus propias solicitudes.
El historial presenta en orden cronológico la radicación, cambios de estado,
asignaciones, ediciones, respuestas y operaciones de adjuntos. El backend impide
eliminar una PQR revisada a residentes. Si una PQR se elimina de forma permitida,
la base de datos elimina también sus respuestas, adjuntos e historial; los
archivos adjuntos se limpian del almacenamiento.

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

#### Archivos principales

| Archivo | Responsabilidad |
|---|---|
| `backend/apps/pqrs/models.py` | Modelos `TipoPQR` y `PQR`. |
| `backend/apps/pqrs/serializers.py` | Validación y creación de solicitudes. |
| `backend/apps/pqrs/views.py` | Vistas y permisos de la API. |
| `backend/apps/pqrs/urls.py` | Rutas del módulo. |
| `backend/apps/core/sql/schema.sql` | Tablas, catálogo, secuencia y trigger SQL. |
| `frontend/lib/models/pqr_model.dart` | Modelos del catálogo y de una PQR. |
| `frontend/lib/services/pqr_service.dart` | Comunicación HTTP con la API PQR. |
| `frontend/lib/services/pqr_file_saver.dart` | Guardado de descargas con implementación específica para web y otras plataformas. |
| `frontend/lib/features/pqrs/presentation/pqr_form_screen.dart` | Selección de tipo, validación, archivos, envío y confirmación de radicación. |
| `frontend/lib/features/pqrs/presentation/pqrs_table_screen.dart` | Listado, búsqueda y acciones sobre las PQR. |
| `frontend/lib/features/pqrs/presentation/pqr_adjuntos_dialog.dart` | Listado, carga, descarga, reemplazo y eliminación de evidencias vinculadas a una PQR. |

#### Pruebas del módulo PQR

Desde la raíz del repositorio, las pruebas automatizadas pueden ejecutarse así:

```powershell
# Backend (Pytest en Docker)
docker compose exec backend pytest apps/pqrs/tests/test_registro_pqr.py -v

# Frontend (Flutter widget tests)
cd frontend
flutter test test/pqr_form_test.dart
```

Las pruebas frontend del formulario verifican que los errores de clasificación,
asunto y descripción se muestren a la vez dentro del formulario, que el tipo se
elija explícitamente, que se envíe el identificador seleccionado, que se
presente el radicado devuelto por el backend y que el usuario pueda reintentar
si falla la carga del catálogo.

## Rama del módulo

La implementación del primer módulo está en la rama `Modulo-1`.

## Marco legal de referencia

- Ley 675 de 2001: régimen de propiedad horizontal.
- Ley 1581 de 2012: protección de datos personales.
- Ley 1273 de 2009: delitos informáticos y protección de la información.
