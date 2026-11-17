-- Midoku's own library. Suwayomi only supplies titles, chapters and pages; everything the person
-- does (library, tabs, reading progress, marks) lives here, one set of rows per signed-in user.

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  title text not null,
  author text not null default '',
  cover_path text,
  description text not null default '',
  tags text[] not null default '{}',
  publishing text not null default 'Ongoing',
  parent_id uuid references public.entries on delete set null,
  in_library boolean not null default true,
  added_at timestamptz not null default now(),
  last_read_at timestamptz,
  updated_at timestamptz not null default now()
);

-- A title on a source. source_id + manga_url identify it on any Suwayomi server;
-- server_manga_id is the id on the server currently in use.
create table public.entry_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.entries on delete cascade,
  source_id text not null,
  manga_url text not null,
  server_manga_id integer,
  source_name text,
  following boolean not null default true,
  is_main boolean not null default false,
  unique (entry_id, source_id, manga_url)
);

-- Per physical source chapter, keyed by the source's chapter url.
create table public.chapter_states (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.entries on delete cascade,
  source_id text not null,
  chapter_url text not null,
  chapter_number numeric,
  page integer not null default 0,
  read boolean not null default false,
  bookmarked boolean not null default false,
  removed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (entry_id, source_id, chapter_url)
);

create table public.tabs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  kind text not null check (kind in ('reading', 'all', 'tab', 'smart')),
  name text not null,
  filters jsonb,
  position integer not null default 0
);

create table public.entry_tabs (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  entry_id uuid not null references public.entries on delete cascade,
  tab_id uuid not null references public.tabs on delete cascade,
  primary key (entry_id, tab_id)
);

create index on public.entries (user_id);
create index on public.entries (parent_id);
create index on public.entry_sources (user_id);
create index on public.entry_sources (entry_id);
create index on public.chapter_states (user_id);
create index on public.tabs (user_id);
create index on public.entry_tabs (user_id);
create index on public.entry_tabs (tab_id);

-- Read chapters per title, for library counts without loading every chapter row.
create view public.entry_progress with (security_invoker = true) as
  select entry_id, count(*) filter (where read and not removed)::int as read_count
  from public.chapter_states group by entry_id;

do $$
declare t text;
begin
  foreach t in array array['entries', 'entry_sources', 'chapter_states', 'tabs', 'entry_tabs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "own rows" on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

grant select on public.entry_progress to authenticated;
revoke all on public.entry_progress from anon;
