-- ================================================================
-- 06_analytics.sql  –  Consultas analiticas · Vistas · Indices
-- Implementa 6 de las 8 consultas del enunciado (todas menos Q2 y Q6,
-- las de cooperacion). Adaptadas a la nomenclatura real del esquema.
-- ================================================================

-- ----------------------------------------------------------------
-- Q1. Duracion media de las sesiones de juego por mapa.
--     La duracion se deriva del rango de tics de cada sesion
--     (el motor de Doom corre a 35 tics por segundo).
-- ----------------------------------------------------------------
WITH dur AS (
    SELECT gp.game_id, g.map_id,
           (MAX(te.tic) - MIN(te.tic)) / 35.0 AS segundos
    FROM   Telemetry_event te
    JOIN   GameParticipant gp ON gp.participant_id = te.participant_id
    JOIN   Game            g  ON g.game_id          = gp.game_id
    GROUP  BY gp.game_id, g.map_id
)
SELECT m.map_code,
       m.map_name,
       COUNT(*)                          AS sesiones,
       ROUND(AVG(d.segundos)::numeric, 1) AS duracion_media_seg
FROM   dur d
JOIN   Map m ON m.id_map = d.map_id
GROUP  BY m.map_code, m.map_name
ORDER  BY duracion_media_seg DESC;

-- ----------------------------------------------------------------
-- Q3. Trayectoria mas corta y mas larga por jugador
--     (window function LAG -> distancia euclidea entre tics) [BONUS]
-- ----------------------------------------------------------------
WITH steps AS (
    SELECT te.participant_id, te.tic, te.pos_x, te.pos_y,
           LAG(te.pos_x) OVER w AS px,
           LAG(te.pos_y) OVER w AS py
    FROM   Telemetry_event te
    WINDOW w AS (PARTITION BY te.participant_id ORDER BY te.tic)
),
dist_per_game AS (
    SELECT participant_id,
           SUM( sqrt( power(pos_x-px,2) + power(pos_y-py,2) ) ) AS dist
    FROM   steps
    WHERE  px IS NOT NULL
    GROUP  BY participant_id
)
SELECT p.player_name,
       ROUND(MIN(d.dist)::numeric,2) AS trayectoria_min,
       ROUND(MAX(d.dist)::numeric,2) AS trayectoria_max
FROM   dist_per_game d
JOIN   GameParticipant gp ON gp.participant_id = d.participant_id
JOIN   Player p           ON p.player_id       = gp.player_id
GROUP  BY p.player_name
ORDER  BY trayectoria_max DESC;

-- ----------------------------------------------------------------
-- Q4. Respuestas UX de jugadores con duracion de trayectoria
--     por ENCIMA del promedio global (en tics)
-- ----------------------------------------------------------------
WITH dur AS (
    SELECT gp.player_id, SUM(t.maxt - t.mint) AS dur_tics
    FROM ( SELECT participant_id, MAX(tic) maxt, MIN(tic) mint
           FROM Telemetry_event GROUP BY participant_id ) t
    JOIN GameParticipant gp ON gp.participant_id = t.participant_id
    GROUP BY gp.player_id
),
avg_dur AS ( SELECT AVG(dur_tics) AS a FROM dur )
SELECT p.player_name, d.dur_tics, i.item_pos, i.subscale, ri.score
FROM   dur d
CROSS  JOIN avg_dur
JOIN   Player p          ON p.player_id = d.player_id
JOIN   "User" u          ON u.id        = p.user_id
JOIN   Answer_UX a       ON a.user_id   = u.id
JOIN   UXResponseItem ri ON ri.answer_id = a.answer_id
JOIN   Item_UX i         ON i.item_id    = ri.item_id
WHERE  d.dur_tics > avg_dur.a
ORDER  BY p.player_name, i.item_pos;

-- ----------------------------------------------------------------
-- Q5. Celda (sector analitico) mas visitada por Episodio y Mapa.
-- El "sector" se calcula como una celda de 250x250 unidades a partir de
-- (pos_x, pos_y); NO usa la tabla Sector ni FK alguna.
-- ----------------------------------------------------------------
SELECT DISTINCT ON (m.episode, m.map_code)
       m.episode, m.map_code, conteo.celda, conteo.visitas
FROM   ( SELECT g.map_id,
                format('(%s,%s)',
                       floor(te.pos_x/250.0)::int,
                       floor(te.pos_y/250.0)::int) AS celda,
                COUNT(*) AS visitas
         FROM Telemetry_event te
         JOIN GameParticipant gp ON gp.participant_id = te.participant_id
         JOIN Game            g  ON g.game_id          = gp.game_id
         GROUP BY g.map_id,
                  floor(te.pos_x/250.0)::int,
                  floor(te.pos_y/250.0)::int ) conteo
JOIN   Map m ON m.id_map = conteo.map_id
ORDER  BY m.episode, m.map_code, conteo.visitas DESC;

-- ----------------------------------------------------------------
-- Q7. Puntaje UX medio de los jugadores con la trayectoria mas
--     corta por episodio
-- ----------------------------------------------------------------
WITH steps AS (
    SELECT te.participant_id, te.tic, te.pos_x, te.pos_y,
           LAG(te.pos_x) OVER w AS px, LAG(te.pos_y) OVER w AS py
    FROM Telemetry_event te
    WINDOW w AS (PARTITION BY te.participant_id ORDER BY te.tic)
),
dist_per_game AS (
    SELECT participant_id, SUM(sqrt(power(pos_x-px,2)+power(pos_y-py,2))) AS dist
    FROM steps WHERE px IS NOT NULL GROUP BY participant_id
),
pdist AS (
    SELECT m.episode, gp.player_id, SUM(d.dist) AS total_dist
    FROM dist_per_game d
    JOIN GameParticipant gp ON gp.participant_id = d.participant_id
    JOIN Game g             ON g.game_id        = gp.game_id
    JOIN Map  m             ON m.id_map         = g.map_id
    GROUP BY m.episode, gp.player_id
),
mn AS (
    SELECT DISTINCT ON (episode) episode, player_id, total_dist
    FROM pdist ORDER BY episode, total_dist ASC
)
SELECT mn.episode, p.player_name,
       ROUND(mn.total_dist::numeric,2) AS trayectoria_total,
       ROUND(AVG(ri.score)::numeric,2) AS ux_promedio
