-- ================================================================
-- 07_index_eval.sql  –  Evaluacion de indices con EXPLAIN ANALYZE
-- Patron: DROP -> EXPLAIN (antes) -> CREATE -> EXPLAIN (despues)
-- ================================================================
-- Consulta de prueba: eventos dentro de una celda 250x250 concreta.
-- El "sector" analitico se calcula desde (pos_x, pos_y); por eso se
-- evalua un indice de EXPRESION sobre esa misma celda. Reproducible
-- sin UUIDs (filtra por la celda y por mapa via participante->partida).

\echo '==== ANTES: sin idx_tel_cell ===='
DROP INDEX IF EXISTS idx_tel_cell;
ANALYZE Telemetry_event;
EXPLAIN (ANALYZE)
SELECT COUNT(*), AVG(te.salud)
FROM   Telemetry_event te
JOIN   GameParticipant gp ON gp.participant_id = te.participant_id
JOIN   Game            g  ON g.game_id          = gp.game_id
JOIN   Map             m  ON m.id_map           = g.map_id
WHERE  m.map_code = 'E3M2'
  AND  floor(te.pos_x/250.0)::int = 0
  AND  floor(te.pos_y/250.0)::int = -2;

\echo '==== DESPUES: con idx_tel_cell ===='
CREATE INDEX idx_tel_cell
    ON Telemetry_event ((floor(pos_x/250.0)::int), (floor(pos_y/250.0)::int));
ANALYZE Telemetry_event;
EXPLAIN (ANALYZE)
SELECT COUNT(*), AVG(te.salud)
FROM   Telemetry_event te
JOIN   GameParticipant gp ON gp.participant_id = te.participant_id
JOIN   Game            g  ON g.game_id          = gp.game_id
JOIN   Map             m  ON m.id_map           = g.map_id
WHERE  m.map_code = 'E3M2'
  AND  floor(te.pos_x/250.0)::int = 0
  AND  floor(te.pos_y/250.0)::int = -2;

-- NOTA: idx_tel_participant_tic es REDUNDANTE con el indice implicito
-- de la restriccion UNIQUE(participant_id, tic); el planificador ya usa
-- ese indice unico para reconstruir trayectorias (Q3/Q8). Se documenta
-- en el reporte como hallazgo de la evaluacion.
