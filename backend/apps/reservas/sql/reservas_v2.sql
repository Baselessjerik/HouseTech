-- =====================================================================
--  MÓDULO AMENIDADES Y RESERVAS - ajustes sobre core/sql/schema.sql
--  Se ejecuta desde apps/reservas/migrations/0001_initial.py (sin BEGIN/COMMIT,
--  Django ya envuelve la migración en una transacción). Es idempotente.
--
--  Convención: los errores de regla de negocio lanzados por triggers usan el
--  SQLSTATE 23P01; core/exceptions.py los traduce a HTTP 409 con el mensaje.
-- =====================================================================

-- Índices para agenda, historial y reportes con filtros.
CREATE INDEX IF NOT EXISTS ix_reservas_fecha    ON reservas (fecha_inicio);
CREATE INDEX IF NOT EXISTS ix_reservas_inmueble ON reservas (inmueble_id, fecha_inicio);

-- ---------------------------------------------------------------------
-- RF5-RF6 / RF11: verificación de disponibilidad en la base de datos.
-- Respaldo de la validación del servicio: protege también contra
-- escrituras concurrentes u otros clientes que no pasen por la API.
--   * amenidad activa
--   * aforo: num_personas <= amenidades.capacidad
--   * sin solapamiento con otras reservas vigentes
--   * sin solapamiento con bloqueos no cancelados
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_reserva() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_final     boolean;
    v_activa    boolean;
    v_capacidad integer;
BEGIN
    SELECT es_final INTO v_final FROM estados WHERE id = NEW.estado_id;
    IF v_final THEN
        RETURN NEW;           -- canceladas/finalizadas/rechazadas no ocupan la amenidad
    END IF;

    SELECT activa, capacidad INTO v_activa, v_capacidad FROM amenidades WHERE id = NEW.amenidad_id;
    IF NOT FOUND OR NOT v_activa THEN
        RAISE EXCEPTION 'La amenidad está desactivada y no admite reservas'
            USING ERRCODE = '23P01';
    END IF;

    IF v_capacidad IS NOT NULL AND NEW.num_personas IS NOT NULL AND NEW.num_personas > v_capacidad THEN
        RAISE EXCEPTION 'El número de personas (%) supera el aforo de la amenidad (%)',
            NEW.num_personas, v_capacidad
            USING ERRCODE = '23P01';
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

DROP TRIGGER IF EXISTS trg_reservas_validar ON reservas;
CREATE TRIGGER trg_reservas_validar
    BEFORE INSERT OR UPDATE OF amenidad_id, fecha_inicio, fecha_fin, estado_id, num_personas ON reservas
    FOR EACH ROW EXECUTE FUNCTION fn_validar_reserva();

-- ---------------------------------------------------------------------
-- RF11: historial de reservas con detalle legible por cada cambio de estado.
-- (motivo_cancelacion también guarda el motivo del rechazo.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reservas_historial() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user   bigint := NULLIF(current_setting('app.usuario_id', true), '')::bigint;
    v_codigo text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT codigo INTO v_codigo FROM estados WHERE id = NEW.estado_id;
        INSERT INTO reservas_historial (reserva_id, estado_anterior_id, estado_nuevo_id, usuario_id, detalle)
        VALUES (NEW.id, NULL, NEW.estado_id, v_user,
                CASE WHEN v_codigo = 'CONFIRMADA' THEN 'Reserva creada y confirmada automáticamente'
                     ELSE 'Reserva creada' END);
    ELSIF NEW.estado_id IS DISTINCT FROM OLD.estado_id THEN
        SELECT codigo INTO v_codigo FROM estados WHERE id = NEW.estado_id;
        INSERT INTO reservas_historial (reserva_id, estado_anterior_id, estado_nuevo_id, usuario_id, detalle)
        VALUES (NEW.id, OLD.estado_id, NEW.estado_id, v_user,
                COALESCE(NULLIF(NEW.motivo_cancelacion, ''),
                         CASE v_codigo
                              WHEN 'CONFIRMADA' THEN 'Reserva confirmada'
                              WHEN 'RECHAZADA'  THEN 'Reserva rechazada'
                              WHEN 'CANCELADA'  THEN 'Reserva cancelada'
                              WHEN 'FINALIZADA' THEN 'Reserva finalizada'
                              ELSE 'Cambio de estado'
                         END));
    END IF;
    RETURN NULL;
END $$;

-- ---------------------------------------------------------------------
-- Utilidad para consultas SQL directas: ¿está libre la amenidad en el rango?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_amenidad_libre(
    p_amenidad bigint, p_inicio timestamptz, p_fin timestamptz, p_excluir_reserva bigint DEFAULT NULL
) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM reservas r JOIN estados e ON e.id = r.estado_id
        WHERE r.amenidad_id = p_amenidad AND NOT e.es_final
          AND r.id IS DISTINCT FROM p_excluir_reserva
          AND tstzrange(r.fecha_inicio, r.fecha_fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
    ) AND NOT EXISTS (
        SELECT 1 FROM bloqueos_amenidad b
        WHERE b.amenidad_id = p_amenidad AND NOT b.cancelado
          AND tstzrange(b.fecha_inicio, b.fecha_fin, '[)') && tstzrange(p_inicio, p_fin, '[)')
    )
$$;
