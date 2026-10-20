-- =====================================================================
--  RESERVAS v3: liberación automática de solicitudes no confirmadas y recordatorios.
--  Idempotente. Se ejecuta desde apps/reservas/migrations/0002_automatizacion.py
-- =====================================================================

-- Plazos configurables por amenidad (junto a las demás políticas de reserva).
ALTER TABLE reglas_reserva
    ADD COLUMN IF NOT EXISTS horas_limite_confirmacion INTEGER NOT NULL DEFAULT 24
        CHECK (horas_limite_confirmacion > 0),       -- tiempo que tiene la administración para confirmar
    ADD COLUMN IF NOT EXISTS horas_recordatorio INTEGER NOT NULL DEFAULT 24
        CHECK (horas_recordatorio >= 0);             -- recordatorio X h antes del inicio; 0 = sin recordatorio

-- Marcas para no enviar dos veces el mismo recordatorio.
ALTER TABLE reservas
    ADD COLUMN IF NOT EXISTS recordatorio_enviado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS aviso_pendiente_en      TIMESTAMPTZ;

-- Estado final para las solicitudes que se liberan por falta de confirmación.
-- Al ser es_final, deja de ocupar la amenidad (lo respetan los triggers y las consultas).
INSERT INTO estados (proceso, codigo, nombre, orden, es_inicial, es_final)
VALUES ('RESERVA', 'EXPIRADA', 'Expirada', 6, FALSE, TRUE)
ON CONFLICT (proceso, codigo) DO NOTHING;

-- Historial: texto por defecto también para EXPIRADA (el servicio siempre envía un motivo).
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
                              WHEN 'EXPIRADA'   THEN 'Solicitud liberada por falta de confirmación'
                              ELSE 'Cambio de estado'
                         END));
    END IF;
    RETURN NULL;
END $$;
