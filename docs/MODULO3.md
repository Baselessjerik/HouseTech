# Módulo 3 — Gestión de Amenidades, Reservas, Reglas Operativas y Automatización

Este documento describe la arquitectura, modelos, reglas de negocio en base de datos, endpoints de API REST, automatización (`scheduler`) e interfaz de usuario (Flutter) correspondientes al **Módulo 3** del proyecto **HouseTech**.

---

## 1. Alcance Funcional

El Módulo 3 gestiona el ciclo completo de uso de las zonas comunes (amenidades) de la copropiedad:

1. **Catálogo de Amenidades (`amenidades.gestionar` / residentes autenticados):**
   - Creación, edición, activación y desactivación (con motivo e historial en `amenidades_estado_historial`) de zonas comunes.
   - Configuración de reglas operativas por amenidad (`ReglaReserva`): duración mínima/máxima en minutos, anticipación máxima en días, máximo de reservas activas por usuario, cancelación mínima en horas, tiempo límite de confirmación administrativa (`horas_limite_confirmacion`) y ventana de recordatorio previo (`horas_recordatorio`).
   - Configuración de franjas horarias por día de la semana (`AmenidadHorario`, `0 = Lunes` … `6 = Domingo`), con validación de no solapamiento.
   - Consulta de disponibilidad diaria detallada (`GET /api/v1/amenidades/{id}/disponibilidad/?fecha=YYYY-MM-DD`) con horarios de atención, franjas ocupadas y ventanas libres calculadas.
   - Reportes de ocupación e histórico de reservas (`GET /api/v1/reportes/ocupacion/` y `GET /api/v1/reportes/reservas/`).

2. **Reservas de Zonas Comunes (`reservas.solicitar` / `amenidades.gestionar`):**
   - Solicitud de reserva (`POST /api/v1/reservas/`) validando simultáneamente en capa de servicio Django y mediante trigger PostgreSQL (`trg_reservas_validar` / `fn_validar_reserva`):
     - Estado activo de la amenidad y del usuario.
     - Capacidad máxima (`num_personas <= capacidad`).
     - Reglas de la amenidad (`duracion_min_minutos`, `duracion_max_minutos`, `anticipacion_min_horas`, `anticipacion_max_dias`, `max_reservas_mes_inmueble`).
     - Horario permitido en el día de la semana correspondiente (`amenidades_horarios`, `1 = Lunes` … `7 = Domingo`).
     - Ausencia de traslapes con otras reservas activas (`SOLICITADA` / `CONFIRMADA`) y bloqueos operativos activos (`bloqueos_amenidad`).
   - Confirmación (`POST /api/v1/reservas/{id}/confirmar/`) o rechazo con motivo (`POST /api/v1/reservas/{id}/rechazar/`) por parte del administrador, o confirmación inmediata si `requiere_confirmacion = False`.
   - Cancelación (`POST /api/v1/reservas/{id}/cancelar/`) por el residente titular (respetando `horas_limite_cancelacion`) o por la administración en cualquier momento antes de finalizar.
   - Trazabilidad automática en `reservas_historial` mediante trigger SQL (`trg_reservas_historial` / `fn_reservas_historial`) y consulta en `GET /api/v1/reservas/{id}/historial/`.
   - Consulta de agenda unificada de reservas y bloqueos (`GET /api/v1/agenda/`).

3. **Automatización de Ciclo de Vida y Recordatorios (`procesar_reservas`):**
   - Comando `python manage.py procesar_reservas`, endpoint administrativo (`POST /api/v1/reservas/procesar/`) y contenedor dedicado `scheduler` en `docker-compose.yml` (ejecución automática cada 5 minutos):
     - **Finalizar cumplidas:** pasa a `FINALIZADA` las reservas `CONFIRMADA` cuya `fecha_fin` ya transcurrió.
     - **Expirar pendientes:** pasa a `EXPIRADA` las reservas `SOLICITADA` que ya superaron su hora de inicio o el plazo `horas_limite_confirmacion` sin respuesta administrativa.
     - **Alertar pendientes por vencer:** notifica a los administradores cuando una solicitud `SOLICITADA` está próxima a expirar.
     - **Enviar recordatorios:** envía notificación interna y correo (vía `apps.core.notificaciones.notificar`) a los residentes cuya reserva `CONFIRMADA` inicia dentro de la ventana `horas_recordatorio`.

---

## 2. Estructura de Archivos Integrados

### Backend (`backend/apps/reservas/` y `backend/apps/core/`)
- `backend/apps/reservas/models.py`: Modelos `Amenidad`, `ReglaReserva`, `AmenidadHorario`, `AmenidadEstadoHistorial`, `BloqueoAmenidad`, `MantenimientoAmenidad`, `Reserva` y `ReservaHistorial` (`managed = False`).
- `backend/apps/reservas/services.py`: Lógica transaccional (`select_for_update`), validación de reglas y horarios, creación/confirmación/rechazo/cancelación de reservas, cálculo de ventanas libres por fecha (`disponibilidad_dia`), creación de bloqueos con cancelación automática de reservas (`crear_bloqueo`) y motor de automatización (`procesar_reservas_automatico`).
- `backend/apps/reservas/serializers.py`: Serializadores de lectura/escritura para amenidades, reglas, horarios, disponibilidad diaria, reservas, historial y acciones de estado.
- `backend/apps/reservas/views.py`: `AmenidadViewSet` y `ReservaViewSet`.
- `backend/apps/reservas/urls.py`: Registro de rutas `/api/v1/amenidades/` y `/api/v1/reservas/`.
- `backend/apps/reservas/management/commands/procesar_reservas.py`: Comando CLI para el procesamiento automático de reservas.
- `backend/apps/reservas/migrations/0001_initial.py` y `0002_automatizacion.py`: Migraciones que aplican `sql/reservas_v2.sql` y `sql/reservas_v3.sql` (índices, triggers `trg_reservas_validar`, función `fn_amenidad_libre`, columnas de automatización y estado `EXPIRADA`).
- `backend/apps/core/notificaciones.py`: Servicio transversal `notificar()` con persistencia en `notificaciones` y despacho de correo en `transaction.on_commit`.
- `backend/apps/core/permissions.py`: Helpers `requiere_permisos` y `requiere_algun_permiso`.

