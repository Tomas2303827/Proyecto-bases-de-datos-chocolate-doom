# Chocolate-Doom Telemetry & UX — Base de datos

Base de datos relacional en PostgreSQL que almacena y analiza la telemetría de
juego de Chocolate-Doom junto con datos de experiencia de usuario (UX) recogidos
con el instrumento BANGS. El repositorio incluye el esquema, el proceso de carga,
las consultas analíticas, índices, vistas y el dataset de telemetría ya limpio.

## Contenido del repositorio
- `telemetria_limpia.csv` — dataset de telemetría limpio (un evento por fila, con
  jugador, episodio, mapa, posición y estado del jugador).
- `01_schema.sql` — esquema: tipos, tablas, restricciones e índices.
- `02_etl.sql` — tabla de staging y función de carga `cargar_nucleo()`.
- `03_load_telemetry.sql` — carga `telemetria_limpia.csv` al modelo.
- `04_seed_bangs.sql` — instrumento UX BANGS (9 ítems, escala 1–5).
- `05_seed_surveys.sql` — respuestas de los jugadores al instrumento.
- `06_analytics.sql` — consultas analíticas, vistas y vista materializada.
- `07_index_eval.sql` — evaluación de un índice con EXPLAIN ANALYZE (opcional).
- `run.sh`, `Makefile` — ejecutan todo el flujo.

## Cómo ejecutar
Desde la raíz del repositorio (donde está el CSV):
```bash
./run.sh chocodoom        # o:  make DB=chocodoom
```
O manualmente, en orden:
```bash
psql -d chocodoom -f 01_schema.sql
psql -d chocodoom -f 02_etl.sql
psql -d chocodoom -f 03_load_telemetry.sql
psql -d chocodoom -f 04_seed_bangs.sql
psql -d chocodoom -f 05_seed_surveys.sql
psql -d chocodoom -f 06_analytics.sql
psql -d chocodoom -f 07_index_eval.sql   # opcional
```

## Modelo de datos
El núcleo gira en torno a `GameParticipant`, la tabla puente entre `Game` y `Player`,
de la que cuelga `Telemetry_event` (una muestra por tic). `Map` agrupa `Sector` y es el
escenario de cada `Game`. El bloque UX es independiente: `Instrument_UX` define el
instrumento y sus `Item_UX`, y `Answer_UX` + `UXResponseItem` guardan las respuestas
de cada `User`. El dataset cubre la telemetría de 6 jugadores a lo largo de 4 episodios
y 8 mapas (más de 20.000 eventos).

## Consultas analíticas (06_analytics.sql)
- Q1 — Duración media de las sesiones por mapa (derivada del rango de tics; Doom corre a 35 tics/seg).
- Q3 — Trayectoria más corta y más larga por jugador (distancia euclídea entre tics con LAG).
- Q4 — Respuestas UX de los jugadores con trayectoria por encima del promedio.
- Q5 — Celda más visitada (hotspot) por episodio y mapa.
- Q7 — Puntaje UX medio del jugador con la trayectoria más corta por episodio.
- Q8 — Distancia total y velocidad media por jugador.

Además define 2 vistas (`v_player_movement`, `v_sector_hotspots`) y 1 vista
materializada (`mv_player_ux_summary`).

## Notas de diseño
- El "sector" para el análisis de hotspots (Q5) se calcula como una celda de 250x250
  unidades a partir de `pos_x`/`pos_y`. La tabla `Sector` es un catálogo de la geografía
  del nivel, ligado únicamente a `Map`.
- El instrumento UX es BANGS (Basic Needs in Games Scale), que mide autonomía,
  competencia y relación en escala Likert 1-5.
- La carga es re-ejecutable: `cargar_nucleo()` reconstruye las tablas del modelo a partir
  del staging cada vez que se ejecuta.
