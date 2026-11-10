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

## Módulo PQR (Peticiones, Quejas y Reclamos)
 
El módulo permite a los residentes radicar y consultar peticiones, quejas y
reclamos, y a la administración y a los responsables gestionarlos: asignación,
cambios de estado, respuestas, evidencias y trazabilidad.
 
### Roles, permisos y visibilidad
 
Todos los endpoints requieren autenticación y el permiso `pqr.radicar`. La
asignación de responsable exige además el permiso de administración
`usuarios.gestionar`. Una PQR que el usuario no puede ver responde `404`.
 
| Rol | Permisos de PQR (según `schema.sql`) | PQR que puede consultar |
|---|---|---|
| `ADMIN` | `pqr.radicar`, `pqr.gestionar` y `usuarios.gestionar` (tiene todos los permisos) | Todas |
| `RESPONSABLE_PQR` | `pqr.radicar` y `pqr.gestionar` | Las que tiene asignadas y las que radicó |
| `RESIDENTE` | `pqr.radicar` | Solo las que radicó |
 
Un usuario sin ninguno de estos roles no ve ninguna PQR. El permiso
`pqr.gestionar` identifica a quienes gestionan solicitudes (por ejemplo, fijar
la prioridad o radicar sobre cualquier inmueble); como el administrador también
lo tiene, el backend y el cliente distinguen al administrador por
`usuarios.gestionar`. La visibilidad depende del rol, no de estos permisos.
 
### Flujo de radicación
 
1. El formulario carga los tipos activos del catálogo desde
   `GET /api/v1/pqrs/tipos/` y muestra Petición, Queja y Reclamo como opciones.
   La persona debe elegir explícitamente una clasificación; el formulario no
   selecciona una opción por defecto.
2. El formulario valida la clasificación, el asunto (mínimo 5 caracteres) y la
   descripción (mínimo 10 caracteres). Al enviar, muestra todos los errores
   presentes en el mismo formulario.
3. El cliente envía `tipo_id`, `asunto`, `descripcion` y, opcionalmente,
   `inmueble_id` a `POST /api/v1/pqrs/`. El radicado no se genera ni se acepta
   desde Flutter.
4. El backend asocia la solicitud al usuario autenticado y al estado inicial del
   proceso PQR (`RECIBIDA`). PostgreSQL genera el radicado a partir del prefijo
   del tipo, el año y una secuencia compartida, en el formato
   `PREFIJO-AAAA-NNNNNN` (por ejemplo, `PET-2026-000001`). La columna tiene una
   restricción única. La secuencia no se reinicia cada año.
5. La respuesta exitosa (`201 Created`) incluye el detalle de la PQR con el tipo
   y el radicado generado. El formulario muestra ese número para confirmación y
   actualiza la lista de solicitudes después de cerrar el mensaje de éxito.
El catálogo inicial contiene los siguientes tipos:
 
| Código | Nombre | Prefijo de radicado |
|---|---|---|
| `PETICION` | Petición | `PET` |
| `QUEJA` | Queja | `QUE` |
| `RECLAMO` | Reclamo | `REC` |
 
Cada tipo del catálogo incluye también `descripcion` y `sla_dias` (tiempo de
atención estimado; el esquema inicial usa 15 días en los tres tipos y el
backend no lo aplica automáticamente).
 
Si no se puede cargar el catálogo, el formulario presenta el error y permite
reintentar. No permite radicar sin tipos disponibles ni sin una clasificación
seleccionada. El tipo de una PQR ya radicada no se puede cambiar mediante la
edición, para mantener coherencia con el prefijo del radicado.
 
#### Prioridad
 
Los valores válidos son `BAJA`, `MEDIA` y `ALTA`. La prioridad la asigna la
administración: cuando radica o edita una persona sin el permiso
`pqr.gestionar`, el backend ignora el campo `prioridad` y la solicitud conserva
el valor base `MEDIA`.
 
#### Inmueble asociado
 
