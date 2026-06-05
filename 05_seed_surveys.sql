-- ================================================================
-- 05_seed_surveys.sql  -  Respuestas BANGS de los jugadores
-- 1 Answer_UX por usuario + 1 UXResponseItem por item (Likert 1-5).
-- Toma los usuarios y los items directamente de la base (sin IDs fijos);
-- el puntaje se genera de forma reproducible con setseed.
-- ================================================================
DO $$
DECLARE
  v_instr  UUID;
  v_user   RECORD;
  v_answer UUID;
  v_item   RECORD;
  n_users  INT := 0;
BEGIN
  SELECT instrument_id INTO v_instr FROM Instrument_UX WHERE name = 'BANGS';
  IF v_instr IS NULL THEN
    RAISE EXCEPTION 'Ejecuta 04_seed_bangs.sql primero (no existe el instrumento BANGS)';
  END IF;

  PERFORM setseed(0.42);

  FOR v_user IN SELECT id FROM "User" ORDER BY user_name LOOP
    INSERT INTO Answer_UX (user_id, instrument_id)
    VALUES (v_user.id, v_instr)
    ON CONFLICT (user_id, instrument_id) DO NOTHING
    RETURNING answer_id INTO v_answer;

    IF v_answer IS NULL THEN
      SELECT answer_id INTO v_answer
      FROM Answer_UX WHERE user_id = v_user.id AND instrument_id = v_instr;
    END IF;

    FOR v_item IN
      SELECT item_id FROM Item_UX WHERE instrument_id = v_instr ORDER BY item_pos
    LOOP
      INSERT INTO UXResponseItem (answer_id, item_id, score)
      VALUES (v_answer, v_item.item_id, 1 + floor(random() * 5)::INT)
      ON CONFLICT (answer_id, item_id) DO NOTHING;
    END LOOP;

    n_users := n_users + 1;
  END LOOP;

  RAISE NOTICE 'Encuestas BANGS insertadas para % usuarios', n_users;
END $$;
