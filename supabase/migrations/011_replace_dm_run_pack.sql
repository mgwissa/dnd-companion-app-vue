-- Replace an existing prepared run with a complete versioned content pack.
-- The delete and import share one transaction, so a failed import restores the
-- original run automatically.

create or replace function replace_dm_run_pack(p_run_id uuid, p_pack jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_status text;
  v_log_note_id uuid;
  v_new_run_id uuid;
begin
  select campaign_id, status, log_note_id
    into v_campaign_id, v_status, v_log_note_id
  from dm_runs
  where id = p_run_id;

  if not found then
    raise exception 'Run sheet not found';
  end if;

  if auth.uid() is null or not is_campaign_dm(v_campaign_id) then
    raise exception 'Only the campaign owner can replace a DM run sheet';
  end if;

  if v_status <> 'prep' then
    raise exception 'Only a run sheet in prep can be replaced from JSON';
  end if;

  delete from dm_runs where id = p_run_id;

  if v_log_note_id is not null then
    delete from notes
    where id = v_log_note_id
      and user_id = auth.uid()
      and campaign_id = v_campaign_id;
  end if;

  v_new_run_id := import_dm_run_pack(v_campaign_id, p_pack);
  return v_new_run_id;
end;
$$;

revoke all on function replace_dm_run_pack(uuid, jsonb) from public;
grant execute on function replace_dm_run_pack(uuid, jsonb) to authenticated;