### Armonización entre Módulo 2 (`apps.comunicados`) y Módulo 3 (`apps.reservas`)
- **`/api/v1/amenidades/{id}/disponibilidad/`**:
  - Si recibe `?fecha=YYYY-MM-DD`, delega en `apps.reservas.services.disponibilidad_dia` y devuelve horarios del día, reservas, bloqueos, mantenimientos y ventanas libres.
  - Si no recibe `fecha` (o recibe `?momento=`), devuelve el resumen instantáneo de disponibilidad del Módulo 2.
- **`/api/v1/bloqueos/`**:
  - Unificado en `BloqueoViewSet`, aceptando tanto el flujo de confirmación de conflictos del Módulo 2 (`confirmar_conflicto_reservas`) como el parámetro `cancelar_reservas` del Módulo 3 (que delega en `crear_bloqueo` y retorna `reservas_canceladas`).
- **`/api/v1/notificaciones/`**:
  - Soporta tanto `GET /api/v1/notificaciones/no-leidas/conteo/` como `GET /api/v1/notificaciones/resumen/` (`no_leidas`, `total`, `recientes`).

### Frontend (`frontend/lib/features/reservas/`)
- `models/reservas_models.dart`: Modelos tipados (`AmenidadModel`, `ReglaReservaModel`, `HorarioAmenidadModel`, `VentanaTiempoModel`, `DisponibilidadDiaModel`, `OcupacionAmenidadModel`, `ReservaModel`, `ReservaHistorialModel`).
- `services/reservas_service.dart`: Cliente HTTP autenticado para todos los endpoints de amenidades y reservas.
- `pages/reservas_residente_page.dart`: Pantalla **Solicitar reserva** (`reservas.solicitar`) con catálogo de zonas comunes, consulta de disponibilidad por fecha, diálogo de solicitud de reserva, listado filtrable de reservas, cancelación e historial de estados.
- `pages/amenidades_admin_page.dart`: Pantalla **Amenidades** (`amenidades.gestionar`) con tres pestañas:
  1. *Zonas comunes*: creación/edición de amenidades, reglas operativas, horarios semanales y activación/desactivación con motivo.
  2. *Solicitudes y reservas*: bandeja administrativa para confirmar, rechazar, cancelar, ver trazabilidad y ejecutar el procesamiento de vencidas.
  3. *Ocupación*: indicadores de reservas confirmadas, pendientes, canceladas y horas reservadas por amenidad.
- `reservas_menu.dart`: Integración con `AppShell` según los permisos efectivos del usuario.

---

## 3. Endpoints principales del Módulo 3 (`/api/v1/`)

| Recurso | Método | Permiso requerido | Descripción |
|---|---|---|---|
| `amenidades/` | `GET` | Autenticado | Lista amenidades con sus reglas y horarios (`?activa=true`) |
| `amenidades/` | `POST` | `amenidades.gestionar` | Crea una amenidad junto con sus reglas y horarios semanales |
| `amenidades/{id}/` | `GET`, `PATCH`, `DELETE` | Autenticado / `amenidades.gestionar` | Consulta, actualiza o elimina (o desactiva si tiene historial) una amenidad |
| `amenidades/{id}/activar/` | `POST` | `amenidades.gestionar` | Reactiva una amenidad registrando trazabilidad |
| `amenidades/{id}/desactivar/` | `POST` | `amenidades.gestionar` | Desactiva una amenidad registrando el cambio de estado |
| `amenidades/{id}/disponibilidad/?fecha=YYYY-MM-DD` | `GET` | Autenticado | Horarios del día, franjas ocupadas y ventanas libres calculadas |
| `reservas/` | `GET`, `POST` | `reservas.solicitar` / `amenidades.gestionar` | Lista reservas (propias para residente, todas para admin) o crea una nueva solicitud |
| `reservas/{id}/confirmar/` | `POST` | `amenidades.gestionar` | Aprueba una reserva en estado `SOLICITADA` |
| `reservas/{id}/rechazar/` | `POST` | `amenidades.gestionar` | Rechaza una reserva en estado `SOLICITADA` registrando el motivo |
| `reservas/{id}/cancelar/` | `POST` | `reservas.solicitar` / `amenidades.gestionar` | Cancela una reserva activa con motivo |
| `reservas/{id}/historial/` | `GET` | Autenticado (titular o gestor) | Historial de transiciones de estado de la reserva |
| `reservas/procesar/` | `POST` | `amenidades.gestionar` | Ejecuta el motor de completado, expiración y recordatorios bajo demanda |
| `agenda/` | `GET` | Autenticado | Agenda unificada de reservas y bloqueos en un rango de fechas |
| `reportes/ocupacion/` y `reportes/reservas/` | `GET` | `reportes.ver` / `amenidades.gestionar` | Estadísticas de ocupación, horas reservadas e histórico consolidado |

---

## 4. Verificación y Pruebas

Ejecutar las pruebas del Módulo 3 en el backend:

```powershell
docker compose exec -T backend pytest apps/reservas -v
```

Ejecutar las pruebas de widget y modelos del Módulo 3 en el frontend:

```powershell
cd frontend
flutter test test/reservas_test.dart
```

