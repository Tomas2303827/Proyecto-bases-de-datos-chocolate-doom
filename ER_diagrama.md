# Diagrama Entidad-Relacion — Chocolate-Doom Telemetry & UX

GitHub renderiza este diagrama automaticamente al abrir el archivo.

```mermaid
erDiagram
  USER ||--|| PLAYER : tiene
  USER ||--o{ ANSWER_UX : responde
  MAP ||--o{ SECTOR : contiene
  MAP ||--o{ GAME : escenario
  PLAYER ||--o{ GAMEPARTICIPANT : participa
  GAME ||--o{ GAMEPARTICIPANT : reune
  GAMEPARTICIPANT ||--o{ TELEMETRY_EVENT : registra
  INSTRUMENT_UX ||--o{ ITEM_UX : compone
  INSTRUMENT_UX ||--o{ ANSWER_UX : aplica
  ANSWER_UX ||--o{ UXRESPONSEITEM : detalla
  ITEM_UX ||--o{ UXRESPONSEITEM : puntua
  USER {
    uuid id PK
    text user_name
    user_genre user_genre
    level_exp user_level_of_exp
    timestamp time_of_creation
    bool consent_given
  }
  PLAYER {
    uuid player_id PK
    uuid user_id FK "UNIQUE -> 1:1 con USER"
    text player_name
  }
  MAP {
    uuid id_map PK
    int episode
    text map_code
    text map_name
    int wide
    int length
  }
  SECTOR {
    uuid sector_id PK
    uuid map_id FK
    text sector_code
    text descri
  }
  GAME {
    uuid game_id PK
    uuid map_id FK
    game_state state
    timestamp start_timestamp
    timestamp end_timestamp
  }
  GAMEPARTICIPANT {
    uuid participant_id PK
    uuid game_id FK
    uuid player_id FK
    timestamp join_time
    timestamp leave_time
  }
  TELEMETRY_EVENT {
    uuid tel_id PK
    uuid participant_id FK
    int tic
    float pos_x
    float pos_y
    float pos_z
    float angulo
    int salud
    int armadura
    int municion
  }
  INSTRUMENT_UX {
    uuid instrument_id PK
    varchar name
    text version
    int min
    int max
  }
  ITEM_UX {
    uuid item_id PK
    uuid instrument_id FK
    int item_pos
    text item_text
    varchar subscale
  }
  ANSWER_UX {
    uuid answer_id PK
    uuid user_id FK
    uuid instrument_id FK
    timestamp ended
  }
  UXRESPONSEITEM {
    uuid response_item_id PK
    uuid answer_id FK
    uuid item_id FK
    int score
  }
```

## Notas de cardinalidad
- `USER 1—1 PLAYER`: cada usuario tiene un unico perfil de jugador (`UNIQUE(user_id)` en Player).
- `MAP 1—N SECTOR` y `MAP 1—N GAME`: un mapa agrupa muchos sectores y se juega en muchas partidas.
- `GAME 1—N GAMEPARTICIPANT` y `PLAYER 1—N GAMEPARTICIPANT`: tabla puente partida↔jugador (`UNIQUE(game_id, player_id)`).
- `GAMEPARTICIPANT 1—N TELEMETRY_EVENT`: cada participacion genera muchos eventos (`UNIQUE(participant_id, tic)` evita duplicados).
- `SECTOR` ya **no** se conecta con `TELEMETRY_EVENT`. El "sector" para el analisis de hotspots (Q5) es una celda 250x250 calculada desde `pos_x`/`pos_y`; `SECTOR` queda como catalogo de geografia estatica ligado solo a `MAP`.
- Bloque UX: `INSTRUMENT_UX 1—N ITEM_UX`, `INSTRUMENT_UX 1—N ANSWER_UX`, y `UXRESPONSEITEM` cruza `ANSWER_UX` con `ITEM_UX` (`UNIQUE(answer_id, item_id)`).