`inmueble_id` es opcional. Si se envía, debe ser un inmueble activo y el backend
verifica que la persona tenga un vínculo vigente con él (sin `fecha_fin`) o el
permiso `pqr.gestionar`. `GET /api/v1/pqrs/mis-inmuebles/` devuelve las opciones
para el selector: los gestores ven todos los inmuebles activos y el resto solo
los vinculados a su usuario.
 
### Ciclo de vida de una PQR
 
Los estados pertenecen al proceso `PQR` del catálogo general (`estados`).
`schema.sql` siembra `RECIBIDA` (inicial), `EN_REVISION`, `EN_PROCESO`,
`ATENDIDA`, `CERRADA` y `ANULADA` (estos dos últimos son estados finales). Sin
la fila `ANULADA` activa, la anulación responde `400`, y sin la marca de final
no se registra `fecha_cierre`. Las transiciones permitidas son:
 
| Estado actual | Destinos permitidos |
|---|---|
| `RECIBIDA` | `EN_REVISION`, `ANULADA` |
| `EN_REVISION` | `EN_PROCESO`, `ANULADA` |
| `EN_PROCESO` | `ATENDIDA`, `ANULADA` |
| `ATENDIDA` | `CERRADA`, `ANULADA` |
| `CERRADA` | Ninguno |
| `ANULADA` | Ninguno |
 
Reglas del flujo:
 
- **Cambiar de estado** (`PATCH /pqrs/<id>/estado/`): solo el administrador o el
  responsable asignado. La transición se valida contra la tabla anterior y la
  fila se bloquea durante el cambio para evitar solicitudes simultáneas.
- **Anular**: cualquier persona con acceso a la PQR puede anularla, pero debe
  indicar un `motivo` de al menos 5 caracteres. Quien no es administrador solo
  puede anular en `RECIBIDA` o `EN_REVISION`; el administrador puede hacerlo en
  cualquier etapa que lo permita la tabla.
- **Asignar responsable** (`PATCH /pqrs/<id>/responsable/`): solo el
  administrador. El responsable debe ser un usuario activo con el rol activo
  `RESPONSABLE_PQR`. Si la PQR está en `RECIBIDA` o `EN_REVISION`, la asignación
  la pasa automáticamente a `EN_PROCESO`.
- **Responder**: una respuesta del administrador o del responsable asignado pasa
  la PQR a `ATENDIDA`; si se marca `es_solucion`, la pasa a `CERRADA`. La
  respuesta de quien radicó la PQR es un mensaje de seguimiento: no marca
  solución ni cambia el estado. No se admiten respuestas en `CERRADA` ni
  `ANULADA`.
- **Cierre**: los triggers de la base de datos actualizan `fecha_cierre` cuando
  el nuevo estado está marcado como final.
### Edición y anulación
 
- `PATCH /api/v1/pqrs/<id>/` no admite modificaciones cuando la PQR está
  `CERRADA` o `ANULADA` (`400`).
- Quien no tiene el permiso `pqr.gestionar` solo puede editar mientras la PQR
  esté en `RECIBIDA` (`403` en otro caso).
- No se puede cambiar el tipo, y la prioridad se ignora si no se tiene el
  permiso `pqr.gestionar`.
- Cada edición registra un evento en el historial con los campos modificados.
- **Las PQR no se eliminan.** El endpoint `/api/v1/pqrs/<id>/` no admite `DELETE`
  (responde `405`); para dejar sin efecto una solicitud se usa la anulación.
### Historial y respuestas
 
`GET /api/v1/pqrs/<id>/historial/` presenta en orden cronológico la radicación,
cambios de estado, asignaciones, ediciones, respuestas y operaciones de
adjuntos. Los cambios de estado y de responsable los registran triggers de la
base de datos (comentarios `PQR radicada`, `Cambio de estado` y `Cambio de
responsable`); si una misma actualización cambia ambos, como al asignar una PQR
que pasa a `EN_PROCESO`, se guarda un solo evento `Cambio de responsable`. El
resto de eventos los registra la aplicación. Además, los triggers de auditoría
guardan en la tabla `auditoria` cada alta, cambio y borrado de `pqr` y
`pqr_respuestas`, junto con el usuario indicado en `app.usuario_id`. Cada evento
incluye el estado anterior y nuevo, el responsable, el usuario que lo originó,
un comentario y la fecha.
 
