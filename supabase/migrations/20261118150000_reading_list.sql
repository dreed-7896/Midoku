alter table public.entries add column if not exists reading_pos double precision;
comment on column public.entries.reading_pos is 'Place in the Reading list (null = not in it); lower comes first.';
alter table public.entry_sources alter column following set default false;
