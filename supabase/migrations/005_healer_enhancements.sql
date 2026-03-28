-- ============================================================
-- 1. New columns on characters
-- ============================================================

ALTER TABLE characters ADD COLUMN temp_hp integer NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN is_npc  boolean NOT NULL DEFAULT false;


-- ============================================================
-- 2. Replace the HP update RPC to also handle temp_hp
--    Drop the old 3-param signature first to avoid overload
-- ============================================================

DROP FUNCTION IF EXISTS update_character_hp(uuid, integer, integer);

CREATE OR REPLACE FUNCTION update_character_hp(
  p_character_id uuid,
  p_current_hp   integer,
  p_max_hp       integer DEFAULT NULL,
  p_temp_hp      integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_campaign_id uuid;
BEGIN
  SELECT campaign_id INTO v_campaign_id
  FROM characters
  WHERE id = p_character_id;

  IF v_campaign_id IS NULL THEN
    RAISE EXCEPTION 'Character not found';
  END IF;

  IF NOT is_campaign_member(v_campaign_id) THEN
    RAISE EXCEPTION 'Not a campaign member';
  END IF;

  UPDATE characters
  SET current_hp = p_current_hp,
      max_hp     = COALESCE(p_max_hp, max_hp),
      temp_hp    = COALESCE(p_temp_hp, temp_hp),
      updated_at = now()
  WHERE id = p_character_id;
END;
$$;


-- ============================================================
-- 3. RPC: create a manually-added character on the healer page
-- ============================================================

CREATE OR REPLACE FUNCTION create_healer_character(
  p_campaign_id    uuid,
  p_character_name text,
  p_max_hp         integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_campaign_member(p_campaign_id) THEN
    RAISE EXCEPTION 'Not a campaign member';
  END IF;

  INSERT INTO characters (
    user_id, campaign_id, character_name,
    max_hp, current_hp, is_active, is_npc
  )
  VALUES (
    auth.uid(), p_campaign_id, p_character_name,
    p_max_hp, p_max_hp, true, true
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;


-- ============================================================
-- 4. RPC: delete a manually-added character (safety: only is_npc)
-- ============================================================

CREATE OR REPLACE FUNCTION delete_healer_character(p_character_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_campaign_id uuid;
  v_is_npc      boolean;
BEGIN
  SELECT campaign_id, is_npc INTO v_campaign_id, v_is_npc
  FROM characters
  WHERE id = p_character_id;

  IF v_campaign_id IS NULL THEN
    RAISE EXCEPTION 'Character not found';
  END IF;

  IF NOT is_campaign_member(v_campaign_id) THEN
    RAISE EXCEPTION 'Not a campaign member';
  END IF;

  IF NOT v_is_npc THEN
    RAISE EXCEPTION 'Can only delete manually-added characters';
  END IF;

  DELETE FROM characters WHERE id = p_character_id;
END;
$$;
