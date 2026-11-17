-- Edited details (title, author, description, cover, reading status) that win over the server's.
alter table public.entries add column if not exists custom jsonb not null default '{}';
-- Order of titles inside a series.
alter table public.entries add column if not exists position integer not null default 0;
-- Merged titles: number chapters 1, 2, 3… instead of keeping the sources' names.
alter table public.entries add column if not exists renumber boolean not null default false;

-- Merged titles: sources with the same segment are versions of one another; segments follow each other.
alter table public.entry_sources add column if not exists segment integer not null default 0;

-- A chapter moved by hand: its place in the reading order.
alter table public.chapter_states add column if not exists position numeric;

-- Pasted chapters: 'chapter' = its own chapter, 'version' = another version of the chapter with that number.
alter table public.inserted_chapters add column if not exists mode text not null default 'chapter' check (mode in ('chapter', 'version'));

-- Merges titles into `keep`: their sources follow as later segments (offset by `segments`), and their
-- reading state, page layouts, inserted chapters, tabs and nested titles move over. Then they are deleted.
-- Runs with the caller's rights, so row-level security still applies.
create or replace function public.merge_entries(keep uuid, parts uuid[], segments integer[])
returns void language plpgsql security invoker set search_path = public as $$
declare i integer;
begin
  for i in 1..coalesce(array_length(parts, 1), 0) loop
    insert into entry_sources (user_id, entry_id, source_id, manga_url, server_manga_id, source_name, following, is_main, segment)
      select user_id, keep, source_id, manga_url, server_manga_id, source_name, following, false, segments[i] + segment
      from entry_sources where entry_id = parts[i]
      on conflict (entry_id, source_id, manga_url) do nothing;
    insert into chapter_states (user_id, entry_id, source_id, chapter_url, chapter_number, page, read, bookmarked, removed, preferred, position, updated_at)
      select user_id, keep, source_id, chapter_url, chapter_number, page, read, bookmarked, removed, preferred, null, updated_at
      from chapter_states where entry_id = parts[i]
      on conflict (entry_id, source_id, chapter_url) do nothing;
    insert into chapter_splits (user_id, entry_id, source_id, chapter_url, breaks, excluded)
      select user_id, keep, source_id, chapter_url, breaks, excluded from chapter_splits where entry_id = parts[i]
      on conflict (entry_id, source_id, chapter_url) do nothing;
    update inserted_chapters set entry_id = keep where entry_id = parts[i];
    insert into entry_tabs (user_id, entry_id, tab_id)
      select user_id, keep, tab_id from entry_tabs where entry_id = parts[i]
      on conflict (entry_id, tab_id) do nothing;
    update entries set parent_id = keep where parent_id = parts[i];
    delete from entries where id = parts[i];
  end loop;
  update entries set updated_at = now() where id = keep;
end $$;

revoke all on function public.merge_entries(uuid, uuid[], integer[]) from public, anon;
grant execute on function public.merge_entries(uuid, uuid[], integer[]) to authenticated;
