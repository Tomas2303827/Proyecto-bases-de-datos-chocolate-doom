-- ================================================================
-- Chocolate-Doom Telemetry & UX Database
-- 04_seed_bangs.sql  –  Instrumento BANGS (open-access)
-- ================================================================
-- BANGS: Basic Needs in Games Scale
-- Martínez et al., 2020  |  9 ítems  |  Likert 1–5
-- Subescalas: Autonomy (AUT) · Competence (COM) · Relatedness (REL)
-- Se eligió BANGS por ser de acceso abierto (requisito del proyecto).
-- ================================================================

INSERT INTO Instrument_UX (instrument_id, name, version, description, min, max)
VALUES (
    uuid_generate_v4(),
    'BANGS',
    '1.0',
    'Basic Needs in Games Scale. Mide la satisfacción de las necesidades psicológicas básicas '
    '(Autonomía, Competencia, Relación) en contextos de juego, basado en la Teoría de la '
    'Autodeterminación (SDT). Instrumento de acceso abierto.',
    1, 5
);

-- ── Insertar los 9 ítems ─────────────────────────────────────────
DO $$
DECLARE
    v_instrument UUID;
BEGIN
    SELECT instrument_id INTO v_instrument
    FROM Instrument_UX WHERE name = 'BANGS';

    INSERT INTO Item_UX (instrument_id, item_pos, item_text, subscale) VALUES

    -- Autonomía (AUT): sentido de libre elección en el juego
    (v_instrument, 1,
     'Sentí que podía jugar a mi manera, de forma libre.',
     'Autonomy'),
    (v_instrument, 2,
     'Sentí que me obligaban a seguir un camino específico mientras jugaba. (R)',
     'Autonomy'),
    (v_instrument, 3,
     'Pude tomar decisiones significativas sobre cómo jugar.',
     'Autonomy'),

    -- Competencia (COM): sensación de eficacia y logro
    (v_instrument, 4,
     'Me sentí capaz y efectivo/a mientras jugaba.',
     'Competence'),
    (v_instrument, 5,
     'Sentí que era habilidoso/a en este juego.',
     'Competence'),
    (v_instrument, 6,
     'Experimenté una sensación de logro durante la partida.',
     'Competence'),

    -- Relación (REL): conexión con otros jugadores
    (v_instrument, 7,
     'Me sentí conectado/a con los demás jugadores mientras jugaba.',
     'Relatedness'),
    (v_instrument, 8,
     'Sentí que los jugadores con quienes participé me entendían y reconocían.',
     'Relatedness'),
    (v_instrument, 9,
     'Experimenté un sentido de pertenencia mientras jugaba.',
     'Relatedness');

    RAISE NOTICE 'BANGS insertado: 9 ítems en 3 subescalas (instrument_id: %)', v_instrument;
END $$;
