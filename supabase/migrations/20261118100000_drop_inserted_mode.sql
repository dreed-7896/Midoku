-- Pasting chapters as versions was dropped (chapters are added with "Add to entry" instead).
alter table public.inserted_chapters drop column if exists mode;