`GET /api/v1/pqrs/<id>/respuestas/` devuelve las respuestas en orden
cronológico, con el nombre de quien respondió y si la respuesta es la solución.
 
### Endpoints del módulo
 
Rutas relativas a `/api/v1/`.
 
| Función | Método | Endpoint | Quién puede |
|---|---|---|---|
| Catálogo de tipos de PQR | `GET` | `/pqrs/tipos/` | `pqr.radicar` |
| Inmuebles disponibles para radicar | `GET` | `/pqrs/mis-inmuebles/` | `pqr.radicar` |
| Listar PQR visibles según rol | `GET` | `/pqrs/` | `pqr.radicar` |
| Radicar PQR | `POST` | `/pqrs/` | `pqr.radicar` |
| Consultar detalle | `GET` | `/pqrs/<id>/` | `pqr.radicar` (PQR visible) |
| Editar PQR | `PATCH` | `/pqrs/<id>/` | Residente: estado `RECIBIDA`; gestores: no `CERRADA` ni `ANULADA` |
| Cambiar estado | `PATCH` | `/pqrs/<id>/estado/` | Administrador o responsable asignado; anular: ver reglas |
| Asignar o reasignar responsable | `PATCH` | `/pqrs/<id>/responsable/` | `usuarios.gestionar` |
| Consultar historial | `GET` | `/pqrs/<id>/historial/` | `pqr.radicar` (PQR visible) |
| Consultar respuestas | `GET` | `/pqrs/<id>/respuestas/` | `pqr.radicar` (PQR visible) |
| Registrar respuesta | `POST` | `/pqrs/<id>/respuestas/` | Administrador, responsable asignado o solicitante |
| Listar metadatos de adjuntos | `GET` | `/pqrs/<id>/adjuntos/` | `pqr.radicar` (PQR visible) |
| Adjuntar archivo | `POST` | `/pqrs/<id>/adjuntos/` | Residente: estado `RECIBIDA`; gestores: cualquier estado |
| Consultar un adjunto | `GET` | `/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` (PQR visible) |
| Reemplazar un adjunto | `PATCH` | `/pqrs/<id>/adjuntos/<adjunto_id>/` | Residente: estado `RECIBIDA`; gestores: cualquier estado |
| Eliminar un adjunto | `DELETE` | `/pqrs/<id>/adjuntos/<adjunto_id>/` | Residente: estado `RECIBIDA`; gestores: cualquier estado |
| Descargar adjunto | `GET` | `/pqrs/<id>/adjuntos/<adjunto_id>/descargar/` | `pqr.radicar` (PQR visible) |
 
### Adjuntos
 
Los adjuntos se cargan individualmente como `multipart/form-data`, usando el
campo `archivo`. Se permiten archivos PDF, JPG y PNG de hasta 10 MiB por
archivo; el backend comprueba que la firma del contenido coincida con la
extensión y no confía en el tipo MIME enviado por el cliente. El archivo se
guarda con un nombre aleatorio en el volumen persistente `pqr_media` y no se
publica mediante una URL directa.
 
El listado devuelve solo metadatos (`id`, `nombre_archivo`, `tipo_mime`,
`tamano_bytes`, `created_at`); para obtener el contenido se debe usar el
endpoint de descarga autenticado. Reemplazar un adjunto exige enviar de nuevo el
campo `archivo`; el archivo anterior se borra del almacenamiento solo cuando el
reemplazo se confirma. Eliminar un adjunto borra la fila y el archivo. Cargar,
reemplazar y eliminar quedan registrados en el historial de la PQR.
 
En Flutter, el formulario permite seleccionar varios archivos y los carga
después de crear o actualizar la PQR; el detalle de la solicitud lista los
adjuntos con opción de ver imágenes y descargarlos. Si un archivo falla después
de que la PQR ya fue creada, el formulario conserva el radicado, informa qué
archivos fallaron y se pueden volver a cargar editando la solicitud.
 
### Cliente Flutter
 
