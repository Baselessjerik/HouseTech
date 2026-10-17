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
│   ├── lib/features/auth/        # Login y registro
│   ├── lib/services/             # Comunicación con la API
│   ├── test/                     # Pruebas widget
│   └── pubspec.yaml              # Dependencias Flutter
├── docker-compose.yml            # Backend Django + PostgreSQL
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
base de datos esté saludable, aplica las migraciones y ejecuta Django.

### Servicios y puertos

| Servicio | Descripción | Acceso |
|---|---|---|
| `backend` | API Django en modo desarrollo | `http://localhost:8000` |
| `db` | PostgreSQL 16 | `localhost:5432` |

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

En Docker estas variables están definidas en
[docker-compose.yml](./docker-compose.yml) para el entorno de desarrollo.

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

El frontend guarda los tokens JWT con `flutter_secure_storage`. Para Android
emulado debe usarse `10.0.2.2:8000` en lugar de `127.0.0.1:8000`; en un
dispositivo físico debe configurarse la IP local del equipo que ejecuta Docker.

El frontend tiene cinco pruebas widget en
[frontend/test/auth_screen_test.dart](./frontend/test/auth_screen_test.dart).

## Rama del módulo

La implementación del primer módulo está en la rama `Modulo-1`.

## Marco legal de referencia

- Ley 675 de 2001: régimen de propiedad horizontal.
- Ley 1581 de 2012: protección de datos personales.
- Ley 1273 de 2009: delitos informáticos y protección de la información.
