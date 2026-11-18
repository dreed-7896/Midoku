alter table public.chapter_states add column if not exists name text;
comment on column public.chapter_states.name is 'Chapter name set by the person (shown instead of the source''s).';
