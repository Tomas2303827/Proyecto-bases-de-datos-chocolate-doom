-- ================================================================
-- Chocolate-Doom Telemetry & UX Database
-- 04_seed_data.sql  –  Datos sintéticos de muestra
-- ================================================================
-- Genera:  6 mapas (3 episodios × 2 mapas)
--          24 sectores (4 por mapa)
--          8 jugadores
--          18 partidas (3 por mapa)
--          36 game-participants
--         ~25 200 filas de telemetría  (36 × 700 tics)
--          72 respuestas UX (8 usuarios × 9 ítems BANGS)
-- ================================================================

-- ================================================================
-- FASE 1: Mapas · Sectores · Usuarios · Jugadores · Partidas
-- (DO block: necesita rastrear UUIDs entre INSERTs)
-- ================================================================
DO $$
DECLARE
    -- arrays para acumular IDs
    map_ids        UUID[]  := ARRAY[]::UUID[];
    player_ids     UUID[]  := ARRAY[]::UUID[];
    all_sector_ids UUID[]  := ARRAY[]::UUID[];  -- plano: mapa m → índices (m-1)*4+1 .. m*4

    -- variables de trabajo
    v_map_id       UUID;
    v_sector_id    UUID;
    v_user_id      UUID;
    v_player_id    UUID;
    v_game_id      UUID;
    v_game_start   TIMESTAMP;
    v_part_id      UUID;

    -- datos de mapas y usuarios
    map_data       TEXT[][];
    user_data      TEXT[][];

    -- contadores
    m INT; s INT; u INT; gnum INT;
    game_num  INT := 0;
    p1 INT; p2 INT; pidx INT;
    p_indices INT[];

BEGIN
    -- ── Tabla temporal para fase 2 (telemetría en bulk) ──────────
    CREATE TEMP TABLE IF NOT EXISTS tmp_participants_gen (
        participant_id UUID,
        map_id         UUID,
        player_seq     INT,   -- para variación de trayectoria
        game_seq       INT
    );

    -- ── Datos de mapas ────────────────────────────────────────────
    map_data := ARRAY[
        ['1','E1M1','Hangar',           '8192','6144'],
        ['1','E1M2','Nuclear Plant',    '7680','5120'],
        ['2','E2M1','Deimos Anomaly',   '9216','7168'],
        ['2','E2M2','Containment Area', '8704','6656'],
        ['3','E3M1','Hell Keep',        '7168','5632'],
        ['3','E3M2','Slough of Despair','8192','6144']
    ];

    -- ── 1. Insertar mapas y sectores ─────────────────────────────
    FOR m IN 1..6 LOOP
        INSERT INTO Map (episode, map_code, map_name, wide, length)
        VALUES (
            map_data[m][1]::INT,
            map_data[m][2],
            map_data[m][3],
            map_data[m][4]::INT,
            map_data[m][5]::INT
        ) RETURNING id_map INTO v_map_id;

        map_ids := map_ids || v_map_id;

        -- 4 sectores por mapa (A, B, C, D)
        FOR s IN 1..4 LOOP
            INSERT INTO Sector (map_id, sector_code, descri)
            VALUES (
                v_map_id,
                map_data[m][2] || '_SEC_' || chr(64 + s),
                'Sector ' || chr(64 + s) || ' del mapa ' || map_data[m][2]
            ) RETURNING sector_id INTO v_sector_id;

            all_sector_ids := all_sector_ids || v_sector_id;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Mapas: 6  |  Sectores: 24';

    -- ── Datos de usuarios ─────────────────────────────────────────
    user_data := ARRAY[
        ['Doomguy',      'male',             'advanced'],
        ['SlayerX',      'female',           'expert'],
        ['DemonKiller',  'male',             'intermediate'],
        ['HellWalker',   'non_binary',       'beginner'],
        ['MarineOne',    'male',             'beginner'],
        ['FragMaster',   'female',           'advanced'],
        ['IronFist',     'prefer_not_to_say','intermediate'],
        ['ShotgunSam',   'male',             'expert']
    ];

    -- ── 2. Insertar usuarios y players ───────────────────────────
    FOR u IN 1..8 LOOP
        INSERT INTO "User" (user_name, user_genre, user_level_of_exp, consent_given)
        VALUES (
            user_data[u][1],
            user_data[u][2]::user_genre,
            user_data[u][3]::level_exp,
            TRUE
        ) RETURNING id INTO v_user_id;

        INSERT INTO Player (user_id, player_name)
        VALUES (v_user_id, user_data[u][1])
        RETURNING player_id INTO v_player_id;

        player_ids := player_ids || v_player_id;
    END LOOP;

    RAISE NOTICE 'Usuarios: 8  |  Players: 8';

    -- ── 3. Insertar partidas y participants ──────────────────────
    -- 3 partidas por mapa → 18 partidas · 2 jugadores c/u → 36 participants
    FOR m IN 1..6 LOOP
        FOR gnum IN 1..3 LOOP
            game_num := game_num + 1;

            v_game_start := NOW()
                - make_interval(days  => (random() * 20 + 3)::INT)
                - make_interval(hours => (random() * 12)::INT);

            INSERT INTO Game (map_id, state, start_timestamp, end_timestamp)
            VALUES (
                map_ids[m],
                'finished',
                v_game_start,
                v_game_start + make_interval(mins => 20 + (random() * 25)::INT)
            ) RETURNING game_id INTO v_game_id;

            -- 2 jugadores distintos (ciclo sobre los 8)
            p1 := ((game_num - 1) % 8) + 1;
            p2 := (game_num        % 8) + 1;
            p_indices := ARRAY[p1, p2];

            FOREACH pidx IN ARRAY p_indices LOOP
                INSERT INTO GameParticipant (game_id, player_id, join_time, leave_time)
                VALUES (
                    v_game_id,
                    player_ids[pidx],
                    v_game_start,
                    v_game_start + make_interval(mins => 18 + (random() * 20)::INT)
                ) RETURNING participant_id INTO v_part_id;

                -- Guardar para la fase de telemetría bulk
                INSERT INTO tmp_participants_gen (participant_id, map_id, player_seq, game_seq)
                VALUES (v_part_id, map_ids[m], pidx, game_num);
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Partidas: %  |  Participants: %', game_num, game_num * 2;
END $$;