`PqrService` (`frontend/lib/services/pqr_service.dart`) centraliza las llamadas
HTTP del módulo. Adjunta el token de acceso guardado en
`flutter_secure_storage`; si una solicitud responde `401`, renueva el token con
el refresh token (`POST /auth/refresh/`) y repite la solicitud una vez.
 
| Método de `PqrService` | Endpoint |
|---|---|
| `obtenerTiposPqr` | `GET /pqrs/tipos/` |
| `obtenerMisInmuebles` | `GET /pqrs/mis-inmuebles/` |
| `obtenerMisPqrs` | `GET /pqrs/` (acepta lista simple o paginada con `results`) |
| `obtenerDetallePqr` | `GET /pqrs/<id>/` |
| `radicarPqr` | `POST /pqrs/` |
| `actualizarPqr`, `cambiarPrioridadPqr` | `PATCH /pqrs/<id>/` |
| `cambiarEstadoPqr` | `PATCH /pqrs/<id>/estado/` (envía `motivo` al anular) |
| `obtenerResponsablesPqr` | `GET /usuarios/?rol=RESPONSABLE_PQR&activo=true` (recorre todas las páginas) |
| `asignarResponsablePqr` | `PATCH /pqrs/<id>/responsable/` |
| `obtenerHistorialPqr` | `GET /pqrs/<id>/historial/` |
| `obtenerRespuestasPqr`, `registrarRespuestaPqr` | `GET` y `POST /pqrs/<id>/respuestas/` |
| `obtenerAdjuntosPqr`, `subirAdjuntoPqr`, `actualizarAdjuntoPqr`, `eliminarAdjuntoPqr`, `descargarAdjuntoPqr` | Endpoints de adjuntos |
 
En `pqr_model.dart`, el enum `PqrEstado` traduce los códigos de estado del
backend (`RECIBIDA`, `EN_REVISION`, `EN_PROCESO`, `ATENDIDA`, `CERRADA`,
`ANULADA`) a la etiqueta, el ícono y el color que muestra la interfaz; un código
desconocido se presenta como "Recibida". Además, el cliente construye el título
y el detalle de cada evento del historial a partir del texto del comentario
(`PQR radicada`, `Cambio de estado`, `Cambio de responsable`, `PQR editada…`,
`Adjunto cargado: …`, `PQR anulada. Motivo: …`, entre otros). Si cambian esos
textos en el backend o en los triggers, también debe actualizarse
`PqrHistorialModel`.
 
#### Pantalla de solicitudes
 
El menú de `frontend/lib/shell/app_shell.dart` abre `PqrsTableScreen` según los
permisos del usuario:
 
| Opción del menú | Permiso | Indicadores que recibe la pantalla |
|---|---|---|
| "Gestionar PQR" | `pqr.gestionar` | `puedeGestionarEstados` (`pqr.gestionar`); `puedeAsignarResponsable` y `esAdministrador` (`usuarios.gestionar`) |
| "Mis PQRs" | `pqr.radicar` (si no tiene `pqr.gestionar`) | Solo el `usuarioId` |
 
Con esos indicadores la pantalla decide qué acciones muestra. El backend vuelve
a validar cada operación.
 
- **Pestañas:** "Bandeja activa" (solicitudes no finalizadas) e "Historial"
  (`CERRADA` y `ANULADA`).
- **Búsqueda y filtros:** búsqueda por radicado, asunto, tipo, solicitante o
  responsable, y filtros por estado, usuario, tipo, responsable, prioridad y
  rango de fechas. Se aplican en el cliente sobre la lista cargada.
- **Acciones de cada tarjeta** (se ocultan en solicitudes finalizadas):
| Acción | Quién la ve | Condición |
|---|---|---|
| Ver solicitud | Todos | Siempre |
| Asignar o cambiar responsable | Quien tiene `puedeAsignarResponsable` | Solicitud no finalizada |
| Editar | Gestores; el resto solo con la PQR en `RECIBIDA` | Solicitud no finalizada |
| Cambiar prioridad (selector en la tarjeta) | Gestores | Solicitud no finalizada |
| Cerrar | Administrador o responsable asignado | Solo en `ATENDIDA` |
| Anular | Administrador en cualquier etapa; solicitante o responsable asignado solo en `RECIBIDA` o `EN_REVISION` | Pide un motivo de al menos 5 caracteres |
 
