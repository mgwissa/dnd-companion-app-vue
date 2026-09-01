-- Give encounters a reusable run reference and support replacing their authored
-- JSON in one transaction while preserving roster-linked player combatants.

alter table dm_encounters
  add column if not exists notes text not null default '';

create or replace function update_dm_encounter_from_json(
  p_encounter_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_campaign_id uuid;
  v_scene_id uuid;
  v_combatant jsonb;
  v_kind text;
  v_name text;
  v_max_hp integer;
  v_current_hp integer;
  v_temp_hp integer;
  v_sort_order integer;
begin
  select run_id, campaign_id
    into v_run_id, v_campaign_id
  from dm_encounters
  where id = p_encounter_id;

  if not found then
    raise exception 'Encounter not found';
  end if;

  if auth.uid() is null or not is_campaign_dm(v_campaign_id) then
    raise exception 'Only the campaign owner can edit encounter JSON';
  end if;

  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Encounter JSON must be an object';
  end if;

  if jsonb_typeof(p_payload -> 'version') <> 'number'
     or (p_payload ->> 'version')::integer <> 1 then
    raise exception 'Unsupported encounter JSON version';
  end if;

  if nullif(trim(p_payload ->> 'title'), '') is null then
    raise exception 'Encounter title is required';
  end if;

  if p_payload ? 'notes' and jsonb_typeof(p_payload -> 'notes') <> 'string' then
    raise exception 'Encounter notes must be text';
  end if;

  v_scene_id := null;
  if p_payload ? 'sceneId'
     and jsonb_typeof(p_payload -> 'sceneId') not in ('null', 'string') then
    raise exception 'sceneId must be a scene ID or null';
  end if;

  if jsonb_typeof(p_payload -> 'sceneId') = 'string'
     and nullif(trim(p_payload ->> 'sceneId'), '') is not null then
    begin
      v_scene_id := trim(p_payload ->> 'sceneId')::uuid;
    exception when invalid_text_representation then
      raise exception 'sceneId must be a valid UUID';
    end;

    if not exists (
      select 1
      from dm_scenes
      where id = v_scene_id
        and run_id = v_run_id
        and campaign_id = v_campaign_id
    ) then
      raise exception 'sceneId does not belong to this run sheet';
    end if;
  end if;

  if jsonb_typeof(coalesce(p_payload -> 'combatants', '[]'::jsonb)) <> 'array' then
    raise exception 'Encounter combatants must be a JSON array';
  end if;

  update dm_encounters
  set title = trim(p_payload ->> 'title'),
      scene_id = v_scene_id,
      notes = coalesce(p_payload ->> 'notes', ''),
      updated_at = now()
  where id = p_encounter_id;

  delete from dm_combatants
  where encounter_id = p_encounter_id
    and source_character_id is null
    and kind in ('enemy', 'ally');

  select coalesce(max(sort_order), -1) + 1
    into v_sort_order
  from dm_combatants
  where encounter_id = p_encounter_id;

  for v_combatant in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'combatants', '[]'::jsonb))
  loop
    if jsonb_typeof(v_combatant) <> 'object' then
      raise exception 'Every combatant must be a JSON object';
    end if;

    v_name := nullif(trim(v_combatant ->> 'name'), '');
    if v_name is null then
      raise exception 'Every combatant needs a name';
    end if;

    v_kind := coalesce(nullif(v_combatant ->> 'kind', ''), 'enemy');
    if v_kind not in ('enemy', 'ally') then
      raise exception 'Encounter JSON may only author enemy and ally combatants';
    end if;

    if v_combatant ? 'initiative'
       and jsonb_typeof(v_combatant -> 'initiative') not in ('number', 'null') then
      raise exception 'Combatant initiative must be an integer or null';
    end if;
    if v_combatant ? 'armorClass'
       and jsonb_typeof(v_combatant -> 'armorClass') not in ('number', 'null') then
      raise exception 'Combatant armorClass must be an integer or null';
    end if;
    if v_combatant ? 'maxHp'
       and jsonb_typeof(v_combatant -> 'maxHp') <> 'number' then
      raise exception 'Combatant maxHp must be an integer';
    end if;
    if v_combatant ? 'currentHp'
       and jsonb_typeof(v_combatant -> 'currentHp') <> 'number' then
      raise exception 'Combatant currentHp must be an integer';
    end if;
    if v_combatant ? 'tempHp'
       and jsonb_typeof(v_combatant -> 'tempHp') <> 'number' then
      raise exception 'Combatant tempHp must be an integer';
    end if;
    if v_combatant ? 'conditions'
       and jsonb_typeof(v_combatant -> 'conditions') <> 'array' then
      raise exception 'Combatant conditions must be an array';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(
        coalesce(v_combatant -> 'conditions', '[]'::jsonb)
      ) as conditions(value)
      where jsonb_typeof(value) <> 'string'
    ) then
      raise exception 'Every combatant condition must be text';
    end if;

    v_max_hp := case
      when jsonb_typeof(v_combatant -> 'maxHp') = 'number'
        then greatest(0, (v_combatant ->> 'maxHp')::integer)
      else 1
    end;
    v_current_hp := case
      when jsonb_typeof(v_combatant -> 'currentHp') = 'number'
        then greatest(0, (v_combatant ->> 'currentHp')::integer)
      else v_max_hp
    end;
    v_temp_hp := case
      when jsonb_typeof(v_combatant -> 'tempHp') = 'number'
        then greatest(0, (v_combatant ->> 'tempHp')::integer)
      else 0
    end;

    insert into dm_combatants (
      encounter_id,
      campaign_id,
      name,
      kind,
      initiative,
      armor_class,
      max_hp,
      current_hp,
      temp_hp,
      conditions,
      sort_order
    )
    values (
      p_encounter_id,
      v_campaign_id,
      v_name,
      v_kind,
      case
        when jsonb_typeof(v_combatant -> 'initiative') = 'number'
          then (v_combatant ->> 'initiative')::integer
        else null
      end,
      case
        when jsonb_typeof(v_combatant -> 'armorClass') = 'number'
          then greatest(0, (v_combatant ->> 'armorClass')::integer)
        else null
      end,
      v_max_hp,
      v_current_hp,
      v_temp_hp,
      case
        when jsonb_typeof(v_combatant -> 'conditions') = 'array'
          then array(select jsonb_array_elements_text(v_combatant -> 'conditions'))
        else '{}'::text[]
      end,
      v_sort_order
    );

    v_sort_order := v_sort_order + 1;
  end loop;

  update dm_encounters
  set turn_index = least(
        turn_index,
        greatest((select count(*) from dm_combatants where encounter_id = p_encounter_id) - 1, 0)
      )
  where id = p_encounter_id;
