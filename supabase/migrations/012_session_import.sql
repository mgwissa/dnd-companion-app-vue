-- Reviewed session notes and private source transcripts. Apply before deploying the UI.
alter table public.notes add column if not exists note_type text not null default 'note'
  check (note_type in ('note', 'session', 'transcript'));
alter table public.notes add column if not exists played_on date;
alter table public.notes add column if not exists resume_point text not null default '';
alter table public.notes add column if not exists session_import_key text;
alter table public.notes add column if not exists parent_session_id uuid references public.notes(id) on delete cascade;

create unique index if not exists notes_session_import_key_idx
  on public.notes (campaign_id, user_id, session_import_key)
  where session_import_key is not null;
create index if not exists notes_session_date_idx
  on public.notes (campaign_id, played_on desc nulls last, created_at desc)
  where note_type = 'session';

-- A source transcript cannot accidentally be published with the recap.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notes_transcript_private' and conrelid = 'public.notes'::regclass) then
    alter table public.notes add constraint notes_transcript_private
      check (note_type <> 'transcript' or is_shared = false);
  end if;
end $$;

create or replace function public.import_session_pack(p_campaign_id uuid, p_pack jsonb, p_shared boolean default false)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_note_id uuid;
  v_thread text;
  v_key text;
begin
  if auth.uid() is null or not is_campaign_member(p_campaign_id) then
    raise exception 'Join this campaign before importing a session';
  end if;
  if p_pack is null or jsonb_typeof(p_pack) <> 'object'
    or p_pack ->> 'kind' is distinct from 'dnd-session'
    or p_pack ->> 'version' is distinct from '1' then
    raise exception 'Unsupported session file';
  end if;
  foreach v_key in array array['id', 'title', 'resumePoint', 'recap', 'body'] loop
    if jsonb_typeof(p_pack -> v_key) is distinct from 'string' or trim(p_pack ->> v_key) = '' then
      raise exception 'Session % is required', v_key;
    end if;
  end loop;
  if (p_pack ->> 'playedOn') is not null and (
    (p_pack ->> 'playedOn') !~ '^\d{4}-\d{2}-\d{2}$'
    or ((p_pack ->> 'playedOn')::date)::text <> p_pack ->> 'playedOn'
  ) then
    raise exception 'Invalid played date';
  end if;
  if jsonb_typeof(p_pack -> 'selectedThreads') is distinct from 'array' then
    raise exception 'Selected threads must be an array';
  end if;
  if exists (select 1 from jsonb_array_elements(p_pack -> 'selectedThreads') t where jsonb_typeof(t) <> 'string') then
    raise exception 'Threads must be text';
  end if;
  if p_pack ? 'transcript' and jsonb_typeof(p_pack -> 'transcript') <> 'string' then
    raise exception 'Transcript must be text';
  end if;

  insert into notes (campaign_id, user_id, title, body, tags, is_shared, note_type, played_on, resume_point, session_import_key)
  values (p_campaign_id, auth.uid(), trim(p_pack ->> 'title'), p_pack ->> 'body', array['session'],
    coalesce(p_shared, false), 'session', (p_pack ->> 'playedOn')::date, trim(p_pack ->> 'resumePoint'), trim(p_pack ->> 'id'))
  returning id into v_note_id;

  if coalesce(p_pack ->> 'transcript', '') <> '' then
    insert into notes (campaign_id, user_id, title, body, tags, is_shared, note_type, parent_session_id)
    values (p_campaign_id, auth.uid(), (p_pack ->> 'title') || ' — source transcript',
      p_pack ->> 'transcript', array['transcript'], false, 'transcript', v_note_id);
  end if;

  for v_thread in select distinct trim(value) from jsonb_array_elements_text(p_pack -> 'selectedThreads') loop
    if v_thread <> '' and not exists (
      select 1 from campaign_threads where campaign_id = p_campaign_id and not is_done and lower(trim(title)) = lower(v_thread)
    ) then
      insert into campaign_threads(campaign_id, created_by, title) values (p_campaign_id, auth.uid(), v_thread);
    end if;
  end loop;
  return v_note_id;
end;
$$;

revoke all on function public.import_session_pack(uuid, jsonb, boolean) from public;
grant execute on function public.import_session_pack(uuid, jsonb, boolean) to authenticated;

-- A random, revocable bearer link exposes only a reviewed session projection.
alter table public.notes add column if not exists recap_share_token uuid;
create unique index if not exists notes_recap_share_token_idx on public.notes(recap_share_token)
  where recap_share_token is not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notes_only_session_share_link' and conrelid = 'public.notes'::regclass) then
    alter table public.notes add constraint notes_only_session_share_link
      check (recap_share_token is null or note_type = 'session');
  end if;
end $$;

create or replace function public.get_shared_recap(p_token uuid)
returns table (title text, body text, resume_point text, played_on date)
language sql
stable
security definer
set search_path = public
as $$
  select n.title, n.body, n.resume_point, n.played_on
  from public.notes n
  where n.recap_share_token = p_token and n.note_type = 'session';
$$;
revoke all on function public.get_shared_recap(uuid) from public;
grant execute on function public.get_shared_recap(uuid) to anon, authenticated;
