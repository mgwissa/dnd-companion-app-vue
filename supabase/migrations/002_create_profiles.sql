create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  character_name text not null default '',
  avatar_url     text not null default '',
  backstory      text not null default '',
  backstory_url  text not null default '',
  updated_at     timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "Users can view own profile"
  on profiles for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on profiles for update
  using (auth.uid() = id);
