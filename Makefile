DB ?= chocodoom
PSQL = psql -v ON_ERROR_STOP=1 -d $(DB)

.PHONY: all db schema load index clean
all: load
db:
	-createdb $(DB)
schema: db
	$(PSQL) -f 01_schema.sql
	$(PSQL) -f 02_etl.sql
load: schema
	$(PSQL) -f 03_load_telemetry.sql
	$(PSQL) -f 04_seed_bangs.sql
	$(PSQL) -f 05_seed_surveys.sql
	$(PSQL) -f 06_analytics.sql
index:
	$(PSQL) -f 07_index_eval.sql
clean:
	-dropdb $(DB)
