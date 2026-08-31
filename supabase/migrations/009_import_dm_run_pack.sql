-- Import a versioned DM content pack as one transaction. If any scene,
-- encounter, or combatant is invalid, the complete import is rolled back.

create or replace function import_dm_run_pack(p_campaign_id uuid, p_pack jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_note_id uuid;
  v_scene_id uuid;
  v_encounter_id uuid;
  v_scene_ids jsonb := '{}'::jsonb;
  v_scene jsonb;
  v_encounter jsonb;
  v_combatant jsonb;
  v_title text;
  v_overview text;
  v_scene_key text;
  v_kind text;
  v_planned_minutes integer;
  v_estimated_minutes integer;
  v_max_hp integer;
  v_current_hp integer;
  v_temp_hp integer;
  v_scene_count integer := 0;
  v_combatant_count integer;
begin
  if auth.uid() is null or not is_campaign_dm(p_campaign_id) then
    raise exception 'Only the campaign owner can import a DM run sheet';
  end if;

  if jsonb_typeof(p_pack) <> 'object' then
    raise exception 'Content pack must be a JSON object';
  end if;

  if coalesce((p_pack ->> 'version')::integer, 0) <> 1 then
    raise exception 'Unsupported content pack version';
  end if;

  if jsonb_typeof(p_pack -> 'run') <> 'object' then
    raise exception 'Content pack is missing run details';
  end if;

  if jsonb_typeof(p_pack -> 'scenes') <> 'array'
     or jsonb_array_length(p_pack -> 'scenes') = 0 then
    raise exception 'Content pack must include at least one scene';
  end if;

  if exists (
    select 1 from dm_runs
    where campaign_id = p_campaign_id and status in ('prep', 'running')
  ) then
    raise exception 'Complete the current DM run before importing another';
  end if;

  v_title := nullif(trim(p_pack #>> '{run,title}'), '');
  if v_title is null then
    raise exception 'Run title is required';
  end if;

  v_planned_minutes := case
    when jsonb_typeof(p_pack #> '{run,plannedMinutes}') = 'number'
      then (p_pack #>> '{run,plannedMinutes}')::integer
    else 180
  end;
  v_planned_minutes := greatest(15, least(720, v_planned_minutes));
  v_overview := coalesce(nullif(trim(p_pack #>> '{run,overview}'), ''), 'Imported DM run sheet.');

  insert into notes (user_id, campaign_id, title, body, tags, is_shared)
  values (
    auth.uid(),
    p_campaign_id,
    v_title || ' — DM briefing',
    '# ' || v_title || E'\n\n' || v_overview,
    array['dm-briefing', 'content-pack'],
    false
  )
  returning id into v_note_id;

  insert into dm_runs (
    campaign_id, created_by, title, planned_minutes, log_note_id
  )
  values (
    p_campaign_id, auth.uid(), v_title, v_planned_minutes, v_note_id
  )
  returning id into v_run_id;

  for v_scene in
    select value from jsonb_array_elements(p_pack -> 'scenes')
  loop
    v_scene_key := nullif(trim(v_scene ->> 'key'), '');
    if v_scene_key is null then
      raise exception 'Every scene needs a stable key';
    end if;
    if v_scene_ids ? v_scene_key then
      raise exception 'Duplicate scene key: %', v_scene_key;
    end if;
    if nullif(trim(v_scene ->> 'title'), '') is null then
      raise exception 'Every scene needs a title';
    end if;

    v_estimated_minutes := case
      when jsonb_typeof(v_scene -> 'estimatedMinutes') = 'number'
        then (v_scene ->> 'estimatedMinutes')::integer
      else 20
    end;
    v_estimated_minutes := greatest(0, least(480, v_estimated_minutes));

    insert into dm_scenes (
      run_id,
      campaign_id,
      created_by,
      title,
      purpose,
      read_aloud,
      secrets,
      notes,
      estimated_minutes,
      sort_order
    )
    values (
      v_run_id,
      p_campaign_id,
      auth.uid(),
      trim(v_scene ->> 'title'),
      coalesce(v_scene ->> 'purpose', ''),
      coalesce(v_scene ->> 'readAloud', ''),
      coalesce(v_scene ->> 'secrets', ''),
      coalesce(v_scene ->> 'notes', ''),
      v_estimated_minutes,
      v_scene_count
    )
    returning id into v_scene_id;

    v_scene_ids := jsonb_set(v_scene_ids, array[v_scene_key], to_jsonb(v_scene_id::text));
    v_scene_count := v_scene_count + 1;
  end loop;

  if p_pack ? 'encounters' and jsonb_typeof(p_pack -> 'encounters') <> 'array' then
    raise exception 'Encounters must be a JSON array';
  end if;

  for v_encounter in
    select value from jsonb_array_elements(coalesce(p_pack -> 'encounters', '[]'::jsonb))
  loop
    if nullif(trim(v_encounter ->> 'title'), '') is null then
      raise exception 'Every encounter needs a title';
    end if;

    v_scene_key := nullif(trim(v_encounter ->> 'sceneKey'), '');
    v_scene_id := null;
    if v_scene_key is not null then
      if not (v_scene_ids ? v_scene_key) then
        raise exception 'Encounter references unknown scene key: %', v_scene_key;
      end if;
      v_scene_id := (v_scene_ids ->> v_scene_key)::uuid;
    end if;

    insert into dm_encounters (
      run_id, scene_id, campaign_id, created_by, title
    )
    values (
      v_run_id,
      v_scene_id,
      p_campaign_id,
      auth.uid(),
      trim(v_encounter ->> 'title')
    )
    returning id into v_encounter_id;

    if v_encounter ? 'combatants'
       and jsonb_typeof(v_encounter -> 'combatants') <> 'array' then
      raise exception 'Encounter combatants must be a JSON array';
    end if;

    v_combatant_count := 0;
    for v_combatant in
      select value from jsonb_array_elements(coalesce(v_encounter -> 'combatants', '[]'::jsonb))
    loop
      if nullif(trim(v_combatant ->> 'name'), '') is null then
        raise exception 'Every combatant needs a name';
      end if;

      v_kind := coalesce(nullif(v_combatant ->> 'kind', ''), 'enemy');
      if v_kind not in ('pc', 'enemy', 'ally') then
        raise exception 'Unsupported combatant kind: %', v_kind;
      end if;

      v_max_hp := case
        when jsonb_typeof(v_combatant -> 'maxHp') = 'number'
          then (v_combatant ->> 'maxHp')::integer
        else 1
      end;
      v_max_hp := greatest(0, v_max_hp);
      v_current_hp := case
        when jsonb_typeof(v_combatant -> 'currentHp') = 'number'
          then (v_combatant ->> 'currentHp')::integer
        else v_max_hp
      end;
      v_current_hp := greatest(0, v_current_hp);
      v_temp_hp := case
        when jsonb_typeof(v_combatant -> 'tempHp') = 'number'
          then (v_combatant ->> 'tempHp')::integer
        else 0
      end;
      v_temp_hp := greatest(0, v_temp_hp);

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
