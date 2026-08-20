create table campaign_threads (
  id          uuid default gen_random_uuid() primary key,
  campaign_id uuid references campaigns(id) on delete cascade not null,
  created_by  uuid references auth.users(id) on delete cascade not null,
  title       text not null,
  is_done     boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index campaign_threads_campaign_idx on campaign_threads (campaign_id, is_done, created_at);

alter table campaign_threads enable row level security;

create policy "Campaign members can view threads"
  on campaign_threads for select
  using (is_campaign_member(campaign_id));

create policy "Members can create threads"
  on campaign_threads for insert
  with check (auth.uid() = created_by and is_campaign_member(campaign_id));

create policy "Members can update threads"
  on campaign_threads for update
  using (is_campaign_member(campaign_id));

create policy "Thread creators can delete threads"
  on campaign_threads for delete
  using (auth.uid() = created_by);