-- ================================================================
-- FASE 2: Telemetría en bulk (set-based, ~25 200 filas)
-- ================================================================
-- Estrategia: trayectorias tipo Lissajous (deterministas, realistas)
-- Sector asignado ciclando A→B→C→D cada tic
-- Salud/armadura oscilan con sin/cos; munición decrece con el tiempo
-- ================================================================
WITH sector_ranked AS (
    -- Numerar los 4 sectores de cada mapa (A=1, B=2, C=3, D=4)
    SELECT
        sector_id,
        map_id,
        ROW_NUMBER() OVER (PARTITION BY map_id ORDER BY sector_code) AS sec_rank
    FROM Sector
),
telemetry_raw AS (
    SELECT
        p.participant_id,
        sr.sector_id,
        t.tic,

        -- Trayectoria: combinación de Lissajous + offset por jugador/partida
        (500.0 * sin(radians(t.tic * 0.5 + p.player_seq * 37.5))
             + p.player_seq * 120.0 - 500.0)::FLOAT          AS pos_x,
        (400.0 * cos(radians(t.tic * 0.7 + p.player_seq * 22.5))
             + p.game_seq  * 80.0  - 300.0)::FLOAT           AS pos_y,
        0.0::FLOAT                                            AS pos_z,

        -- Ángulo de orientación [0, 360)
        ((t.tic * 5.14 + p.player_seq * 45.0) % 360.0)::FLOAT AS angulo,

        -- Vectores de momentum (derivada de la posición)
        (500.0 * 0.5 * (cos(radians(t.tic * 0.5 + p.player_seq * 37.5))
                      - cos(radians((t.tic-1) * 0.5 + p.player_seq * 37.5))))::FLOAT AS momentum_x,
        (400.0 * 0.7 * (-sin(radians(t.tic * 0.7 + p.player_seq * 22.5))
                       + sin(radians((t.tic-1) * 0.7 + p.player_seq * 22.5))))::FLOAT AS momentum_y,
        0.0::FLOAT                                            AS momentum_z,

        90.0::FLOAT                                           AS fov,

        -- Estadísticas de combate (oscilantes y acotadas)
        GREATEST(0, LEAST(200,
            (100 + (30.0 * sin(t.tic * 0.05 + p.player_seq))::INT)
        ))                                                    AS salud,
        GREATEST(0, LEAST(200,
            (50 + (25.0 * cos(t.tic * 0.03 + p.player_seq))::INT)
        ))                                                    AS armadura,
        GREATEST(0, LEAST(999,
            200 - (t.tic / 4)
        ))                                                    AS municion

    FROM tmp_participants_gen p
    CROSS JOIN generate_series(1, 700) AS t(tic)
    JOIN sector_ranked sr
        ON sr.map_id   = p.map_id
        AND sr.sec_rank = ((t.tic - 1) % 4) + 1   -- ciclo A→B→C→D
)
INSERT INTO Telemetry_event (
    participant_id, sector_id, tic,
    pos_x, pos_y, pos_z,
    angulo, momentum_x, momentum_y, momentum_z,
    fov, salud, armadura, municion
)
SELECT
    participant_id, sector_id, tic,
    pos_x, pos_y, pos_z,
    angulo, momentum_x, momentum_y, momentum_z,
    fov, salud, armadura, municion
FROM telemetry_raw;

-- Confirmar filas insertadas
DO $$
DECLARE cnt BIGINT;
BEGIN
    SELECT COUNT(*) INTO cnt FROM Telemetry_event;
    RAISE NOTICE 'Telemetry_event total: % filas', cnt;
END $$;


-- ================================================================
-- FASE 3: Respuestas UX (8 usuarios × 9 ítems BANGS = 72 filas)
-- ================================================================
DO $$
DECLARE
    v_instrument_id UUID;
    v_answer_id     UUID;
    v_score         INT;
    v_user_rec      RECORD;
    v_item_rec      RECORD;
BEGIN
    SELECT instrument_id INTO v_instrument_id
    FROM Instrument_UX WHERE name = 'BANGS';

    FOR v_user_rec IN SELECT id FROM "User" LOOP

        INSERT INTO Answer_UX (user_id, instrument_id, ended)
        VALUES (
            v_user_rec.id,
            v_instrument_id,
            NOW() - make_interval(days => (random() * 5)::INT)
        ) RETURNING answer_id INTO v_answer_id;

        FOR v_item_rec IN
            SELECT item_id FROM Item_UX
            WHERE  instrument_id = v_instrument_id
            ORDER  BY item_pos
        LOOP
            -- Puntuación Likert 1–5 aleatoria
            v_score := 1 + floor(random() * 5)::INT;

            INSERT INTO UXResponseItem (answer_id, item_id, score)
            VALUES (v_answer_id, v_item_rec.item_id, v_score);
        END LOOP;

    END LOOP;

    RAISE NOTICE 'Respuestas UX insertadas: % filas',
        (SELECT COUNT(*) FROM UXResponseItem);
END $$;

-- ================================================================
-- LIMPIEZA de tabla temporal
-- ================================================================
DROP TABLE IF EXISTS tmp_participants_gen;
