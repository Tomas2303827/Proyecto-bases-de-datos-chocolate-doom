#!/usr/bin/env bash
# Crea el esquema y carga todos los datos. Uso: ./run.sh [nombre_db]
# Ejecutar desde la raiz del repo (alli debe estar telemetria_limpia.csv).
set -euo pipefail
DB="${1:-chocodoom}"
PSQL="psql -v ON_ERROR_STOP=1 -d $DB"
echo ">> Creando base $DB (si no existe)"
createdb "$DB" 2>/dev/null || true
for f in 01_schema.sql 02_etl.sql 03_load_telemetry.sql \
         04_seed_bangs.sql 05_seed_surveys.sql 06_analytics.sql; do
  echo ">> Ejecutando $f"
  $PSQL -f "$f"
done
echo ">> LISTO. Opcional:"
echo "   $PSQL -f 07_index_eval.sql   # EXPLAIN ANALYZE antes/despues"
