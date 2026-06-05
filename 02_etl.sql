-- ================================================================
-- 02_etl.sql  –  Zona de staging + funcion de carga al modelo
-- La telemetria limpia se carga primero en una tabla de staging y de
-- ahi se transforma a las tablas del modelo (jugadores, mapas, sectores,
-- partidas, participaciones y eventos). La asociacion jugador<->evento
-- viene dada por la columna player_name del propio dataset.
-- ================================================================

-- Tabla de staging: refleja 1:1 las columnas de telemetria_limpia.csv
CREATE TABLE IF NOT EXISTS raw_telemetry_staging (
    player_name  TEXT,
    episode      INT,
    map_code     TEXT,
    celda_250    TEXT,
    tic          INT,
    pos_x        FLOAT,
    pos_y        FLOAT,
    pos_z        FLOAT,
    angulo       FLOAT,
    momentum_x   FLOAT,
    momentum_y   FLOAT,
    momentum_z   FLOAT,
    fov          FLOAT,
    salud        INT,
    armadura     INT,
    municion     INT
);

-- ----------------------------------------------------------------
-- Funcion de carga: staging -> modelo. Devuelve un resumen de conteos.
-- Es re-ejecutable: limpia las tablas de juego antes de poblarlas.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION cargar_nucleo()
RETURNS TABLE (usuarios INT, jugadores INT, mapas INT, sectores INT,
               partidas INT, eventos INT) AS $$
BEGIN
    TRUNCATE Telemetry_event, GameParticipant, Game, Sector, Map, Player, "User"
        RESTART IDENTITY CASCADE;

    -- Usuarios y jugadores (uno por nombre distinto del dataset)
    INSERT INTO "User" (user_name, consent_given)
    SELECT DISTINCT player_name, TRUE
    FROM   raw_telemetry_staging;

    INSERT INTO Player (user_id, player_name)
    SELECT u.id, u.user_name
    FROM   "User" u;

    -- Mapas (uno por episodio+codigo distinto)
    INSERT INTO Map (episode, map_code, map_name, wide, length)
    SELECT DISTINCT episode, map_code,
           CASE map_code
                WHEN 'E1M2' THEN 'Nuclear Plant'
                WHEN 'E1M5' THEN 'Phobos Lab'
                WHEN 'E2M1' THEN 'Deimos Anomaly'
                WHEN 'E2M2' THEN 'Containment Area'
                WHEN 'E3M1' THEN 'Hell Keep'
                WHEN 'E3M2' THEN 'Slough of Despair'
                WHEN 'E3M5' THEN 'Unholy Cathedral'
                WHEN 'E4M1' THEN 'Hell Beneath'
                ELSE map_code
           END,
           250, 250
    FROM   raw_telemetry_staging;

    -- Sectores: catalogo de celdas presentes por mapa (geografia estatica)
    INSERT INTO Sector (map_id, sector_code)
    SELECT m.id_map, s.celda_250
    FROM   (SELECT DISTINCT episode, map_code, celda_250 FROM raw_telemetry_staging) s
    JOIN   Map m ON m.episode = s.episode AND m.map_code = s.map_code;

    -- Partidas y participaciones: una por (jugador, episodio, mapa)
    CREATE TEMP TABLE _combo ON COMMIT DROP AS
    SELECT d.player_name, d.episode, d.map_code,
           uuid_generate_v4() AS game_id,
           uuid_generate_v4() AS participant_id
    FROM   (SELECT DISTINCT player_name, episode, map_code
            FROM raw_telemetry_staging) d;

    INSERT INTO Game (game_id, map_id, state)
    SELECT c.game_id, m.id_map, 'finished'
    FROM   _combo c JOIN Map m ON m.episode = c.episode AND m.map_code = c.map_code;

    INSERT INTO GameParticipant (participant_id, game_id, player_id)
    SELECT c.participant_id, c.game_id, p.player_id
    FROM   _combo c JOIN Player p ON p.player_name = c.player_name;

    -- Eventos de telemetria, ligados a su participacion
    INSERT INTO Telemetry_event (
        participant_id, tic, pos_x, pos_y, pos_z, angulo,
        momentum_x, momentum_y, momentum_z, fov, salud, armadura, municion)
    SELECT c.participant_id, s.tic, s.pos_x, s.pos_y, s.pos_z, s.angulo,
           s.momentum_x, s.momentum_y, s.momentum_z, s.fov,
           s.salud, s.armadura, s.municion
    FROM   raw_telemetry_staging s
    JOIN   _combo c ON c.player_name = s.player_name
                   AND c.episode    = s.episode
                   AND c.map_code   = s.map_code;

    RETURN QUERY
    SELECT (SELECT COUNT(*) FROM "User")::INT,
           (SELECT COUNT(*) FROM Player)::INT,
           (SELECT COUNT(*) FROM Map)::INT,
           (SELECT COUNT(*) FROM Sector)::INT,
           (SELECT COUNT(*) FROM Game)::INT,
           (SELECT COUNT(*) FROM Telemetry_event)::INT;
END $$ LANGUAGE plpgsql;
