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
    ├── test_registro_pqr.py     # Suite principal Pytest del módulo PQR
    └── test_paquete_b.py        # Pruebas de regresión (inmutabilidad, permisos y motivo)

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

La visibilidad y las acciones sobre cada PQR se evalúan según los **permisos efectivos** del usuario (compatible tanto con los roles base como con roles personalizados creados desde el Módulo 1):

| Rol base | Permisos PQR relevantes | Visibilidad y alcance |
|---|---|---|
| Administrador (`ADMIN`) | `usuarios.gestionar`, `pqr.gestionar`, `pqr.radicar` | Ve todas las PQR, asigna responsables, cambia estados, responde y gestiona adjuntos (salvo en estados finales). |
| Responsable de PQR (`RESPONSABLE_PQR`) | `pqr.gestionar`, `pqr.radicar` | Ve las PQR que tiene **asignadas** y las que **él mismo radicó**. Sobre una PQR propia que no le esté asignada se rige por las reglas de solicitante (no puede auto-escalar prioridad ni editar tras `RECIBIDA`). |
| Residente (`RESIDENTE`) | `pqr.radicar` | Ve y radica únicamente sus propias PQR; edita o modifica adjuntos solo mientras esté en estado `RECIBIDA`, y puede anular en `RECIBIDA` o `EN_REVISION` con motivo. |

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

Las transiciones son validadas en backend (`TRANSICIONES_ESTADO_PQR`) y registradas automáticamente en `pqr_historial` mediante el trigger `trg_pqr_hist`:

1. `RECIBIDA` *(estado inicial al radicar; único estado en el que el solicitante puede editar su solicitud o modificar adjuntos)*
2. `EN_REVISION` *(transición desde `RECIBIDA`)*
3. `EN_PROCESO` *(transición desde `EN_REVISION` o automáticamente al asignar responsable)*
4. `ATENDIDA` *(transición desde `EN_PROCESO` o al registrar respuesta de atención sin solución final)*
5. `CERRADA` *(estado final inmutable; registra `fecha_cierre`)*
6. `ANULADA` *(estado final inmutable; exige motivo en texto plano de mínimo 5 caracteres. Las PQR **no tienen `DELETE` físico**, responden `405`)*

En estados finales (`CERRADA` y `ANULADA`), el backend bloquea con `400` cualquier edición, respuesta, reasignación de responsable y carga/reemplazo/eliminación de adjuntos.

---

## 5. Endpoints REST (`/api/v1/`)

| Método | Ruta | Permiso | Descripción |
|---|---|---|---|
| `GET` | `/api/v1/pqrs/tipos/` | `pqr.radicar` | Lista los tipos activos del catálogo (`PETICION`, `QUEJA`, `RECLAMO`). |
| `GET` | `/api/v1/pqrs/mis-inmuebles/` | `pqr.radicar` | Lista los inmuebles activos vinculados al usuario autenticado (o todos los activos si gestiona PQR). |
| `GET` | `/api/v1/pqrs/` | `pqr.radicar` | Lista las PQR visibles según permisos efectivos (`usuarios.gestionar`, `pqr.gestionar`, `pqr.radicar`). |
| `POST` | `/api/v1/pqrs/` | `pqr.radicar` | Radica una nueva PQR en estado inicial `RECIBIDA` (rechaza inmuebles inactivos). |
| `GET` | `/api/v1/pqrs/<id>/` | `pqr.radicar` | Consulta el detalle de una PQR autorizada. |
| `PUT` / `PATCH` | `/api/v1/pqrs/<id>/` | `pqr.radicar` | Actualiza asunto, descripción, prioridad o inmueble (bloqueado en `CERRADA`/`ANULADA`; solicitantes solo en `RECIBIDA`). |
| `PATCH` | `/api/v1/pqrs/<id>/estado/` | `pqr.radicar` | Avanza el estado (admin o responsable asignado) o anula con `motivo` (`str` ≥ 5 caracteres). |
| `PATCH` | `/api/v1/pqrs/<id>/responsable/` | `usuarios.gestionar` | Asigna o reasigna un responsable PQR activo (bloqueado en `CERRADA`/`ANULADA`). |
| `GET` / `POST` | `/api/v1/pqrs/<id>/respuestas/` | `pqr.radicar` | Lista o registra respuestas de atención/solución o seguimiento del solicitante. |
| `GET` | `/api/v1/pqrs/<id>/historial/` | `pqr.radicar` | Consulta la línea de tiempo cronológica de eventos de la PQR. |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` | Lista los metadatos de los archivos adjuntos de la PQR. |
| `POST` | `/api/v1/pqrs/<id>/adjuntos/` | `pqr.radicar` | Sube un adjunto (`multipart/form-data`, campo `archivo`: PDF, JPG o PNG hasta 10 MiB; bloqueado en `CERRADA`/`ANULADA`). |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Consulta los metadatos de un adjunto específico. |
| `PUT` / `PATCH` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Reemplaza el archivo físico y actualiza sus metadatos (bloqueado en `CERRADA`/`ANULADA`). |
| `DELETE` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/` | `pqr.radicar` | Elimina el archivo y su metadato registrando el evento en historial (bloqueado en `CERRADA`/`ANULADA`). |
| `GET` | `/api/v1/pqrs/<id>/adjuntos/<adjunto_id>/descargar/` | `pqr.radicar` | Descarga autenticada del archivo adjunto (`FileResponse`). |

---

## 6. Seguridad y almacenamiento de adjuntos

- Los archivos se almacenan en `MEDIA_ROOT` (`/app/media` montado en el volumen persistente `pqr_media` de Docker) y nunca se exponen mediante URL pública estática.
- El validador comprueba tanto la extensión (`.pdf`, `.jpg`, `.jpeg`, `.png`) como la firma binaria real del archivo (`%PDF-`, `\xff\xd8\xff`, `\x89PNG\r\n\x1a\n`) y el límite de 10 MiB.
- El nombre del archivo se sanea antes de guardarse en una ruta con UUID único por solicitud (`pqrs/<pqr_id>/<uuid><ext>`).

---

## 7. Ejecución de pruebas

```powershell
# Backend (Pytest en Docker)
docker compose exec -T backend pytest apps/pqrs -v

# Frontend (Flutter test)
cd frontend
flutter test test/pqr_model_test.dart test/pqr_form_test.dart test/pqr_adjuntos_dialog_test.dart test/pqr_detail_modal_test.dart
```