- **Apertura automática:** cuando un administrador abre el detalle de una PQR
  en `RECIBIDA`, el cliente la pasa a `EN_REVISION`.
- **Asignación:** el diálogo lista los responsables activos, permite buscarlos
  por nombre o correo y guarda con `PATCH /pqrs/<id>/responsable/`.
#### Detalle de la solicitud
 
El detalle tiene tres pestañas: Información, Respuestas y Seguimiento
(historial), además de un panel con el avance del estado. Las solicitudes
`CERRADA` o `ANULADA` se muestran en modo de solo lectura. El campo para
responder aparece mientras la PQR esté abierta y solo para el administrador, el
responsable asignado o quien la radicó; la opción "Marcar como solución" solo
la tienen el administrador y el responsable asignado.
 
Al responder con archivos, el cliente registra primero la respuesta y luego
sube cada archivo como adjunto de la PQR. El backend no vincula adjuntos con
respuestas específicas: el cliente los asocia mostrando los archivos cuyo
nombre aparece en el texto de la respuesta. Quien no tiene el permiso
`pqr.gestionar` solo puede subir adjuntos mientras la PQR esté en `RECIBIDA`;
en otros estados la respuesta se guarda y el cliente informa que los archivos
fallaron.
 
#### Formulario
 
El mismo formulario radica y edita. En edición, el tipo no se puede cambiar, se
listan los archivos actuales (ver imagen o eliminar) y los archivos nuevos se
suben después de guardar. El formulario no incluye selector de prioridad: la
radicación envía `MEDIA` y la prioridad se cambia desde la tarjeta, solo para
gestores.
 
### Ejemplos de cuerpos de solicitud
 
Radicar una queja como residente (no se envía `prioridad`; si se envía, se
ignora):
 
```json
{
  "tipo_id": 2,
  "inmueble_id": 5,
  "asunto": "Ruido en zona común",
  "descripcion": "El ruido persiste durante la noche en la zona común."
}
```
 
Cambiar el estado (`PATCH /pqrs/<id>/estado/`):
 
```json
{ "estado_codigo": "EN_REVISION" }
```
 
Anular una PQR (el `motivo` es obligatorio):
 
```json
{
  "estado_codigo": "ANULADA",
  "motivo": "Solicitud duplicada."
}
```
 
Asignar un responsable (`PATCH /pqrs/<id>/responsable/`):
 
```json
{ "responsable_id": 3 }
```
 
Registrar una respuesta (`POST /pqrs/<id>/respuestas/`):
 
```json
{
  "respuesta": "Se realizó la visita y se resolvió el inconveniente.",
  "es_solucion": true
}
```
 
Una respuesta exitosa al radicar (`201 Created`) tiene esta forma (valores de
ejemplo):
 
```json
{
  "id": 42,
  "radicado": "QUE-2026-000001",
  "solicitante_id": 7,
  "tipo": {
    "id": 2,
    "codigo": "QUEJA",
    "nombre": "Queja",
    "prefijo": "QUE",
    "descripcion": "Inconformidad con un servicio o una conducta",
    "sla_dias": 15
  },
  "asunto": "Ruido en zona común",
  "descripcion": "El ruido persiste durante la noche en la zona común.",
  "prioridad": "MEDIA",
  "estado_codigo": "RECIBIDA",
  "estado_nombre": "Recibida",
  "solicitante_nombre": "Nombre del residente",
  "inmueble_codigo": "T1-101",
  "inmueble_id": 5,
  "responsable_id": null,
  "responsable_nombre": null,
  "fecha_radicacion": "2026-11-09T17:30:00-05:00",
  "fecha_cierre": null
}
```
 
El `tipo_id` debe corresponder a un registro activo del catálogo. El cliente
no debe enviar `radicado`, `solicitante` ni `estado`: el servidor determina esos
valores.
 
### Archivos principales
 
