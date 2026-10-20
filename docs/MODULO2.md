# Módulo 2 · Comunicados, mantenimientos y bloqueos (Iteración 3: RF1–RF16)

Módulo autocontenido: usa el esquema de `commands.sql` (idéntico a `schema.sql`) y las convenciones del Módulo 1.
No crea tablas ni permisos nuevos.

> **Estado de verificación:** el código se escribió leyendo el repositorio del Módulo 1 y el SQL, pero **no se ejecutó**
> (el entorno donde se generó no tiene Django, PostgreSQL ni Flutter). Corre los comandos de la sección 3 y
> envíame cualquier error: se corrige rápido.

## 1. Qué contiene

```
backend/apps/comunicados/        app nueva (modelos, services, serializers, views, urls, tests, comandos)
backend/config/urls.py           + 1 línea (// MODULO-2)
backend/config/settings/base.py  + 1 línea (// MODULO-2)
frontend/lib/features/comunicados/   pantallas, modelos, servicio y providers
frontend/lib/shell/app_shell.dart    + 2 líneas (// MODULO-2)
frontend/test/comunicados_test.dart  pruebas de widgets y modelos
```

Solo 3 archivos existentes cambian (en total 4 líneas). Todo lo demás es nuevo.

## 2. Instalación

1. Copia las carpetas del zip sobre el repositorio (respetando rutas). Los tres archivos compartidos
   (`urls.py`, `base.py`, `app_shell.dart`) ya traen las líneas marcadas con `MODULO-2`; si prefieres no
   sobrescribirlos, añade a mano:
   - `config/settings/base.py` → `"apps.comunicados",` en `INSTALLED_APPS`
   - `config/urls.py` → `path("api/v1/", include("apps.comunicados.urls")),`
   - `lib/shell/app_shell.dart` → el `import` de `comunicados_menu.dart` y las 2 líneas dentro de `add(...)`
2. No hay nada que instalar: no se añaden dependencias a `requirements.txt` ni a `pubspec.yaml`.

## 3. Ejecutar y probar

```bash
cd backend
python manage.py migrate                 # crea el esquema (core) y el estado de la app nueva
python manage.py seed_demo               # usuarios demo (admin / residente)
python manage.py seed_modulo2            # amenidades, mantenimientos, bloqueos y comunicados de ejemplo
python manage.py runserver
pytest apps/comunicados                  # pruebas del módulo
```

```bash
cd frontend
flutter pub get
flutter analyze && flutter test
flutter run -d chrome
```

Usuarios demo: `admin` / `residente`, clave `HouseTech2026!`.
Swagger: <http://127.0.0.1:8000/api/docs/>

Orden sugerido para verificar manualmente:
1. Entra como **admin** → *Bloqueos* → crea un mantenimiento con bloqueo (RF1, RF2–RF4).
2. Entra como **residente** → *Comunicados* → pestaña *Notificaciones* (RF8) y *Disponibilidad* (RF6).
3. Como admin → *Administrar comunicados* → crea, programa, publica, edita y mira el historial (RF9–RF13, RF15).
4. Como residente → *Avisos*: solo ve lo publicado y vigente (RF14) y recibe la notificación (RF16).

## 4. Publicación programada (RF13)

No hay Celery. Dos mecanismos que se complementan:
- Comando idempotente, agéndalo cada minuto:
  `* * * * * cd /ruta/backend && python manage.py publicar_comunicados_programados`
  (en Docker puedes lanzarlo con un servicio extra que haga `while true; do python manage.py publicar_comunicados_programados; sleep 60; done`).
- Publicación perezosa: cada consulta a `GET /avisos/` publica antes lo que ya venció, así el residente nunca ve un aviso atrasado.

Opcional: `COMUNICADOS_NOTIFICAR_EMAIL=true` envía también correo (usa el `EMAIL_*` ya configurado en settings).

## 5. API (prefijo `/api/v1/`)

