-- ============================================================
-- 1. Create all tables first (order matters for foreign keys)
-- ============================================================

-- Campaigns
create table campaigns (
  id          uuid default gen_random_uuid() primary key,
  name        text not null,
  invite_code text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Campaign members (join table)
create table campaign_members (
  id          uuid default gen_random_uuid() primary key,
  campaign_id uuid references campaigns(id) on delete cascade not null,
  user_id     uuid references auth.users(id) on delete cascade not null,
  role        text not null default 'member' check (role in ('owner', 'member')),
  joined_at   timestamptz not null default now(),
  unique (campaign_id, user_id)
);

create index campaign_members_campaign_idx on campaign_members (campaign_id);
create index campaign_members_user_idx on campaign_members (user_id);

-- Characters (replaces profiles)
create table characters (
  id              uuid default gen_random_uuid() primary key,
  user_id         uuid references auth.users(id) on delete cascade not null,
  campaign_id     uuid references campaigns(id) on delete cascade not null,
  character_name  text not null default '',
  avatar_url      text not null default '',
  backstory       text not null default '',
  backstory_url   text not null default '',
  is_active       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index characters_user_campaign_idx on characters (user_id, campaign_id);

-- Alter notes: add campaign_id and is_shared
alter table notes add column campaign_id uuid references campaigns(id) on delete cascade;
alter table notes add column is_shared boolean not null default false;

create index notes_campaign_id_idx on notes (campaign_id);


-- ============================================================
-- 2. Enable RLS on all tables
-- ============================================================
alter table campaigns enable row level security;
alter table campaign_members enable row level security;
alter table characters enable row level security;


-- ============================================================
-- 3. Helper function: check campaign membership (bypasses RLS)
--    Avoids infinite recursion in policies that query campaign_members
-- ============================================================
create or replace function is_campaign_member(p_campaign_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from campaign_members
    where campaign_id = p_campaign_id and user_id = auth.uid()
  );
$$;

create or replace function get_campaign_role(p_campaign_id uuid)
returns text
language sql
security definer
stable
as $$
  select role from campaign_members
  where campaign_id = p_campaign_id and user_id = auth.uid()
  limit 1;
$$;


-- ============================================================
-- 4. Campaigns policies
-- ============================================================
create policy "Members can view campaigns"
  on campaigns for select
  using (is_campaign_member(id));

create policy "Creator can view own campaigns"
  on campaigns for select
  using (created_by = auth.uid());

create policy "Authenticated users can create campaigns"
  on campaigns for insert
  with check (auth.uid() is not null);

create policy "Creator can update campaign"
  on campaigns for update
  using (created_by = auth.uid());

create policy "Creator can delete campaign"
  on campaigns for delete
  using (created_by = auth.uid());


-- ============================================================
-- 5. Campaign members policies
-- ============================================================
create policy "Members can view co-members"
  on campaign_members for select
  using (is_campaign_member(campaign_id));

create policy "Users can insert own membership"
  on campaign_members for insert
  with check (auth.uid() = user_id);

create policy "Owner can delete members"
  on campaign_members for delete
  using (
    get_campaign_role(campaign_id) = 'owner'
    or auth.uid() = user_id
  );


-- ============================================================
-- 6. Characters policies
-- ============================================================
create policy "Users can view own characters"
  on characters for select
  using (auth.uid() = user_id);

create policy "Campaign members can view characters"
  on characters for select
  using (is_campaign_member(campaign_id));

create policy "Users can insert own characters"
  on characters for insert
  with check (auth.uid() = user_id);

create policy "Users can update own characters"
  on characters for update
  using (auth.uid() = user_id);

create policy "Users can delete own characters"
  on characters for delete
  using (auth.uid() = user_id);


-- ============================================================
-- 7. Replace notes policies with campaign-aware ones
-- ============================================================
drop policy if exists "Users can view own notes" on notes;
drop policy if exists "Users can insert own notes" on notes;
drop policy if exists "Users can update own notes" on notes;
drop policy if exists "Users can delete own notes" on notes;

create policy "Users can view own and shared notes"
  on notes for select
  using (
    auth.uid() = user_id
    or (is_shared = true and is_campaign_member(campaign_id))
  );

create policy "Users can insert own notes"
  on notes for insert
  with check (auth.uid() = user_id);

create policy "Users can update own notes"
  on notes for update
  using (auth.uid() = user_id);

create policy "Users can delete own notes"
  on notes for delete
  using (auth.uid() = user_id);


-- ============================================================
-- 8. RPC: create a campaign + owner membership in one transaction
-- ============================================================
create or replace function create_campaign(campaign_name text)
returns json
language plpgsql
security definer
as $$
declare
  v_campaign campaigns%rowtype;
begin
  insert into campaigns (name, created_by)
  values (campaign_name, auth.uid())
  returning * into v_campaign;

  insert into campaign_members (campaign_id, user_id, role)
  values (v_campaign.id, auth.uid(), 'owner');

  return json_build_object(
    'id', v_campaign.id,
    'name', v_campaign.name,
    'invite_code', v_campaign.invite_code,
    'created_by', v_campaign.created_by,
    'created_at', v_campaign.created_at,
    'updated_at', v_campaign.updated_at
  );
end;
$$;


-- ============================================================
-- 9. RPC: join a campaign by invite code
-- ============================================================
create or replace function join_campaign(code text)
returns json
language plpgsql
security definer
as $$
declare
  v_campaign campaigns%rowtype;
  v_existing campaign_members%rowtype;
begin
  select * into v_campaign
  from campaigns
  where invite_code = code;

  if v_campaign.id is null then
    raise exception 'Invalid invite code';
  end if;

  select * into v_existing
  from campaign_members
  where campaign_id = v_campaign.id and user_id = auth.uid();

  if v_existing.id is not null then
    return json_build_object(
      'id', v_campaign.id,
      'name', v_campaign.name,
      'already_member', true
    );
  end if;

  insert into campaign_members (campaign_id, user_id, role)
  values (v_campaign.id, auth.uid(), 'member');

  return json_build_object(
    'id', v_campaign.id,
    'name', v_campaign.name,
    'already_member', false
  );
end;
$$;
