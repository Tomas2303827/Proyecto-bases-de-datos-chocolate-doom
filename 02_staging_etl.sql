-- ================================================================
-- Chocolate-Doom Telemetry & UX Database
-- 02_staging_etl.sql  –  Staging · Error Log · ETL Pipeline
-- ================================================================
-- Pipeline: TSV file → raw_telemetry_staging → Telemetry_event
--           Registros rechazados → etl_error_log

-- ── Tabla staging: todo TEXT, sin restricciones ─────────────────
CREATE TABLE IF NOT EXISTS raw_telemetry_staging (
    raw_id        BIGSERIAL  PRIMARY KEY,
    game_id       TEXT,          -- UUID de la partida (texto libre)
    player_name   TEXT,          -- alias del jugador
    episode       TEXT,
    map_code      TEXT,
    sector_code   TEXT,
    tic           TEXT,
    pos_x         TEXT,
    pos_y         TEXT,
    pos_z         TEXT,
    angulo        TEXT,
    momentum_x    TEXT,
    momentum_y    TEXT,
    momentum_z    TEXT,
    fov           TEXT,
    salud         TEXT,
    armadura      TEXT,
    municion      TEXT,
    source_file   TEXT,
    loaded_at     TIMESTAMP DEFAULT NOW()
);

-- ── Log de errores de transformación ────────────────────────────
CREATE TABLE IF NOT EXISTS etl_error_log (
    error_id      BIGSERIAL  PRIMARY KEY,
    raw_id        BIGINT,
    error_reason  TEXT       NOT NULL,
    raw_data      TEXT,
    logged_at     TIMESTAMP  DEFAULT NOW()
);

-- ================================================================
-- FUNCIÓN ETL: staging → core
-- Retorna: (inserted, rejected, skipped)
-- ================================================================
CREATE OR REPLACE FUNCTION etl_process_staging()
RETURNS TABLE(inserted BIGINT, rejected BIGINT, skipped BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
    rec             RECORD;
    v_participant   UUID;
    v_sector        UUID;
    v_tic           INT;
    v_pos_x         FLOAT;
    v_pos_y         FLOAT;
    v_pos_z         FLOAT;
    v_angulo        FLOAT;
    v_mx            FLOAT;
    v_my            FLOAT;
    v_mz            FLOAT;
    v_fov           FLOAT;
    v_salud         INT;
    v_armadura      INT;
    v_municion      INT;
    cnt_inserted    BIGINT := 0;
    cnt_rejected    BIGINT := 0;
    cnt_skipped     BIGINT := 0;
    rows_affected   INT;
BEGIN
    FOR rec IN SELECT * FROM raw_telemetry_staging ORDER BY raw_id LOOP
        BEGIN
            -- ── 1. Casteo y validación de tipos ──────────────────
            v_tic      := rec.tic::INT;
            v_pos_x    := rec.pos_x::FLOAT;
            v_pos_y    := rec.pos_y::FLOAT;
            v_pos_z    := COALESCE(NULLIF(rec.pos_z, ''), '0')::FLOAT;
            v_angulo   := rec.angulo::FLOAT;
            v_mx       := rec.momentum_x::FLOAT;
            v_my       := rec.momentum_y::FLOAT;
            v_mz       := COALESCE(NULLIF(rec.momentum_z, ''), '0')::FLOAT;
            v_fov      := rec.fov::FLOAT;
            v_salud    := rec.salud::INT;
            v_armadura := rec.armadura::INT;
            v_municion := rec.municion::INT;

            -- ── 2. Validación de rangos ───────────────────────────
            IF v_tic <= 0 THEN
                RAISE EXCEPTION 'tic debe ser > 0, recibido: %', v_tic;
            END IF;
            IF v_salud < 0 OR v_salud > 200 THEN
                RAISE EXCEPTION 'salud fuera de rango [0,200]: %', v_salud;
            END IF;
            IF v_armadura < 0 OR v_armadura > 200 THEN
                RAISE EXCEPTION 'armadura fuera de rango [0,200]: %', v_armadura;
            END IF;
            IF v_municion < 0 OR v_municion > 999 THEN
                RAISE EXCEPTION 'municion fuera de rango [0,999]: %', v_municion;
            END IF;
            IF v_angulo < 0 OR v_angulo >= 360 THEN
                RAISE EXCEPTION 'angulo fuera de rango [0,360): %', v_angulo;
            END IF;

            -- ── 3. Resolver participant_id ────────────────────────
            SELECT gp.participant_id INTO v_participant
            FROM   GameParticipant gp
            JOIN   Player p  ON p.player_id = gp.player_id
            JOIN   Game   g  ON g.game_id   = gp.game_id
            WHERE  g.game_id::TEXT = rec.game_id
              AND  p.player_name   = rec.player_name
            LIMIT 1;

            IF v_participant IS NULL THEN
                RAISE EXCEPTION 'participant no encontrado: game=% player=%',
                    rec.game_id, rec.player_name;
            END IF;

            -- ── 4. Resolver sector_id (opcional) ─────────────────
            SELECT s.sector_id INTO v_sector
            FROM   Sector s
            JOIN   Map    m ON m.id_map   = s.map_id
            WHERE  m.map_code    = rec.map_code
              AND  s.sector_code = rec.sector_code
            LIMIT 1;
            -- Si no se encuentra, sector_id quedará NULL (permitido)

            -- ── 5. Insertar / saltar duplicado ────────────────────
            INSERT INTO Telemetry_event (
                participant_id, sector_id, tic,
                pos_x, pos_y, pos_z, angulo,
                momentum_x, momentum_y, momentum_z,
                fov, salud, armadura, municion
            ) VALUES (
                v_participant, v_sector, v_tic,
                v_pos_x, v_pos_y, v_pos_z, v_angulo,
                v_mx, v_my, v_mz,
                v_fov, v_salud, v_armadura, v_municion
            )
            ON CONFLICT (participant_id, tic) DO NOTHING;

            GET DIAGNOSTICS rows_affected = ROW_COUNT;
            IF rows_affected = 0 THEN
                cnt_skipped := cnt_skipped + 1;
            ELSE
                cnt_inserted := cnt_inserted + 1;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            -- Registrar error y continuar con el siguiente registro
            INSERT INTO etl_error_log (raw_id, error_reason, raw_data)
            VALUES (rec.raw_id, SQLERRM, rec::TEXT);
            cnt_rejected := cnt_rejected + 1;
        END;
    END LOOP;

    RETURN QUERY SELECT cnt_inserted, cnt_rejected, cnt_skipped;
END;
$$;

-- ================================================================
-- CÓMO CARGAR UN TSV REAL (ejecutar desde psql)
-- ================================================================
-- Paso 1 – Cargar archivo al staging:
--
--   \copy raw_telemetry_staging(game_id, player_name, episode,
--         map_code, sector_code, tic, pos_x, pos_y, pos_z,
--         angulo, momentum_x, momentum_y, momentum_z, fov,
--         salud, armadura, municion)
--   FROM 'ruta/al/archivo.tsv'
--   DELIMITER E'\t' CSV HEADER;
--
-- Paso 2 – Ejecutar la transformación:
--
--   SELECT * FROM etl_process_staging();
--
-- El resultado muestra cuántos registros fueron:
--   inserted  → insertados correctamente
--   rejected  → fallaron validación (ver etl_error_log)
--   skipped   → tic duplicado (ya existía)
-- ================================================================
