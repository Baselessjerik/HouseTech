-- =====================================================================
--  BASE DE DATOS: Sistema de gestión de copropiedades
--  Motor: PostgreSQL 14+
--  Módulos: 1) Administración y Perfiles   2) Comunicados y Avisos
--           3) Amenidades y Reservas       4) PQR
--
--  Uso:
--    createdb copropiedad_db
--    psql -d copropiedad_db -f copropiedad_db.sql
--
--  Auditoría: la API (Django) debe ejecutar al inicio de cada petición
--    SET LOCAL app.usuario_id = '<id_usuario>';
--  para que los triggers registren quién hizo cada operación.
-- =====================================================================

BEGIN;

  -- =====================================================================
  -- 1. MÓDULO ADMINISTRACIÓN Y PERFILES
  -- =====================================================================
  
  CREATE TABLE copropiedad (
      id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      nombre       VARCHAR(150) NOT NULL,
      nit          VARCHAR(30)  UNIQUE,
      direccion    VARCHAR(200),
      ciudad       VARCHAR(100),
      telefono     VARCHAR(30),
      email        VARCHAR(150),
      descripcion  TEXT,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  
  CREATE TABLE roles (
      id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      codigo       VARCHAR(40)  NOT NULL UNIQUE,
      nombre       VARCHAR(80)  NOT NULL,
      descripcion  TEXT,
      activo       BOOLEAN NOT NULL DEFAULT TRUE,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  
  CREATE TABLE permisos (
      id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      codigo       VARCHAR(80)  NOT NULL UNIQUE,   -- ej: pqr.gestionar
      modulo       VARCHAR(40)  NOT NULL,
      descripcion  VARCHAR(200) NOT NULL
  );
  
  CREATE TABLE roles_permisos (
      rol_id      BIGINT NOT NULL REFERENCES roles(id)    ON DELETE CASCADE,
      permiso_id  BIGINT NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
      PRIMARY KEY (rol_id, permiso_id)
  );
  
  CREATE TABLE usuarios (
      id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      tipo_documento    VARCHAR(5)  NOT NULL DEFAULT 'CC'
                        CHECK (tipo_documento IN ('CC','CE','TI','PP','NIT')),
      numero_documento  VARCHAR(30) NOT NULL,
      nombres           VARCHAR(100) NOT NULL,
      apellidos         VARCHAR(100) NOT NULL,
      username          VARCHAR(60)  NOT NULL,
      email             VARCHAR(150) NOT NULL,
      password_hash     VARCHAR(255) NOT NULL,
      telefono          VARCHAR(30),
      activo            BOOLEAN NOT NULL DEFAULT TRUE,   -- RF8: activar/desactivar sin borrar historial
      ultimo_login      TIMESTAMPTZ,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (tipo_documento, numero_documento)
  );
  CREATE UNIQUE INDEX ux_usuarios_username ON usuarios (lower(username));
  CREATE UNIQUE INDEX ux_usuarios_email    ON usuarios (lower(email));
  CREATE INDEX ix_usuarios_nombre          ON usuarios (lower(apellidos), lower(nombres));
  CREATE INDEX ix_usuarios_activo          ON usuarios (activo);
  
  CREATE TABLE usuarios_roles (
      usuario_id   BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      rol_id       BIGINT NOT NULL REFERENCES roles(id)    ON DELETE RESTRICT,
      asignado_por BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      asignado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (usuario_id, rol_id)
  );
  
  -- RF4: recuperación de contraseña
  CREATE TABLE recuperacion_password (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      usuario_id  BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      token_hash  VARCHAR(255) NOT NULL UNIQUE,
      expira_en   TIMESTAMPTZ NOT NULL,
      usado_en    TIMESTAMPTZ,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_recpwd_usuario ON recuperacion_password (usuario_id);
  
  -- RF3: cierre de sesión seguro (blacklist de JWT)
  CREATE TABLE tokens_revocados (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      jti         VARCHAR(100) NOT NULL UNIQUE,
      usuario_id  BIGINT REFERENCES usuarios(id) ON DELETE CASCADE,
      expira_en   TIMESTAMPTZ NOT NULL,
      revocado_en TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_tokens_expira ON tokens_revocados (expira_en);
  
  -- Tokens de dispositivos para notificaciones push (Flutter / FCM)
  CREATE TABLE dispositivos (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      usuario_id  BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      token_push  VARCHAR(255) NOT NULL UNIQUE,
      plataforma  VARCHAR(10) NOT NULL CHECK (plataforma IN ('ANDROID','IOS','WEB')),
      activo      BOOLEAN NOT NULL DEFAULT TRUE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_dispositivos_usuario ON dispositivos (usuario_id);
  
  -- RF10-RF12, RF16: inmuebles
  CREATE TABLE inmuebles (
      id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      copropiedad_id   BIGINT NOT NULL REFERENCES copropiedad(id) ON DELETE RESTRICT,
      tipo             VARCHAR(15) NOT NULL DEFAULT 'APARTAMENTO'
                       CHECK (tipo IN ('APARTAMENTO','CASA','LOCAL','PARQUEADERO','OTRO')),
      torre_bloque     VARCHAR(30),
      piso             SMALLINT,
      numero           VARCHAR(20) NOT NULL,          -- número de apto o casa
      codigo_interno   VARCHAR(40) NOT NULL UNIQUE,   -- identificación interna
      area_m2          NUMERIC(8,2) CHECK (area_m2 IS NULL OR area_m2 > 0),
      activo           BOOLEAN NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE UNIQUE INDEX ux_inmuebles_ubicacion
      ON inmuebles (copropiedad_id, COALESCE(torre_bloque,''), numero);
  
  -- RF13-RF15: relación usuario - inmueble
  CREATE TABLE inmueble_usuario (
      id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      inmueble_id    BIGINT NOT NULL REFERENCES inmuebles(id) ON DELETE CASCADE,
      usuario_id     BIGINT NOT NULL REFERENCES usuarios(id)  ON DELETE CASCADE,
      tipo_relacion  VARCHAR(15) NOT NULL
                     CHECK (tipo_relacion IN ('PROPIETARIO','ARRENDATARIO','RESIDENTE')),
      fecha_inicio   DATE NOT NULL DEFAULT CURRENT_DATE,
      fecha_fin      DATE,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
  );
  CREATE UNIQUE INDEX ux_inmueble_usuario_vigente
      ON inmueble_usuario (inmueble_id, usuario_id, tipo_relacion) WHERE fecha_fin IS NULL;
  CREATE INDEX ix_inmueble_usuario_usuario ON inmueble_usuario (usuario_id);
  
  -- RF19: estados configurables por proceso (PQR, reservas, mantenimientos)
  CREATE TABLE estados (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      proceso     VARCHAR(20) NOT NULL CHECK (proceso IN ('PQR','RESERVA','MANTENIMIENTO')),
      codigo      VARCHAR(30) NOT NULL,
      nombre      VARCHAR(60) NOT NULL,
      orden       SMALLINT NOT NULL DEFAULT 0,
      es_inicial  BOOLEAN NOT NULL DEFAULT FALSE,
      es_final    BOOLEAN NOT NULL DEFAULT FALSE,   -- un estado final libera cupo / cierra el caso
      activo      BOOLEAN NOT NULL DEFAULT TRUE,
      UNIQUE (proceso, codigo),
      UNIQUE (id, proceso)                          -- permite FK compuesta que impide mezclar procesos
  );
  
  -- RF28-RF31: auditoría y trazabilidad
  CREATE TABLE auditoria (
      id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      fecha             TIMESTAMPTZ NOT NULL DEFAULT now(),       -- RF28
      usuario_id        BIGINT REFERENCES usuarios(id) ON DELETE SET NULL, -- RF29
      tabla             VARCHAR(63) NOT NULL,
      registro_id       VARCHAR(40),
      operacion         VARCHAR(6) NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
      datos_anteriores  JSONB,                                    -- RF30
      datos_nuevos      JSONB
  );
  CREATE INDEX ix_auditoria_tabla_registro ON auditoria (tabla, registro_id);  -- RF31
  CREATE INDEX ix_auditoria_usuario        ON auditoria (usuario_id);
  CREATE INDEX ix_auditoria_fecha          ON auditoria (fecha DESC);
  
  -- =====================================================================
  -- 2. MÓDULO AMENIDADES Y RESERVAS
  -- =====================================================================
  
  CREATE TABLE amenidades (
      id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      copropiedad_id   BIGINT NOT NULL REFERENCES copropiedad(id) ON DELETE RESTRICT,
      nombre           VARCHAR(100) NOT NULL,      -- cancha, piscina, gimnasio, salón social...
      descripcion      TEXT,
      capacidad        INTEGER CHECK (capacidad IS NULL OR capacidad > 0),
      condiciones_uso  TEXT,
      activa           BOOLEAN NOT NULL DEFAULT TRUE,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (copropiedad_id, nombre)
  );
  
  -- RF18: horarios de funcionamiento (1 = lunes ... 7 = domingo)
  CREATE TABLE amenidad_horarios (
      id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      amenidad_id    BIGINT NOT NULL REFERENCES amenidades(id) ON DELETE CASCADE,
      dia_semana     SMALLINT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
      hora_apertura  TIME NOT NULL,
      hora_cierre    TIME NOT NULL,
      activo         BOOLEAN NOT NULL DEFAULT TRUE,
      CHECK (hora_cierre > hora_apertura),
      UNIQUE (amenidad_id, dia_semana, hora_apertura)
  );
  
  -- RF17: reglas de reserva por amenidad
  CREATE TABLE reglas_reserva (
      id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      amenidad_id                 BIGINT NOT NULL UNIQUE REFERENCES amenidades(id) ON DELETE CASCADE,
      duracion_min_minutos        INTEGER NOT NULL DEFAULT 30  CHECK (duracion_min_minutos > 0),
      duracion_max_minutos        INTEGER NOT NULL DEFAULT 240 CHECK (duracion_max_minutos > 0),
      anticipacion_min_horas      INTEGER NOT NULL DEFAULT 1   CHECK (anticipacion_min_horas >= 0),
      anticipacion_max_dias       INTEGER NOT NULL DEFAULT 30  CHECK (anticipacion_max_dias > 0),
      max_reservas_mes_inmueble   INTEGER CHECK (max_reservas_mes_inmueble IS NULL OR max_reservas_mes_inmueble > 0),
      horas_limite_cancelacion    INTEGER NOT NULL DEFAULT 24  CHECK (horas_limite_cancelacion >= 0),
      requiere_confirmacion       BOOLEAN NOT NULL DEFAULT TRUE,
      observaciones               TEXT,
      updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (duracion_max_minutos >= duracion_min_minutos)
  );
  
  CREATE TABLE reservas (
      id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      amenidad_id         BIGINT NOT NULL REFERENCES amenidades(id) ON DELETE RESTRICT,
      usuario_id          BIGINT NOT NULL REFERENCES usuarios(id)   ON DELETE RESTRICT,
      inmueble_id         BIGINT REFERENCES inmuebles(id)           ON DELETE RESTRICT,
      fecha_inicio        TIMESTAMPTZ NOT NULL,
      fecha_fin           TIMESTAMPTZ NOT NULL,
      num_personas        INTEGER CHECK (num_personas IS NULL OR num_personas > 0),
      estado_id           BIGINT NOT NULL,
      estado_proceso      VARCHAR(20) NOT NULL DEFAULT 'RESERVA' CHECK (estado_proceso = 'RESERVA'),
      observaciones       TEXT,
      confirmada_por      BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      confirmada_en       TIMESTAMPTZ,
      cancelada_por       BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      cancelada_en        TIMESTAMPTZ,
      motivo_cancelacion  TEXT,
      created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (fecha_fin > fecha_inicio),
      FOREIGN KEY (estado_id, estado_proceso) REFERENCES estados(id, proceso)
  );
  CREATE INDEX ix_reservas_amenidad_fecha ON reservas (amenidad_id, fecha_inicio, fecha_fin);
  CREATE INDEX ix_reservas_usuario        ON reservas (usuario_id, fecha_inicio DESC);
  CREATE INDEX ix_reservas_estado         ON reservas (estado_id);
  
  -- RF11: historial de reservas
  CREATE TABLE reservas_historial (
      id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      reserva_id          BIGINT NOT NULL REFERENCES reservas(id) ON DELETE CASCADE,
      estado_anterior_id  BIGINT REFERENCES estados(id),
      estado_nuevo_id     BIGINT NOT NULL REFERENCES estados(id),
      usuario_id          BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      detalle             TEXT,
      fecha               TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_reservas_hist_reserva ON reservas_historial (reserva_id, fecha);
  
  -- =====================================================================
  -- 3. MÓDULO COMUNICADOS Y AVISOS (mantenimientos y bloqueos incluidos)
  -- =====================================================================
  
  -- RF1: mantenimientos programados de zonas comunes
  CREATE TABLE mantenimientos (
      id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      amenidad_id     BIGINT REFERENCES amenidades(id) ON DELETE SET NULL,
      titulo          VARCHAR(150) NOT NULL,
      descripcion     TEXT,
      fecha_inicio    TIMESTAMPTZ NOT NULL,
      fecha_fin       TIMESTAMPTZ NOT NULL,
      estado_id       BIGINT NOT NULL,
      estado_proceso  VARCHAR(20) NOT NULL DEFAULT 'MANTENIMIENTO' CHECK (estado_proceso = 'MANTENIMIENTO'),
      responsable     VARCHAR(150),                      -- proveedor o encargado
      creado_por      BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (fecha_fin > fecha_inicio),
      FOREIGN KEY (estado_id, estado_proceso) REFERENCES estados(id, proceso)
  );
  CREATE INDEX ix_mantenimientos_amenidad ON mantenimientos (amenidad_id, fecha_inicio);
  
  -- RF2-RF5, RF7: bloqueos temporales de amenidades
  CREATE TABLE bloqueos_amenidad (
      id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      amenidad_id      BIGINT NOT NULL REFERENCES amenidades(id) ON DELETE CASCADE,
      mantenimiento_id BIGINT REFERENCES mantenimientos(id) ON DELETE SET NULL,
      fecha_inicio     TIMESTAMPTZ NOT NULL,
      fecha_fin        TIMESTAMPTZ NOT NULL,
      motivo           TEXT NOT NULL,
      cancelado        BOOLEAN NOT NULL DEFAULT FALSE,
      cancelado_en     TIMESTAMPTZ,
      creado_por       BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (fecha_fin > fecha_inicio)
  );
  CREATE INDEX ix_bloqueos_amenidad_fecha ON bloqueos_amenidad (amenidad_id, fecha_inicio, fecha_fin)
      WHERE NOT cancelado;
  
  CREATE TABLE categorias_comunicado (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      nombre      VARCHAR(80) NOT NULL UNIQUE,
      descripcion VARCHAR(200),
      color       VARCHAR(9),                       -- ej: #E53935, para etiquetas en Flutter
      activa      BOOLEAN NOT NULL DEFAULT TRUE
  );
  
  -- RF9-RF15: avisos y comunicados
  CREATE TABLE comunicados (
      id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      categoria_id       BIGINT REFERENCES categorias_comunicado(id) ON DELETE SET NULL,
      titulo             VARCHAR(200) NOT NULL,
      contenido          TEXT NOT NULL,
      autor_id           BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      estado             VARCHAR(12) NOT NULL DEFAULT 'BORRADOR'
                         CHECK (estado IN ('BORRADOR','PROGRAMADO','PUBLICADO','ARCHIVADO')),
      audiencia          VARCHAR(10) NOT NULL DEFAULT 'TODOS'
                         CHECK (audiencia IN ('TODOS','ROL','USUARIOS')),
      rol_destino_id     BIGINT REFERENCES roles(id) ON DELETE SET NULL,
      fecha_programada   TIMESTAMPTZ,
      fecha_publicacion  TIMESTAMPTZ,
      fecha_expiracion   TIMESTAMPTZ,
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      CHECK (estado <> 'PROGRAMADO' OR fecha_programada IS NOT NULL),
      CHECK (audiencia <> 'ROL' OR rol_destino_id IS NOT NULL)
  );
  CREATE INDEX ix_comunicados_estado_pub ON comunicados (estado, fecha_publicacion DESC);
  CREATE INDEX ix_comunicados_programados ON comunicados (fecha_programada) WHERE estado = 'PROGRAMADO';
  
  CREATE TABLE comunicado_destinatarios (
      comunicado_id BIGINT NOT NULL REFERENCES comunicados(id) ON DELETE CASCADE,
      usuario_id    BIGINT NOT NULL REFERENCES usuarios(id)    ON DELETE CASCADE,
      PRIMARY KEY (comunicado_id, usuario_id)
  );
  
  -- RF15: historial de versiones
  CREATE TABLE comunicados_historial (
      id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      comunicado_id       BIGINT NOT NULL REFERENCES comunicados(id) ON DELETE CASCADE,
      usuario_id          BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      estado_anterior     VARCHAR(12),
      titulo_anterior     VARCHAR(200),
      contenido_anterior  TEXT,
      fecha               TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_comunicados_hist ON comunicados_historial (comunicado_id, fecha);
  
  -- Notificaciones transversales (comunicados, bloqueos, reservas, PQR)
  CREATE TABLE notificaciones (
      id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      usuario_id       BIGINT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      tipo             VARCHAR(15) NOT NULL
                       CHECK (tipo IN ('COMUNICADO','MANTENIMIENTO','BLOQUEO','RESERVA','PQR','SISTEMA')),
      titulo           VARCHAR(200) NOT NULL,
      mensaje          TEXT NOT NULL,
      referencia_tipo  VARCHAR(40),
      referencia_id    BIGINT,
      canal            VARCHAR(6) NOT NULL DEFAULT 'PUSH' CHECK (canal IN ('PUSH','EMAIL','APP')),
      leida            BOOLEAN NOT NULL DEFAULT FALSE,
      leida_en         TIMESTAMPTZ,
      enviada_en       TIMESTAMPTZ,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_notif_usuario_pendientes ON notificaciones (usuario_id, created_at DESC) WHERE NOT leida;
  
  -- =====================================================================
  -- 4. MÓDULO PQR
  -- =====================================================================
  
  CREATE TABLE tipos_pqr (
      id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      codigo      VARCHAR(20) NOT NULL UNIQUE,
      nombre      VARCHAR(60) NOT NULL,
      prefijo     VARCHAR(5)  NOT NULL UNIQUE,      -- prefijo del radicado
      descripcion VARCHAR(200),
      sla_dias    SMALLINT CHECK (sla_dias IS NULL OR sla_dias > 0),
      activo      BOOLEAN NOT NULL DEFAULT TRUE
  );
  
  CREATE SEQUENCE seq_radicado_pqr START 1;
  
  CREATE TABLE pqr (
      id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      radicado          VARCHAR(30) UNIQUE,         -- RF2: se genera por trigger (ej. PET-2026-000001)
      tipo_id           BIGINT NOT NULL REFERENCES tipos_pqr(id) ON DELETE RESTRICT,
      solicitante_id    BIGINT NOT NULL REFERENCES usuarios(id)  ON DELETE RESTRICT,
      inmueble_id       BIGINT REFERENCES inmuebles(id) ON DELETE SET NULL,
      asunto            VARCHAR(200) NOT NULL,
      descripcion       TEXT NOT NULL,
      prioridad         VARCHAR(6) NOT NULL DEFAULT 'MEDIA' CHECK (prioridad IN ('BAJA','MEDIA','ALTA')),
      estado_id         BIGINT NOT NULL,
      estado_proceso    VARCHAR(20) NOT NULL DEFAULT 'PQR' CHECK (estado_proceso = 'PQR'),
      responsable_id    BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      fecha_radicacion  TIMESTAMPTZ NOT NULL DEFAULT now(),
      fecha_cierre      TIMESTAMPTZ,
      created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      FOREIGN KEY (estado_id, estado_proceso) REFERENCES estados(id, proceso)
  );
  CREATE INDEX ix_pqr_solicitante ON pqr (solicitante_id, fecha_radicacion DESC);
  CREATE INDEX ix_pqr_responsable ON pqr (responsable_id);
  CREATE INDEX ix_pqr_estado_tipo ON pqr (estado_id, tipo_id);
  CREATE INDEX ix_pqr_fecha       ON pqr (fecha_radicacion DESC);
  
  -- RF4: adjuntos y evidencias (el archivo vive en storage; aquí solo su referencia)
  CREATE TABLE pqr_adjuntos (
      id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      pqr_id          BIGINT NOT NULL REFERENCES pqr(id) ON DELETE CASCADE,
      nombre_archivo  VARCHAR(255) NOT NULL,
      ruta            VARCHAR(500) NOT NULL,
      tipo_mime       VARCHAR(100),
      tamano_bytes    BIGINT CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0),
      subido_por      BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_pqr_adjuntos_pqr ON pqr_adjuntos (pqr_id);
  
  -- RF8: respuestas / soluciones
  CREATE TABLE pqr_respuestas (
      id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      pqr_id          BIGINT NOT NULL REFERENCES pqr(id) ON DELETE CASCADE,
      responsable_id  BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      respuesta       TEXT NOT NULL,
      es_solucion     BOOLEAN NOT NULL DEFAULT FALSE,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_pqr_respuestas_pqr ON pqr_respuestas (pqr_id, created_at);
  
  -- RF9-RF10: trazabilidad
  CREATE TABLE pqr_historial (
      id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      pqr_id               BIGINT NOT NULL REFERENCES pqr(id) ON DELETE CASCADE,
      estado_anterior_id   BIGINT REFERENCES estados(id),
      estado_nuevo_id      BIGINT NOT NULL REFERENCES estados(id),
      responsable_id       BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
      usuario_id           BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,   -- quien hizo el cambio
      comentario           TEXT,
      fecha                TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX ix_pqr_historial_pqr ON pqr_historial (pqr_id, fecha);
  
  -- =====================================================================
  -- 5. FUNCIONES Y TRIGGERS
  -- =====================================================================
  
  -- updated_at automático
  CREATE FUNCTION fn_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
      NEW.updated_at := now();
      RETURN NEW;
  END $$;
  
  DO $$
  DECLARE r record;
  BEGIN
      FOR r IN
          SELECT c.table_name
          FROM information_schema.columns c
          JOIN information_schema.tables t
            ON t.table_schema = c.table_schema AND t.table_name = c.table_name
          WHERE c.table_schema = 'public' AND c.column_name = 'updated_at'
            AND t.table_type = 'BASE TABLE'
      LOOP
          EXECUTE format(
            'CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$I
             FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()', r.table_name);
      END LOOP;
  END $$;
  
  -- Auditoría genérica (RF28-RF30)
  CREATE FUNCTION fn_auditar() RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE
      v_old jsonb; v_new jsonb; v_id text; v_user bigint;
  BEGIN
      v_user := NULLIF(current_setting('app.usuario_id', true), '')::bigint;
      IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - 'password_hash'; END IF;
      IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - 'password_hash'; END IF;
      v_id := COALESCE(v_new->>'id', v_old->>'id');
      INSERT INTO auditoria (usuario_id, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
      VALUES (v_user, TG_TABLE_NAME, v_id, TG_OP, v_old, v_new);
      RETURN NULL;
  END $$;
  
  DO $$
  DECLARE t text;
  BEGIN
      FOREACH t IN ARRAY ARRAY[
          'copropiedad','roles','roles_permisos','usuarios','usuarios_roles','inmuebles','inmueble_usuario',
          'amenidades','amenidad_horarios','reglas_reserva','reservas','mantenimientos','bloqueos_amenidad',
          'comunicados','pqr','pqr_respuestas'
      ] LOOP
          EXECUTE format(
            'CREATE TRIGGER trg_%1$s_audit AFTER INSERT OR UPDATE OR DELETE ON %1$I
             FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
      END LOOP;
  END $$;
  
  -- Reservas: impide solapamientos entre reservas y contra bloqueos (RF5-RF6 reservas, RF5 bloqueos)
  CREATE FUNCTION fn_validar_reserva() RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE v_final boolean;
  BEGIN
      SELECT es_final INTO v_final FROM estados WHERE id = NEW.estado_id;
      IF v_final THEN
          RETURN NEW;           -- canceladas/finalizadas no ocupan la amenidad
      END IF;
  
      -- serializa reservas concurrentes sobre la misma amenidad
      PERFORM pg_advisory_xact_lock(hashtext('reserva_amenidad_' || NEW.amenidad_id::text));
  
      IF EXISTS (
          SELECT 1 FROM reservas r
          JOIN estados e ON e.id = r.estado_id
          WHERE r.amenidad_id = NEW.amenidad_id
            AND r.id IS DISTINCT FROM NEW.id
            AND NOT e.es_final
            AND tstzrange(r.fecha_inicio, r.fecha_fin, '[)') && tstzrange(NEW.fecha_inicio, NEW.fecha_fin, '[)')
      ) THEN
          RAISE EXCEPTION 'La amenidad ya tiene una reserva en ese horario'
              USING ERRCODE = '23P01';
      END IF;
  
      IF EXISTS (
          SELECT 1 FROM bloqueos_amenidad b
          WHERE b.amenidad_id = NEW.amenidad_id
            AND NOT b.cancelado
            AND tstzrange(b.fecha_inicio, b.fecha_fin, '[)') && tstzrange(NEW.fecha_inicio, NEW.fecha_fin, '[)')
      ) THEN
          RAISE EXCEPTION 'La amenidad se encuentra bloqueada en ese horario'
              USING ERRCODE = '23P01';
      END IF;
  
      RETURN NEW;
  END $$;
  
  CREATE TRIGGER trg_reservas_validar
      BEFORE INSERT OR UPDATE OF amenidad_id, fecha_inicio, fecha_fin, estado_id ON reservas
      FOR EACH ROW EXECUTE FUNCTION fn_validar_reserva();
  
  -- Historial de reservas (RF11)
  CREATE FUNCTION fn_reservas_historial() RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE v_user bigint := NULLIF(current_setting('app.usuario_id', true), '')::bigint;
  BEGIN
      IF TG_OP = 'INSERT' THEN
          INSERT INTO reservas_historial (reserva_id, estado_anterior_id, estado_nuevo_id, usuario_id, detalle)
          VALUES (NEW.id, NULL, NEW.estado_id, v_user, 'Reserva creada');
      ELSIF NEW.estado_id IS DISTINCT FROM OLD.estado_id THEN
          INSERT INTO reservas_historial (reserva_id, estado_anterior_id, estado_nuevo_id, usuario_id, detalle)
          VALUES (NEW.id, OLD.estado_id, NEW.estado_id, v_user, NEW.motivo_cancelacion);
      END IF;
      RETURN NULL;
  END $$;
  
  CREATE TRIGGER trg_reservas_hist
      AFTER INSERT OR UPDATE OF estado_id ON reservas
      FOR EACH ROW EXECUTE FUNCTION fn_reservas_historial();
  
  -- Historial de comunicados (RF15): guarda la versión previa al editar
  CREATE FUNCTION fn_comunicados_historial() RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
      IF NEW.titulo IS DISTINCT FROM OLD.titulo
         OR NEW.contenido IS DISTINCT FROM OLD.contenido
         OR NEW.estado IS DISTINCT FROM OLD.estado THEN
          INSERT INTO comunicados_historial
              (comunicado_id, usuario_id, estado_anterior, titulo_anterior, contenido_anterior)
          VALUES (OLD.id, NULLIF(current_setting('app.usuario_id', true), '')::bigint,
                  OLD.estado, OLD.titulo, OLD.contenido);
      END IF;
      RETURN NEW;
  END $$;
  
  CREATE TRIGGER trg_comunicados_hist
      BEFORE UPDATE ON comunicados
      FOR EACH ROW EXECUTE FUNCTION fn_comunicados_historial();
  
  -- PQR: radicado único y fecha de cierre (RF2)
  CREATE FUNCTION fn_pqr_before() RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE v_prefijo text; v_final boolean;
  BEGIN
      IF TG_OP = 'INSERT' AND NEW.radicado IS NULL THEN
          SELECT prefijo INTO v_prefijo FROM tipos_pqr WHERE id = NEW.tipo_id;
          NEW.radicado := v_prefijo || '-' || to_char(now(), 'YYYY') || '-' ||
                          lpad(nextval('seq_radicado_pqr')::text, 6, '0');
      END IF;
      SELECT es_final INTO v_final FROM estados WHERE id = NEW.estado_id;
      IF v_final AND NEW.fecha_cierre IS NULL THEN
          NEW.fecha_cierre := now();
      ELSIF NOT v_final THEN
          NEW.fecha_cierre := NULL;
      END IF;
      RETURN NEW;
  END $$;
  
  CREATE TRIGGER trg_pqr_before
      BEFORE INSERT OR UPDATE OF estado_id ON pqr
      FOR EACH ROW EXECUTE FUNCTION fn_pqr_before();
  
  -- PQR: trazabilidad de estados y asignaciones (RF10)
  CREATE FUNCTION fn_pqr_historial() RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE v_user bigint := NULLIF(current_setting('app.usuario_id', true), '')::bigint;
  BEGIN
      IF TG_OP = 'INSERT' THEN
          INSERT INTO pqr_historial (pqr_id, estado_anterior_id, estado_nuevo_id, responsable_id, usuario_id, comentario)
          VALUES (NEW.id, NULL, NEW.estado_id, NEW.responsable_id, v_user, 'PQR radicada');
      ELSIF NEW.estado_id IS DISTINCT FROM OLD.estado_id
         OR NEW.responsable_id IS DISTINCT FROM OLD.responsable_id THEN
          INSERT INTO pqr_historial (pqr_id, estado_anterior_id, estado_nuevo_id, responsable_id, usuario_id, comentario)
          VALUES (NEW.id, OLD.estado_id, NEW.estado_id, NEW.responsable_id, v_user,
                  CASE WHEN NEW.responsable_id IS DISTINCT FROM OLD.responsable_id
                       THEN 'Cambio de responsable' ELSE 'Cambio de estado' END);
      END IF;
      RETURN NULL;
  END $$;
  
  CREATE TRIGGER trg_pqr_hist
      AFTER INSERT OR UPDATE OF estado_id, responsable_id ON pqr
      FOR EACH ROW EXECUTE FUNCTION fn_pqr_historial();
  
  -- Estado de una amenidad en un momento dado (RF6 de comunicados)
  CREATE FUNCTION fn_estado_amenidad(p_amenidad bigint, p_momento timestamptz DEFAULT now())
  RETURNS text LANGUAGE sql STABLE AS $$
      SELECT CASE
          WHEN EXISTS (SELECT 1 FROM mantenimientos m JOIN estados e ON e.id = m.estado_id
                       WHERE m.amenidad_id = p_amenidad AND NOT e.es_final
                         AND p_momento >= m.fecha_inicio AND p_momento < m.fecha_fin)
              THEN 'EN_MANTENIMIENTO'
          WHEN EXISTS (SELECT 1 FROM bloqueos_amenidad b
                       WHERE b.amenidad_id = p_amenidad AND NOT b.cancelado
                         AND p_momento >= b.fecha_inicio AND p_momento < b.fecha_fin)
              THEN 'BLOQUEADA'
          WHEN EXISTS (SELECT 1 FROM reservas r JOIN estados e ON e.id = r.estado_id
                       WHERE r.amenidad_id = p_amenidad AND NOT e.es_final
                         AND p_momento >= r.fecha_inicio AND p_momento < r.fecha_fin)
              THEN 'RESERVADA'
          ELSE 'DISPONIBLE'
      END
  $$;
  
  -- =====================================================================
  -- 6. VISTAS PARA CONSULTAS Y REPORTES
  -- =====================================================================
  
  -- Agenda / calendario de reservas (RF12 reservas, RF22 admin)
  CREATE VIEW v_agenda_reservas AS
  SELECT r.id AS reserva_id, a.id AS amenidad_id, a.nombre AS amenidad,
         r.fecha_inicio, r.fecha_fin,
         u.id AS usuario_id, u.nombres || ' ' || u.apellidos AS residente,
         i.codigo_interno AS inmueble, e.codigo AS estado, e.nombre AS estado_nombre
  FROM reservas r
  JOIN amenidades a ON a.id = r.amenidad_id
  JOIN usuarios  u ON u.id = r.usuario_id
  JOIN estados   e ON e.id = r.estado_id
  LEFT JOIN inmuebles i ON i.id = r.inmueble_id;
  
  -- Detalle de PQR para reportes y filtros (RF21, RF11-RF12 PQR)
  CREATE VIEW v_pqr_detalle AS
  SELECT p.id, p.radicado, t.nombre AS tipo, p.asunto, p.prioridad,
         e.codigo AS estado, e.nombre AS estado_nombre,
         s.nombres || ' ' || s.apellidos AS solicitante,
         i.codigo_interno AS inmueble,
         rsp.nombres || ' ' || rsp.apellidos AS responsable,
         p.fecha_radicacion, p.fecha_cierre,
         EXTRACT(DAY FROM COALESCE(p.fecha_cierre, now()) - p.fecha_radicacion)::int AS dias_abierta
  FROM pqr p
  JOIN tipos_pqr t ON t.id = p.tipo_id
  JOIN estados   e ON e.id = p.estado_id
  JOIN usuarios  s ON s.id = p.solicitante_id
  LEFT JOIN usuarios  rsp ON rsp.id = p.responsable_id
  LEFT JOIN inmuebles i   ON i.id = p.inmueble_id;
  
  -- Inmuebles con sus personas asociadas (RF25 administración)
  CREATE VIEW v_inmuebles_personas AS
  SELECT i.id AS inmueble_id, i.codigo_interno, i.tipo, i.torre_bloque, i.numero,
         u.id AS usuario_id, u.nombres || ' ' || u.apellidos AS persona,
         iu.tipo_relacion, iu.fecha_inicio, iu.fecha_fin
  FROM inmuebles i
  LEFT JOIN inmueble_usuario iu ON iu.inmueble_id = i.id AND iu.fecha_fin IS NULL
  LEFT JOIN usuarios u ON u.id = iu.usuario_id;
  
  -- =====================================================================
  -- 7. DATOS INICIALES (SEMILLAS)
  -- =====================================================================
  
  INSERT INTO roles (codigo, nombre, descripcion) VALUES
   ('ADMIN',            'Administrador',       'Acceso total a la administración de la copropiedad'),
   ('RESIDENTE',        'Residente',           'Propietarios, arrendatarios y residentes'),
   ('RESPONSABLE_PQR',  'Responsable de PQR',  'Personal encargado de atender PQR');
  
  INSERT INTO permisos (codigo, modulo, descripcion) VALUES
   ('usuarios.gestionar',      'ADMINISTRACION', 'Crear, editar, activar y desactivar usuarios'),
   ('roles.gestionar',         'ADMINISTRACION', 'Asignar roles y consultar permisos'),
   ('inmuebles.gestionar',     'ADMINISTRACION', 'Registrar y modificar inmuebles y relaciones'),
   ('inmuebles.consultar',     'ADMINISTRACION', 'Consultar inmuebles'),
   ('configuracion.gestionar', 'ADMINISTRACION', 'Configurar copropiedad, reglas, horarios y estados'),
   ('reportes.ver',            'ADMINISTRACION', 'Consultar y exportar reportes'),
   ('auditoria.ver',           'ADMINISTRACION', 'Consultar historial de acciones'),
   ('comunicados.gestionar',   'COMUNICADOS',    'Crear, editar y publicar avisos y comunicados'),
   ('comunicados.ver',         'COMUNICADOS',    'Consultar avisos publicados'),
   ('bloqueos.gestionar',      'COMUNICADOS',    'Programar mantenimientos y bloqueos'),
   ('amenidades.gestionar',    'RESERVAS',       'Administrar zonas comunes y reservas de terceros'),
   ('reservas.solicitar',      'RESERVAS',       'Solicitar, consultar y cancelar reservas propias'),
   ('pqr.radicar',             'PQR',            'Radicar y consultar PQR propias'),
   ('pqr.gestionar',           'PQR',            'Asignar, responder y cambiar estado de PQR');
  
  -- ADMIN: todos los permisos
  INSERT INTO roles_permisos (rol_id, permiso_id)
  SELECT (SELECT id FROM roles WHERE codigo = 'ADMIN'), id FROM permisos;
  
  INSERT INTO roles_permisos (rol_id, permiso_id)
  SELECT (SELECT id FROM roles WHERE codigo = 'RESIDENTE'), id FROM permisos
  WHERE codigo IN ('inmuebles.consultar','comunicados.ver','reservas.solicitar','pqr.radicar');
  
  INSERT INTO roles_permisos (rol_id, permiso_id)
  SELECT (SELECT id FROM roles WHERE codigo = 'RESPONSABLE_PQR'), id FROM permisos
  WHERE codigo IN ('pqr.gestionar','pqr.radicar','comunicados.ver','inmuebles.consultar');
  
  INSERT INTO estados (proceso, codigo, nombre, orden, es_inicial, es_final) VALUES
   ('PQR','RECIBIDA',    'Recibida',    1, TRUE,  FALSE),
   ('PQR','EN_REVISION', 'En revisión', 2, FALSE, FALSE),
   ('PQR','EN_PROCESO',  'En proceso',  3, FALSE, FALSE),
   ('PQR','ATENDIDA',    'Atendida',    4, FALSE, FALSE),
   ('PQR','CERRADA',     'Cerrada',     5, FALSE, TRUE),
   ('RESERVA','SOLICITADA',  'Solicitada',  1, TRUE,  FALSE),
   ('RESERVA','CONFIRMADA',  'Confirmada',  2, FALSE, FALSE),
   ('RESERVA','FINALIZADA',  'Finalizada',  3, FALSE, TRUE),
   ('RESERVA','RECHAZADA',   'Rechazada',   4, FALSE, TRUE),
   ('RESERVA','CANCELADA',   'Cancelada',   5, FALSE, TRUE),
   ('MANTENIMIENTO','PROGRAMADO', 'Programado', 1, TRUE,  FALSE),
   ('MANTENIMIENTO','EN_CURSO',   'En curso',   2, FALSE, FALSE),
   ('MANTENIMIENTO','FINALIZADO', 'Finalizado', 3, FALSE, TRUE),
   ('MANTENIMIENTO','CANCELADO',  'Cancelado',  4, FALSE, TRUE);
  
  INSERT INTO tipos_pqr (codigo, nombre, prefijo, descripcion, sla_dias) VALUES
   ('PETICION', 'Petición', 'PET', 'Solicitud de información o de una acción',     15),
   ('QUEJA',    'Queja',    'QUE', 'Inconformidad con un servicio o una conducta',  15),
   ('RECLAMO',  'Reclamo',  'REC', 'Reclamación por un derecho o servicio afectado', 15);
  
  INSERT INTO categorias_comunicado (nombre, descripcion, color) VALUES
   ('General',        'Información general de la copropiedad', '#1E88E5'),
   ('Mantenimiento',  'Trabajos y mantenimientos programados', '#FB8C00'),
   ('Seguridad',      'Avisos de seguridad y convivencia',     '#E53935'),
   ('Asambleas',      'Convocatorias y actas',                 '#43A047'),
   ('Eventos',        'Actividades y eventos sociales',        '#8E24AA');
  
  COMMIT;
