# Módulo PQR · Peticiones, Quejas y Reclamos

Módulo integrado sobre el esquema oficial de `schema.sql` (`managed = False`) y el sistema de autenticación, roles, permisos y auditoría de HouseTech.

---

## 1. Contenido del módulo

```text
backend/apps/pqrs/
├── models.py                    # Modelos TipoPQR, PQR, PQRAdjunto, PQRRespuesta y PQRHistorial
├── serializers.py               # Validación de radicación, transiciones de estado y adjuntos
├── views.py                     # Vistas REST, control de permisos por rol y descarga segura
├── urls.py                      # Rutas del módulo bajo /api/v1/pqrs/
└── tests/
    └── test_registro_pqr.py     # Suite de pruebas Pytest (22 tests)

frontend/lib/
├── models/pqr_model.dart        # Modelos de tipos, solicitudes PQR, inmuebles y adjuntos
├── services/
│   ├── pqr_service.dart         # Cliente HTTP autenticado para todos los endpoints PQR
│   ├── pqr_file_saver.dart      # Exportación condicional para descarga de archivos
│   ├── pqr_file_saver_web.dart  # Guardado en navegador web
│   └── pqr_file_saver_stub.dart # Guardado en plataformas nativas / pruebas
└── features/pqrs/presentation/
    ├── pqrs_table_screen.dart   # Tabla CRUD, filtros, estados y acciones de PQR
    ├── pqr_form_screen.dart     # Formulario de radicación y edición con carga de evidencias
    └── pqr_adjuntos_dialog.dart # Modal para listar, subir, reemplazar, eliminar y descargar adjuntos

frontend/test/
├── pqr_model_test.dart
├── pqr_form_test.dart
└── pqr_adjuntos_dialog_test.dart
```

---

## 2. Permisos y roles

| Rol | Código interno | Permisos PQR asignados | Acceso en menú (`AppShell`) |
|---|---|---|---|
| Administrador | `ADMIN` | `pqr.radicar`, `pqr.gestionar` | **Gestionar PQR** (ve todas las PQR, cambia estados y gestiona adjuntos) |
| Responsable de PQR | `RESPONSABLE_PQR` | `pqr.radicar`, `pqr.gestionar` | **Gestionar PQR** (ve todas las PQR, cambia estados y gestiona adjuntos) |
| Residente | `RESIDENTE` | `pqr.radicar` | **Mis PQRs** (radica y consulta sus propias PQR; edita/elimina en estado `RECIBIDA`) |

---

## 3. Catálogo de tipos y numeración de radicados

PostgreSQL genera automáticamente el número de radicado mediante el trigger `trg_pqr_before` y la secuencia `seq_pqr_radicado` con el formato `PREFIJO-AAAA-NNNNNN`:

| Código | Nombre | Prefijo | Ejemplo de radicado |
|---|---|---|---|
| `PETICION` | Petición | `PET` | `PET-2026-000001` |
| `QUEJA` | Queja | `QUE` | `QUE-2026-000002` |
| `RECLAMO` | Reclamo | `REC` | `REC-2026-000003` |

---

## 4. Ciclo de vida y estados (`proceso = 'PQR'`)

Las transiciones son validadas en backend (`PQR_TRANSICIONES_VALIDAS`) y registradas automáticamente en `pqr_historial` mediante el trigger `trg_pqr_hist`:

1. `RECIBIDA` *(estado inicial al radicar; único estado en el que el residente puede editar o eliminar su solicitud o sus adjuntos)*
2. `EN_REVISION` *(transición desde `RECIBIDA`)*
3. `EN_PROCESO` *(transición desde `EN_REVISION`)*
4. `ATENDIDA` *(transición desde `EN_PROCESO`; registra `fecha_cierre`)*
5. `CERRADA` *(estado final; transición desde `ATENDIDA`)*

---

## 5. Endpoints REST (`/api/v1/`)

| Método | Ruta | Permiso | Descripción |
|---|---|---|---|
| `GET` | `/api/v1/pqrs/tipos/` | `pqr.radicar` | Lista los tipos activos del catálogo (`PETICION`, `QUEJA`, `RECLAMO`). |
| `GET` | `/api/v1/pqrs/mis-inmuebles/` | `pqr.radicar` | Lista los inmuebles activos vinculados al usuario autenticado. |
| `GET` | `/api/v1/pqrs/` | `pqr.radicar` / `pqr.gestionar` | Lista todas las PQR (si tiene `pqr.gestionar`) o las del usuario autenticado. |
| `POST` | `/api/v1/pqrs/` | `pqr.radicar` | Radica una nueva PQR en estado inicial `RECIBIDA`. |
| `GET` | `/api/v1/pqrs/<id>/` | `pqr.radicar` | Consulta el detalle de una PQR autorizada. |
| `PUT` / `PATCH` | `/api/v1/pqrs/<id>/` | `pqr.radicar` | Actualiza asunto, descripción, prioridad o inmueble (residentes solo en `RECIBIDA`). |
| `DELETE` | `/api/v1/pqrs/<id>/` | `pqr.radicar` | Elimina una PQR y sus archivos físicos (residentes solo en `RECIBIDA`). |
| `PATCH` | `/api/v1/pqrs/<id>/estado/` | `pqr.gestionar` | Avanza el estado de la PQR según las transiciones permitidas. |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` | Lista los metadatos de los archivos adjuntos de la PQR. |
| `POST` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` | Sube un adjunto (`multipart/form-data`, campo `archivo`: PDF, JPG o PNG hasta 10 MiB). |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Consulta los metadatos de un adjunto específico. |
| `PUT` / `PATCH` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Reemplaza el archivo físico y actualiza sus metadatos. |
| `DELETE` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Elimina el archivo físico del volumen `pqr_media` y su registro en BD. |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/descargar/` | `pqr.radicar` | Descarga autenticada del archivo adjunto (`FileResponse`). |

---

## 6. Seguridad y almacenamiento de adjuntos

- Los archivos se almacenan en `MEDIA_ROOT` (`/app/media` montado en el volumen persistente `pqr_media` de Docker) y nunca se exponen mediante URL pública estática.
- El validador comprueba tanto la extensión (`.pdf`, `.jpg`, `.jpeg`, `.png`) como la firma binaria real del archivo (`%PDF-`, `\xff\xd8\xff`, `\x89PNG\r\n\x1a\n`) y el límite de 10 MiB.
- El nombre del archivo se sanea antes de guardarse en una ruta con UUID único por solicitud (`pqr/<pqr_id>/<uuid>_<nombre>`).

---

## 7. Ejecución de pruebas

```powershell
# Backend (Pytest en Docker)
docker compose exec -T backend pytest apps/pqrs/tests/test_registro_pqr.py -v

# Frontend (Flutter test)
cd frontend
flutter test test/pqr_model_test.dart test/pqr_form_test.dart test/pqr_adjuntos_dialog_test.dart
```
