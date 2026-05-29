-- ================================================================
-- Chocolate-Doom Telemetry & UX Database
-- 01_schema.sql  –  Extensions · ENUMs · Tables · Indexes
-- PostgreSQL >= 14
-- ================================================================

-- ── Extensions ──────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── ENUM types ───────────────────────────────────────────────────
DO $$ BEGIN
    CREATE TYPE user_genre AS ENUM ('male','female','non_binary','prefer_not_to_say');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE level_exp AS ENUM ('beginner','intermediate','advanced','expert');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE game_state AS ENUM ('active','finished','abandoned');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ================================================================
-- CORE TABLES
-- ================================================================

-- Voluntario real; consent_given es requisito ético obligatorio
CREATE TABLE IF NOT EXISTS "User" (
    id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_name         TEXT        NOT NULL,
    user_genre        user_genre,
    user_level_of_exp level_exp,
    time_of_creation  TIMESTAMP   NOT NULL DEFAULT NOW(),
    consent_given     BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_user_consent CHECK (consent_given = TRUE)
);

-- Perfil en el juego; relación 1:1 con User (UNIQUE en user_id)
CREATE TABLE IF NOT EXISTS Player (
    player_id    UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID  NOT NULL REFERENCES "User"(id) ON DELETE CASCADE,
    player_name  TEXT  NOT NULL,
    UNIQUE (user_id)
);

-- Mapa de Doom: Episode → Map (→ Sector)
CREATE TABLE IF NOT EXISTS Map (
    id_map    UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    episode   INT   NOT NULL CHECK (episode > 0),
    map_code  TEXT,
    map_name  TEXT,
    wide      INT   CHECK (wide > 0),
    length    INT   CHECK (length > 0),
    UNIQUE (episode, map_code)
);

-- Región geométrica del motor (no cuadrícula)
CREATE TABLE IF NOT EXISTS Sector (
    sector_id   UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    map_id      UUID  NOT NULL REFERENCES Map(id_map) ON DELETE RESTRICT,
    sector_code TEXT  NOT NULL,
    descri      TEXT,
    UNIQUE (map_id, sector_code)
);

-- Sesión de juego completa
CREATE TABLE IF NOT EXISTS Game (
    game_id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    map_id           UUID        NOT NULL REFERENCES Map(id_map) ON DELETE RESTRICT,
    state            game_state  NOT NULL DEFAULT 'active',
    start_timestamp  TIMESTAMP   NOT NULL DEFAULT NOW(),
    end_timestamp    TIMESTAMP,
    CONSTRAINT chk_game_times
        CHECK (end_timestamp IS NULL OR end_timestamp > start_timestamp)
);

-- Tabla puente Player ↔ Game (N:M); guarda tiempos de entrada/salida
CREATE TABLE IF NOT EXISTS GameParticipant (
    participant_id  UUID       PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id         UUID       NOT NULL REFERENCES Game(game_id)   ON DELETE CASCADE,
    player_id       UUID       NOT NULL REFERENCES Player(player_id) ON DELETE RESTRICT,
    join_time       TIMESTAMP  NOT NULL DEFAULT NOW(),
    leave_time      TIMESTAMP,
    UNIQUE (game_id, player_id)
);

-- Registro atómico de telemetría: 1 jugador, 1 tic, 1 partida
-- UNIQUE(participant_id, tic) garantiza deduplicación
CREATE TABLE IF NOT EXISTS Telemetry_event (
    tel_id          UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    participant_id  UUID      NOT NULL REFERENCES GameParticipant(participant_id) ON DELETE CASCADE,
    sector_id       UUID      REFERENCES Sector(sector_id) ON DELETE SET NULL,
    tic             INT       NOT NULL CHECK (tic > 0),
    pos_x           FLOAT     NOT NULL,
    pos_y           FLOAT     NOT NULL,
    pos_z           FLOAT     NOT NULL DEFAULT 0,
    angulo          FLOAT     CHECK (angulo >= 0 AND angulo < 360),
    momentum_x      FLOAT,
    momentum_y      FLOAT,
    momentum_z      FLOAT,
    fov             FLOAT,
    salud           INT       CHECK (salud    >= 0 AND salud    <= 200),
    armadura        INT       CHECK (armadura >= 0 AND armadura <= 200),
    municion        INT       CHECK (municion >= 0 AND municion <= 999),
    registered_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (participant_id, tic)
);

-- Metadatos del instrumento UX (PENS / GUESS / BANGS)
CREATE TABLE IF NOT EXISTS Instrument_UX (
    instrument_id  UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    name           VARCHAR(64)  NOT NULL UNIQUE,
    version        TEXT,
    description    TEXT,
    min            INT,
    max            INT,
    CHECK (min < max)
);

-- Cada pregunta individual del instrumento
CREATE TABLE IF NOT EXISTS Item_UX (
    item_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    instrument_id  UUID         NOT NULL REFERENCES Instrument_UX(instrument_id) ON DELETE CASCADE,
    item_pos       INT          NOT NULL CHECK (item_pos > 0),
    item_text      TEXT         NOT NULL,
    subscale       VARCHAR(64),
    UNIQUE (instrument_id, item_pos)
);

-- "Cuadernillo" respondido: un usuario, un instrumento, una fecha
CREATE TABLE IF NOT EXISTS Answer_UX (
    answer_id      UUID       PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id        UUID       NOT NULL REFERENCES "User"(id) ON DELETE CASCADE,
    instrument_id  UUID       NOT NULL REFERENCES Instrument_UX(instrument_id) ON DELETE RESTRICT,
    ended          TIMESTAMP  NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, instrument_id)
);

-- Puntuación de cada ítem dentro de un Answer_UX
CREATE TABLE IF NOT EXISTS UXResponseItem (
    response_item_id  UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    answer_id         UUID  NOT NULL REFERENCES Answer_UX(answer_id) ON DELETE CASCADE,
    item_id           UUID  NOT NULL REFERENCES Item_UX(item_id)     ON DELETE RESTRICT,
    score             INT   NOT NULL,
    UNIQUE (answer_id, item_id)
);

-- ================================================================
-- INDEXES  (para consultas analíticas del enunciado)
-- ================================================================

-- Q3/Q8: reconstrucción de trayectorias ordenadas por tic
CREATE INDEX IF NOT EXISTS idx_tel_participant_tic
    ON Telemetry_event (participant_id, tic);

-- Q5/Q6: hotspot y co-presencia por sector
CREATE INDEX IF NOT EXISTS idx_tel_sector
    ON Telemetry_event (sector_id);

-- Q2: proximidad espacial (self-join por posición)
CREATE INDEX IF NOT EXISTS idx_tel_pos_xy
    ON Telemetry_event (pos_x, pos_y);

-- Lookup de partidas por jugador
CREATE INDEX IF NOT EXISTS idx_gp_player_game
    ON GameParticipant (player_id, game_id);

-- Lookup de sesiones por mapa (Q1)
CREATE INDEX IF NOT EXISTS idx_game_map
    ON Game (map_id);

-- Lookup de respuestas UX por usuario
CREATE INDEX IF NOT EXISTS idx_answer_user
    ON Answer_UX (user_id);
