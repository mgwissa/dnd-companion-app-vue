-- ============================================================
-- Add HP tracking columns to characters
-- ============================================================

ALTER TABLE characters ADD COLUMN max_hp     integer NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN current_hp integer NOT NULL DEFAULT 0;


-- ============================================================
-- RPC: safely update HP for any character in your campaign.
-- Uses SECURITY DEFINER so campaign members can update HP
-- on each other's characters without opening a broad UPDATE policy.
-- ============================================================

CREATE OR REPLACE FUNCTION update_character_hp(
  p_character_id uuid,
  p_current_hp   integer,
  p_max_hp       integer DEFAULT NULL
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

  IF p_max_hp IS NOT NULL THEN
    UPDATE characters
    SET current_hp = p_current_hp,
        max_hp     = p_max_hp,
        updated_at = now()
    WHERE id = p_character_id;
  ELSE
    UPDATE characters
    SET current_hp = p_current_hp,
        updated_at = now()
    WHERE id = p_character_id;
  END IF;
END;
$$;
