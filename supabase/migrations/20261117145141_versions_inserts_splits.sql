-- Which version (linked source) of a chapter slot is read; set on the chosen physical chapter.
alter table public.chapter_states add column preferred boolean not null default false;

-- A chapter from another title or source placed into an entry at a chosen number.
create table public.inserted_chapters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.entries on delete cascade,
  source_id text not null,
  manga_url text not null,
  chapter_url text not null,
  server_chapter_id integer,
  number numeric not null,
  label text not null,
  from_title text not null default '',
  created_at timestamptz not null default now()
);

-- A long chapter cut into parts: breaks are the first page of every part after the first.
create table public.chapter_splits (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.entries on delete cascade,
  source_id text not null,
  chapter_url text not null,
  breaks integer[] not null,
  primary key (entry_id, source_id, chapter_url)
);

create index on public.inserted_chapters (user_id);
create index on public.inserted_chapters (entry_id);
create index on public.chapter_splits (user_id);

do $$
declare t text;
begin
  foreach t in array array['inserted_chapters', 'chapter_splits'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "own rows" on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;
