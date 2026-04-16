-- Optional link to external character sheet (e.g. D&D Beyond, Roll20, Google Doc)
alter table characters add column if not exists character_sheet_url text not null default '';
