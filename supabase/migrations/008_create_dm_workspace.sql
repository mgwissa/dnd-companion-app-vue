-- ============================================================
-- DM workspace: persistent one-shot runs, scenes, encounters,
-- and initiative combatants. Every table is private to the
-- campaign owner at the database layer.
-- ============================================================

create or replace function is_campaign_dm(p_campaign_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from campaign_members
    where campaign_id = p_campaign_id
      and user_id = auth.uid()
      and role = 'owner'
  );
$$;

create table dm_runs (
  id              uuid default gen_random_uuid() primary key,
  campaign_id     uuid references campaigns(id) on delete cascade not null,
  created_by      uuid references auth.users(id) on delete cascade not null,
  title           text not null,
  planned_minutes integer not null default 240 check (planned_minutes between 15 and 720),
  status          text not null default 'prep' check (status in ('prep', 'running', 'completed')),
  started_at      timestamptz,
  ended_at        timestamptz,
  log_note_id     uuid references notes(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index dm_runs_campaign_idx on dm_runs (campaign_id, status, created_at desc);
create unique index dm_runs_one_open_per_campaign_idx
  on dm_runs (campaign_id)
  where status in ('prep', 'running');

create table dm_scenes (
  id                uuid default gen_random_uuid() primary key,
  run_id            uuid references dm_runs(id) on delete cascade not null,
  campaign_id       uuid references campaigns(id) on delete cascade not null,
  created_by        uuid references auth.users(id) on delete cascade not null,
  title             text not null,
  purpose           text not null default '',
  read_aloud        text not null default '',
  secrets           text not null default '',
  notes             text not null default '',
  estimated_minutes integer not null default 20 check (estimated_minutes between 0 and 480),
  sort_order        integer not null default 0,
  status            text not null default 'planned' check (status in ('planned', 'current', 'completed')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index dm_scenes_run_idx on dm_scenes (run_id, sort_order, created_at);

create table dm_encounters (
  id          uuid default gen_random_uuid() primary key,
  run_id      uuid references dm_runs(id) on delete cascade not null,
  scene_id    uuid references dm_scenes(id) on delete set null,
  campaign_id uuid references campaigns(id) on delete cascade not null,
  created_by  uuid references auth.users(id) on delete cascade not null,
  title       text not null,
  is_active   boolean not null default false,
  round       integer not null default 1 check (round >= 1),
  turn_index  integer not null default 0 check (turn_index >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index dm_encounters_run_idx on dm_encounters (run_id, created_at);

create table dm_combatants (
  id                  uuid default gen_random_uuid() primary key,
  encounter_id        uuid references dm_encounters(id) on delete cascade not null,
  campaign_id         uuid references campaigns(id) on delete cascade not null,
  source_character_id uuid references characters(id) on delete set null,
  name                text not null,
  kind                text not null default 'enemy' check (kind in ('pc', 'enemy', 'ally')),
  initiative          integer,
  armor_class         integer check (armor_class is null or armor_class >= 0),
  max_hp              integer not null default 1 check (max_hp >= 0),
  current_hp          integer not null default 1 check (current_hp >= 0),
  temp_hp             integer not null default 0 check (temp_hp >= 0),
  conditions          text[] not null default '{}',
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index dm_combatants_encounter_idx
  on dm_combatants (encounter_id, initiative desc nulls last, sort_order, created_at);

create or replace function dm_run_belongs_to_campaign(p_run_id uuid, p_campaign_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from dm_runs where id = p_run_id and campaign_id = p_campaign_id
  );
$$;

create or replace function dm_scene_belongs_to_run(p_scene_id uuid, p_run_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_scene_id is null or exists (
    select 1 from dm_scenes where id = p_scene_id and run_id = p_run_id
  );
$$;

create or replace function dm_encounter_belongs_to_campaign(p_encounter_id uuid, p_campaign_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from dm_encounters where id = p_encounter_id and campaign_id = p_campaign_id
  );
$$;

alter table dm_runs enable row level security;
alter table dm_scenes enable row level security;
alter table dm_encounters enable row level security;
alter table dm_combatants enable row level security;

create policy "DM can view runs"
  on dm_runs for select
  using (is_campaign_dm(campaign_id));

create policy "DM can create runs"
  on dm_runs for insert
  with check (created_by = auth.uid() and is_campaign_dm(campaign_id));

create policy "DM can update runs"
  on dm_runs for update
  using (is_campaign_dm(campaign_id))
  with check (is_campaign_dm(campaign_id));

create policy "DM can delete runs"
  on dm_runs for delete
  using (is_campaign_dm(campaign_id));

create policy "DM can view scenes"
  on dm_scenes for select
  using (is_campaign_dm(campaign_id));

create policy "DM can create scenes"
  on dm_scenes for insert
  with check (
    created_by = auth.uid()
    and is_campaign_dm(campaign_id)
    and dm_run_belongs_to_campaign(run_id, campaign_id)
  );

create policy "DM can update scenes"
  on dm_scenes for update
  using (is_campaign_dm(campaign_id))
  with check (
    is_campaign_dm(campaign_id)
    and dm_run_belongs_to_campaign(run_id, campaign_id)
  );

create policy "DM can delete scenes"
  on dm_scenes for delete
  using (is_campaign_dm(campaign_id));

create policy "DM can view encounters"
  on dm_encounters for select
  using (is_campaign_dm(campaign_id));

create policy "DM can create encounters"
  on dm_encounters for insert
  with check (
    created_by = auth.uid()
    and is_campaign_dm(campaign_id)
    and dm_run_belongs_to_campaign(run_id, campaign_id)
    and dm_scene_belongs_to_run(scene_id, run_id)
  );

create policy "DM can update encounters"
  on dm_encounters for update
  using (is_campaign_dm(campaign_id))
  with check (
    is_campaign_dm(campaign_id)
    and dm_run_belongs_to_campaign(run_id, campaign_id)
    and dm_scene_belongs_to_run(scene_id, run_id)
  );

create policy "DM can delete encounters"
  on dm_encounters for delete
  using (is_campaign_dm(campaign_id));

create policy "DM can view combatants"
  on dm_combatants for select
  using (is_campaign_dm(campaign_id));

create policy "DM can create combatants"
  on dm_combatants for insert
  with check (
    is_campaign_dm(campaign_id)
    and dm_encounter_belongs_to_campaign(encounter_id, campaign_id)
  );

create policy "DM can update combatants"
  on dm_combatants for update
  using (is_campaign_dm(campaign_id))
  with check (
    is_campaign_dm(campaign_id)
    and dm_encounter_belongs_to_campaign(encounter_id, campaign_id)
  );

create policy "DM can delete combatants"
  on dm_combatants for delete
  using (is_campaign_dm(campaign_id));