FROM   mn
JOIN   Player p          ON p.player_id = mn.player_id
JOIN   "User" u          ON u.id        = p.user_id
JOIN   Answer_UX a       ON a.user_id   = u.id
JOIN   UXResponseItem ri ON ri.answer_id = a.answer_id
GROUP  BY mn.episode, p.player_name, mn.total_dist
ORDER  BY mn.episode;

-- ----------------------------------------------------------------
-- Q8. Distancia total y velocidad media por jugador (todas sus partidas)
-- ----------------------------------------------------------------
WITH steps AS (
    SELECT te.participant_id, te.tic, te.pos_x, te.pos_y,
           LAG(te.pos_x) OVER w AS px, LAG(te.pos_y) OVER w AS py
    FROM Telemetry_event te
    WINDOW w AS (PARTITION BY te.participant_id ORDER BY te.tic)
),
dist_per_game AS (
    SELECT participant_id, SUM(sqrt(power(pos_x-px,2)+power(pos_y-py,2))) AS dist
    FROM steps WHERE px IS NOT NULL GROUP BY participant_id
),
span AS (
    SELECT participant_id, (MAX(tic)-MIN(tic)) AS tics
    FROM Telemetry_event GROUP BY participant_id
)
SELECT p.player_name,
       ROUND(SUM(d.dist)::numeric,2)                              AS distancia_total,
       SUM(s.tics)                                                AS tics_totales,
       ROUND((SUM(d.dist)/NULLIF(SUM(s.tics),0))::numeric,4)      AS velocidad_media_por_tic
FROM   dist_per_game d
JOIN   span s            ON s.participant_id = d.participant_id
JOIN   GameParticipant gp ON gp.participant_id = d.participant_id
JOIN   Player p          ON p.player_id = gp.player_id
GROUP  BY p.player_name
ORDER  BY distancia_total DESC;

-- ----------------------------------------------------------------
-- ================================================================
-- VISTAS (2) + VISTA MATERIALIZADA (1)
-- ================================================================

-- Vista 1: distancia/velocidad por jugador (reusa logica Q8)
CREATE OR REPLACE VIEW v_player_movement AS
WITH steps AS (
    SELECT te.participant_id, te.tic, te.pos_x, te.pos_y,
           LAG(te.pos_x) OVER w AS px, LAG(te.pos_y) OVER w AS py
    FROM Telemetry_event te
    WINDOW w AS (PARTITION BY te.participant_id ORDER BY te.tic)
),
dpg AS (SELECT participant_id, SUM(sqrt(power(pos_x-px,2)+power(pos_y-py,2))) dist
        FROM steps WHERE px IS NOT NULL GROUP BY participant_id),
span AS (SELECT participant_id, MAX(tic)-MIN(tic) tics FROM Telemetry_event GROUP BY participant_id)
SELECT p.player_id, p.player_name,
       SUM(dpg.dist) AS distancia_total,
       SUM(span.tics) AS tics_totales,
       SUM(dpg.dist)/NULLIF(SUM(span.tics),0) AS velocidad_media
FROM dpg
JOIN span ON span.participant_id = dpg.participant_id
JOIN GameParticipant gp ON gp.participant_id = dpg.participant_id
JOIN Player p ON p.player_id = gp.player_id
GROUP BY p.player_id, p.player_name;

-- Vista 2: hotspots por celda 250x250 (calculada) por episodio/mapa
CREATE OR REPLACE VIEW v_sector_hotspots AS
SELECT m.episode, m.map_code,
       format('(%s,%s)',
              floor(te.pos_x/250.0)::int,
              floor(te.pos_y/250.0)::int) AS celda,
       COUNT(*) AS visitas
FROM Telemetry_event te
JOIN GameParticipant gp ON gp.participant_id = te.participant_id
JOIN Game            g  ON g.game_id          = gp.game_id
JOIN Map             m  ON m.id_map           = g.map_id
GROUP BY m.episode, m.map_code,
         floor(te.pos_x/250.0)::int, floor(te.pos_y/250.0)::int;

-- Vista materializada: resumen UX (BANGS) por jugador y subescala
DROP MATERIALIZED VIEW IF EXISTS mv_player_ux_summary;
CREATE MATERIALIZED VIEW mv_player_ux_summary AS
SELECT p.player_id, p.player_name, i.subscale,
       ROUND(AVG(ri.score)::numeric,2) AS puntaje_medio,
       COUNT(*) AS items
FROM Player p
JOIN "User" u          ON u.id = p.user_id
JOIN Answer_UX a       ON a.user_id = u.id
JOIN UXResponseItem ri ON ri.answer_id = a.answer_id
JOIN Item_UX i         ON i.item_id = ri.item_id
GROUP BY p.player_id, p.player_name, i.subscale;

CREATE INDEX IF NOT EXISTS idx_mv_ux_player ON mv_player_ux_summary (player_id);
-- Refrescar tras recargar datos:  REFRESH MATERIALIZED VIEW mv_player_ux_summary;