end;
$$;

revoke all on function update_dm_encounter_from_json(uuid, jsonb) from public;
grant execute on function update_dm_encounter_from_json(uuid, jsonb) to authenticated;

-- Wrap the existing importer so databases that already applied migration 009
-- also retain encounter notes. The original import still performs validation;
-- this wrapper rebuilds its encounters with the authored reference attached.
alter function import_dm_run_pack(uuid, jsonb)
  rename to import_dm_run_pack_without_encounter_notes;

revoke all on function import_dm_run_pack_without_encounter_notes(uuid, jsonb) from public;
revoke all on function import_dm_run_pack_without_encounter_notes(uuid, jsonb) from authenticated;

create function import_dm_run_pack(p_campaign_id uuid, p_pack jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_scene_id uuid;
  v_encounter_id uuid;
  v_scene_ids jsonb := '{}'::jsonb;
  v_scene jsonb;
  v_encounter jsonb;
  v_combatant jsonb;
  v_scene_key text;
  v_kind text;
  v_max_hp integer;
  v_current_hp integer;
  v_temp_hp integer;
  v_scene_count integer := 0;
  v_combatant_count integer;
begin
  v_run_id := import_dm_run_pack_without_encounter_notes(p_campaign_id, p_pack);

  for v_scene in
    select value from jsonb_array_elements(p_pack -> 'scenes')
  loop
    select id
      into v_scene_id
    from dm_scenes
    where run_id = v_run_id and sort_order = v_scene_count
    limit 1;

    v_scene_key := trim(v_scene ->> 'key');
    v_scene_ids := jsonb_set(v_scene_ids, array[v_scene_key], to_jsonb(v_scene_id::text));
    v_scene_count := v_scene_count + 1;
  end loop;

  delete from dm_encounters where run_id = v_run_id;

  for v_encounter in
    select value from jsonb_array_elements(coalesce(p_pack -> 'encounters', '[]'::jsonb))
  loop
    v_scene_key := nullif(trim(v_encounter ->> 'sceneKey'), '');
    v_scene_id := case
      when v_scene_key is null then null
      else (v_scene_ids ->> v_scene_key)::uuid
    end;

    insert into dm_encounters (
      run_id,
      scene_id,
      campaign_id,
      created_by,
      title,
      notes
    )
    values (
      v_run_id,
      v_scene_id,
      p_campaign_id,
      auth.uid(),
      trim(v_encounter ->> 'title'),
      coalesce(v_encounter ->> 'notes', '')
    )
    returning id into v_encounter_id;

    v_combatant_count := 0;
    for v_combatant in
      select value
      from jsonb_array_elements(coalesce(v_encounter -> 'combatants', '[]'::jsonb))
    loop
      v_kind := coalesce(nullif(v_combatant ->> 'kind', ''), 'enemy');
      v_max_hp := case
        when jsonb_typeof(v_combatant -> 'maxHp') = 'number'
          then greatest(0, (v_combatant ->> 'maxHp')::integer)
        else 1
      end;
      v_current_hp := case
        when jsonb_typeof(v_combatant -> 'currentHp') = 'number'
          then greatest(0, (v_combatant ->> 'currentHp')::integer)
        else v_max_hp
      end;
      v_temp_hp := case
        when jsonb_typeof(v_combatant -> 'tempHp') = 'number'
          then greatest(0, (v_combatant ->> 'tempHp')::integer)
        else 0
      end;

      insert into dm_combatants (
        encounter_id,
        campaign_id,
        name,
        kind,
        initiative,
        armor_class,
        max_hp,
        current_hp,
        temp_hp,
        conditions,
        sort_order
      )
      values (
        v_encounter_id,
        p_campaign_id,
        trim(v_combatant ->> 'name'),
        v_kind,
        case
          when jsonb_typeof(v_combatant -> 'initiative') = 'number'
            then (v_combatant ->> 'initiative')::integer
          else null
        end,
        case
          when jsonb_typeof(v_combatant -> 'armorClass') = 'number'
            then greatest(0, (v_combatant ->> 'armorClass')::integer)
          else null
        end,
        v_max_hp,
        v_current_hp,
        v_temp_hp,
        case
          when jsonb_typeof(v_combatant -> 'conditions') = 'array'
            then array(select jsonb_array_elements_text(v_combatant -> 'conditions'))
          else '{}'::text[]
        end,
        v_combatant_count
      );

      v_combatant_count := v_combatant_count + 1;
    end loop;
  end loop;

  return v_run_id;
end;
$$;

revoke all on function import_dm_run_pack(uuid, jsonb) from public;
grant execute on function import_dm_run_pack(uuid, jsonb) to authenticated;
