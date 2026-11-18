create table if not exists public.chapter_imports (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entry_id uuid not null references public.entries(id) on delete cascade,
  source_id text not null,
  manga_url text not null,
  number numeric,
  title text,
  read boolean not null default false,
  page integer not null default 0,
  removed boolean not null default false,
  preferred boolean not null default false,
  position numeric,
  name text,
  thumb text,
  breaks integer[],
  excluded integer[],
  only_chapter boolean not null default false,
  created_at timestamptz not null default now()
);
comment on table public.chapter_imports is 'Reading state imported from a backup, waiting for the title''s chapters to load; matched by source title + chapter number, then moved to chapter_states.';
create index if not exists chapter_imports_entry on public.chapter_imports(entry_id);
alter table public.chapter_imports enable row level security;
create policy "own imports" on public.chapter_imports for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.chapter_imports to authenticated;