| Archivo | Responsabilidad |
|---|---|
| `backend/apps/pqrs/models.py` | Modelos `TipoPQR`, `PQR`, `PQRAdjunto`, `PQRRespuesta` y `PQRHistorial`. |
| `backend/apps/pqrs/serializers.py` | Validación de radicación, edición, adjuntos, respuestas, transiciones y asignación; representación de detalle e historial. |
| `backend/apps/pqrs/views.py` | Vistas, visibilidad por rol, reglas de estado y permisos de la API. |
| `backend/apps/pqrs/urls.py` | Rutas del módulo. |
| `backend/apps/pqrs/tests/test_registro_pqr.py` | Pruebas del backend del módulo. |
| `backend/apps/core/sql/schema.sql` | Tablas, catálogo, secuencia y triggers SQL (radicado, historial, cierre). |
| `frontend/lib/models/pqr_model.dart` | Modelos de tipo, inmueble, PQR, adjunto, responsable, respuesta e historial, y enum `PqrEstado` que traduce los códigos de estado del backend. |
| `frontend/lib/services/pqr_service.dart` | Cliente HTTP de la API PQR con renovación automática del token (ver "Cliente Flutter"). |
| `frontend/lib/services/pqr_file_saver.dart` | Guardado de descargas; implementaciones `pqr_file_saver_web.dart` y `pqr_file_saver_stub.dart` según la plataforma. |
| `frontend/lib/features/pqrs/pqr_detail_modal.dart` | Detalle con pestañas de información, respuestas y seguimiento; registro de respuestas con archivos; vista y descarga de adjuntos. |
| `frontend/lib/features/pqrs/presentation/pqr_form_screen.dart` | Formulario de radicación y edición: selección de tipo, validación, archivos, envío y confirmación del radicado. |
| `frontend/lib/features/pqrs/presentation/pqrs_table_screen.dart` | Bandeja activa e historial, búsqueda, filtros y acciones (asignar, editar, prioridad, cerrar y anular). |
| `frontend/lib/features/pqrs/presentation/pqr_adjuntos_dialog.dart` | Listado, carga, descarga, reemplazo y eliminación de evidencias vinculadas a una PQR. Ninguna pantalla actual lo abre. |
| `frontend/lib/features/pqrs/presentation/pqr_visor_adjunto_dialog.dart` | Previsualización de un adjunto (imagen o aviso de PDF) con botón de descarga. Ninguna pantalla actual lo abre. || `frontend/lib/shell/app_shell.dart` | Menú por permisos; abre `PqrsTableScreen` como "Gestionar PQR" o "Mis PQRs". || `frontend/lib/config/api_config.dart` | URL base y rutas de la API usadas por el cliente. |
 
### Pruebas del módulo PQR
 
Desde la raíz del repositorio, las pruebas automatizadas pueden ejecutarse así:
 
```powershell
# Backend (Pytest en Docker)
docker compose exec backend pytest apps/pqrs/tests/test_registro_pqr.py -v
 
# Frontend (Flutter widget tests)
cd frontend
flutter test test/pqr_form_test.dart
flutter test test/pqr_adjuntos_dialog_test.dart
flutter test test/pqr_detail_modal_test.dart
flutter test test/pqr_model_test.dart
```
 
Las pruebas del backend (`apps/pqrs/tests/test_registro_pqr.py`) usan las
semillas de `schema.sql` (roles, permisos, estados, incluido `ANULADA`, y tipos
de PQR) y cubren:
 
- catálogo de tipos; radicación, prefijo del radicado por tipo y consecutivos
  distintos; validación de asunto y descripción; tipo inmutable tras radicar;
- prioridad: ignorada para residentes y editable por gestores;
- visibilidad por rol, detalle e historial con aislamiento entre residentes;
- edición con registro en el historial y bloqueo en `RECIBIDA`, `CERRADA` y
  `ANULADA`; rechazo del borrado de PQR;
- ciclo de estados, saltos inválidos y permisos para cambiar el estado;
- anulación con motivo, según rol y etapa;
- asignación de responsable;
- respuestas (solución, seguimiento del solicitante y estados finales);
- adjuntos (carga, validación de extensión, firma y tamaño, permisos por
  estado, listado, descarga, reemplazo y eliminación).
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