| Recurso | Métodos | Permiso | RF |
|---|---|---|---|
| `mantenimientos/` | GET, POST, PATCH · `POST {id}/iniciar|finalizar|cancelar/` | `bloqueos.gestionar` | 1, 8 |
| `bloqueos/` | GET, POST, PATCH · `POST {id}/cancelar/` | `bloqueos.gestionar` | 2–5, 7, 8 |
| `amenidades/disponibilidad/?momento=` · `amenidades/{id}/disponibilidad/` | GET | autenticado | 6 |
| `categorias-comunicado/` | GET (activas) / POST, PATCH, DELETE | `comunicados.ver` / `comunicados.gestionar` | 12 |
| `comunicados/` | GET, POST, PATCH · `POST {id}/publicar|programar|archivar/` · `GET {id}/historial/` | `comunicados.gestionar` | 9–13, 15 |
| `avisos/` | GET (publicados, vigentes y visibles para el usuario) | `comunicados.ver` | 14 |
| `notificaciones/` · `POST {id}/leer/` · `POST leer-todas/` · `GET no-leidas/conteo/` | | autenticado | 8, 16 |
| `comunicados-opciones/roles/` · `comunicados-opciones/usuarios/?search=` | GET | `comunicados.gestionar` | formularios |

Reglas clave:
- Bloqueo y mantenimiento **no se borran**: se cancelan.
- Crear/editar un bloqueo que cruce otro bloqueo activo → **409** `bloqueo_cruzado`.
- Si hay reservas en ese horario → **409** `reservas_en_conflicto` con la lista; repetir con `?confirmar=true` crea el
  bloqueo y notifica a los dueños (tipo `RESERVA`). Las reservas **no se cancelan** solas.
- RF5 (no reservar en un bloqueo) lo garantiza el trigger de la BD (`23P01` → 409).
- Audiencia `TODOS` = usuarios activos con el permiso `comunicados.ver`.
- Comunicados `ARCHIVADOS` no se editan; los `PUBLICADOS` sí (queda historial por trigger).

## 6. Puntos de integración al unir los 4 módulos

1. **Rutas**: en `config/urls.py` incluir `apps.comunicados.urls` **antes** de las rutas de amenidades, para que
   `amenidades/disponibilidad/` no sea capturada por `amenidades/<pk>/`.
2. **Modelos de lectura**: `AmenidadRef` y `ReservaRef` (en `apps/comunicados/models.py`) apuntan a las tablas
   `amenidades` y `reservas`. Si el módulo de reservas define sus modelos, se pueden reemplazar por los reales
   (ajustando los imports en `services.py`, `serializers.py` y `tests/conftest.py`).
3. **Notificaciones**: `services.crear_notificaciones(...)` es reutilizable por los demás módulos (PQR, reservas).
4. **Menú**: el shell llama a `ComunicadosMenu.paginaPara(permiso)`; los otros módulos pueden seguir el mismo patrón.
5. **Seeds**: `seed_modulo2` crea amenidades de ejemplo si no existen; si el módulo de amenidades trae su propio seed,
   basta con ejecutar este después.
6. **Migraciones**: `comunicados/0001_initial` solo registra estado (modelos `managed = False`) y depende de
   `core.0002_initial` y `usuarios.0001_initial`; no choca con las de otros módulos.
7. **Pantalla vieja**: `features/avisos/avisos_page.dart` (datos de ejemplo del Módulo 1) queda sin uso; no se tocó.

## 7. Supuestos y límites

- Notificaciones por canal `APP` (y correo opcional). No hay push (FCM); la tabla `dispositivos` existe para añadirlo luego.
- La paginación del cliente usa "Cargar más" (20 por página, como el backend).
- El formulario de destinatarios específicos lista como máximo 25 usuarios por búsqueda.
- La zona horaria se guarda en UTC y se muestra en la hora local del dispositivo.
