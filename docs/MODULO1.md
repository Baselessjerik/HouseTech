# Módulo 1: Usuarios, Perfiles, Control de Acceso (RBAC), Inmuebles, Parametrización y Auditoría

Este documento detalla la arquitectura y funcionamiento de punta a punta del **Módulo 1** de HouseTech.

---

## 1. Alcance Funcional

1. **Autenticación y Seguridad de Sesión**:
   - Inicio de sesión por nombre de usuario o correo electrónico (`/api/v1/auth/login/`), renovación de tokens JWT (`/api/v1/auth/refresh/`) y cierre de sesión con revocación en lista negra (`/api/v1/auth/logout/`).
   - Autorregistro de residentes (`/api/v1/auth/registro/`) asignando automáticamente el rol `RESIDENTE`.
   - Recuperación de contraseña mediante código de 6 dígitos enviado por correo (`/api/v1/auth/recuperar-password/solicitar/`, `validar-codigo/`, `confirmar/`).
2. **Mi Perfil y Foto de Perfil (`mi_perfil_page.dart`)**:
   - Visualización ordenada en 2 columnas de los datos de identificación (fijos por trazabilidad: nombres, apellidos, documento y `@username`) y datos de contacto.
   - Carga, actualización y eliminación de **foto de perfil** (`PNG`, `JPG`, `WEBP`, `GIF`, hasta 3 MB) en formato data URI base64 validado en el backend (`guardar_foto_perfil` / `obtener_foto_perfil`).
   - Edición de correo electrónico y teléfono mediante modal dedicado (`PATCH /api/v1/auth/me/`), y cambio de contraseña (`POST /api/v1/auth/cambiar-password/`).
3. **Administración de Usuarios (`usuarios_admin_page.dart`)**:
   - Listado en grilla de 2 columnas con búsqueda por nombre, usuario, documento o correo, y filtros por estado (`Activo`/`Inactivo`) y rol.
   - Creación de cuentas administrativas o de residentes, edición de datos, activación/desactivación sin borrado físico (conservando integridad histórica) y asignación de roles.
4. **Roles y Permisos RBAC (`roles_permisos_page.dart`)**:
   - Consulta de roles del sistema (`ADMIN`, `RESIDENTE`, `RESPONSABLE_PQR`) y matriz interactiva de permisos agrupados por módulo (`PUT /api/v1/roles/{id}/permisos/`).
5. **Gestión y Consulta de Inmuebles (`inmuebles_page.dart`)**:
   - **Modo Residente (`inmuebles.consultar`)**: Consulta de las viviendas vinculadas a la cuenta del residente.
   - **Modo Administrador (`inmuebles.gestionar`)**: Registro y edición de casas, apartamentos y locales con generación automática de código interno en el backend, activación/desactivación y vinculación/desvinculación de residentes (`PROPIETARIO`, `ARRENDATARIO`, `RESIDENTE`).
6. **Parametrización de Conjuntos Residenciales (`parametrizacion_page.dart`)**:
   - Creación y actualización de conjuntos residenciales (`Copropiedad`: nombre, NIT, dirección, ciudad, teléfono, correo y descripción).
7. **Bitácora de Auditoría (`auditoria_page.dart`)**:
   - Tabla de auditoría estilo Back-Office con columnas `Fecha y Hora (UTC)`, `Usuario / Actor`, `Acción` (`CREATE`, `UPDATE`, `DELETE`), `Módulo / Entidad`, `ID Afectado` y `Resumen del Cambio / Detalle` (con visor de JSON anterior vs. nuevo), filtrable por usuario, acción, entidad y fecha.
8. **Reportes y Estadísticas Operativas (`reportes_page.dart`)**:
   - KPIs consolidados, **gráfico de barras verticales** de reservas y horas por zona común, **gráfico de anillo (Donut Chart)** de proporción de uso vs. zonas sin reservas, reporte de lugares que no se reservan (`0` reservas) y desglose con barras de progreso horizontales.

---

## 2. Endpoints del Módulo 1 (`/api/v1/`)

| Recurso | Métodos | Permiso requerido | Descripción |
| :--- | :--- | :--- | :--- |
| `auth/login/`, `refresh/`, `logout/` | `POST` | Público / Autenticado | Emisión, renovación y revocación de tokens JWT |
| `auth/registro/` | `POST` | Público | Autorregistro de residente |
| `auth/me/` | `GET`, `PATCH` | Autenticado | Consulta de perfil, actualización de contacto y foto de perfil |
| `auth/cambiar-password/` | `POST` | Autenticado | Cambio de contraseña con validación de clave actual |
| `auth/recuperar-password/*` | `POST` | Público (con throttling) | Solicitud, validación y restablecimiento de clave con código de 6 dígitos |
| `usuarios/` | `GET`, `POST`, `PATCH`, `POST {id}/activar\|desactivar/`, `PUT {id}/roles/` | `usuarios.gestionar` / `roles.gestionar` | Gestión integral del ciclo de vida de usuarios y sus roles |
| `roles/` y `permisos/` | `GET`, `PUT roles/{id}/permisos/` | `roles.gestionar` | Catálogo de roles, permisos y actualización de matriz RBAC |
| `inmuebles/` | `GET`, `POST`, `PATCH`, `POST {id}/activar\|desactivar\|vincular\|desvincular/` | `inmuebles.consultar` / `inmuebles.gestionar` | Gestión de unidades residenciales y vínculo con usuarios |
| `copropiedades/` | `GET`, `POST`, `PATCH` | Autenticado / `configuracion.gestionar` | Registro y parametrización de conjuntos residenciales |
| `auditoria/` | `GET` (`?search=`, `?operacion=`, `?tabla=`) | `auditoria.ver` | Bitácora de seguridad generada por triggers PostgreSQL |
