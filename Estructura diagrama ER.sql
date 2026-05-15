CREATE TABLE "User" (
  "user_id" uuid PRIMARY KEY,
  "user_name" text,
  "user_gender" text,
  "user_level_of_exp" text,
  "time_of_creation" timestamp
);

CREATE TABLE "Player" (
  "player_id" uuid PRIMARY KEY,
  "user_id" uuid,
  "player_name" text
);

CREATE TABLE "GameParticipant" (
  "participant_id" uuid PRIMARY KEY,
  "game_id" uuid,
  "player_id" uuid,
  "join_time" timestamp,
  "leave_time" timestamp
);

CREATE TABLE "Game" (
  "game_id" uuid PRIMARY KEY,
  "map_id" uuid,
  "state" varchar(32),
  "start" timestamp,
  "end" timestamp
);

CREATE TABLE "Map" (
  "map_id" uuid PRIMARY KEY,
  "episode" int,
  "map_code" text,
  "map_name" text,
  "width" int,
  "length" int,
  "end" timestamp
);

CREATE TABLE "Sector" (
  "sector_id" uuid PRIMARY KEY,
  "map_id" uuid,
  "sector_code" text,
  "descri" text
);

CREATE TABLE "Telemetry_event" (
  "tel_id" uuid PRIMARY KEY,
  "participant_id" uuid,
  "sector_id" uuid,
  "tic" int,
  "pos_x" float,
  "pos_y" float,
  "pos_z" float,
  "angle" float,
  "momentum_x" float,
  "momentum_y" float,
  "momentum_z" float,
  "fov" float,
  "health" int,
  "armor" int,
  "ammo" int,
  "registered_at" timestamp
);

CREATE TABLE "Instrument_UX" (
  "instrument_id" uuid PRIMARY KEY,
  "name" varchar(64),
  "version" text,
  "description" text,
  "min" int,
  "max" int
);

CREATE TABLE "Item_UX" (
  "item_id" uuid PRIMARY KEY,
  "instrument_id" uuid,
  "item_pos" int,
  "item_text" text,
  "subscale" varchar(64)
);

CREATE TABLE "Answer_UX" (
  "answer_id" uuid PRIMARY KEY,
  "user_id" uuid,
  "instrument_id" uuid,
  "ended" timestamp
);

CREATE TABLE "UXResponseItem" (
  "response_item_id" uuid PRIMARY KEY,
  "answer_id" uuid,
  "item_id" uuid,
  "score" int
);

ALTER TABLE "Player" ADD FOREIGN KEY ("user_id") REFERENCES "User" ("user_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "GameParticipant" ADD FOREIGN KEY ("game_id") REFERENCES "Game" ("game_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "GameParticipant" ADD FOREIGN KEY ("player_id") REFERENCES "Player" ("player_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Game" ADD FOREIGN KEY ("map_id") REFERENCES "Map" ("map_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Sector" ADD FOREIGN KEY ("map_id") REFERENCES "Map" ("map_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Telemetry_event" ADD FOREIGN KEY ("participant_id") REFERENCES "GameParticipant" ("participant_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Telemetry_event" ADD FOREIGN KEY ("sector_id") REFERENCES "Sector" ("sector_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Item_UX" ADD FOREIGN KEY ("instrument_id") REFERENCES "Instrument_UX" ("instrument_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Answer_UX" ADD FOREIGN KEY ("user_id") REFERENCES "User" ("user_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "Answer_UX" ADD FOREIGN KEY ("instrument_id") REFERENCES "Instrument_UX" ("instrument_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UXResponseItem" ADD FOREIGN KEY ("answer_id") REFERENCES "Answer_UX" ("answer_id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "UXResponseItem" ADD FOREIGN KEY ("item_id") REFERENCES "Item_UX" ("item_id") DEFERRABLE INITIALLY IMMEDIATE;
