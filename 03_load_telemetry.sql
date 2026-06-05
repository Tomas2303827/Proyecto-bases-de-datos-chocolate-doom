-- ================================================================
-- 03_load_telemetry.sql  –  Carga de la telemetria limpia
-- Lee telemetria_limpia.csv (en la raiz del repo) hacia el staging y
-- ejecuta la transformacion al modelo. Correr psql desde la raiz del repo.
-- ================================================================

TRUNCATE raw_telemetry_staging;

\copy raw_telemetry_staging (player_name, episode, map_code, celda_250, tic, pos_x, pos_y, pos_z, angulo, momentum_x, momentum_y, momentum_z, fov, salud, armadura, municion) FROM 'telemetria_limpia.csv' WITH (FORMAT csv, HEADER true)

SELECT * FROM cargar_nucleo();
