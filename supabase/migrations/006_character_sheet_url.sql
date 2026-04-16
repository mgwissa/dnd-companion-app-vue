-- Optional link to external character sheet (e.g. virtual tabletop, Google Doc)
alter table characters add column if not exists character_sheet_url text not null default '';
