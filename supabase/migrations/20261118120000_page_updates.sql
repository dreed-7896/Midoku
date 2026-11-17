-- New pages in a chapter the server had already fetched: found by the update check, listed in Updates.
alter table public.chapter_states add column if not exists pages integer;
alter table public.chapter_states add column if not exists pages_before integer;
alter table public.chapter_states add column if not exists pages_grew_at timestamptz;
create index if not exists chapter_states_pages_grew_at on public.chapter_states (user_id, pages_grew_at desc) where pages_grew_at is not null;
