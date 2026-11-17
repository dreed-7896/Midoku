-- Reading history: when a chapter was last read, and its name as shown then.
alter table public.chapter_states add column if not exists read_at timestamptz;
alter table public.chapter_states add column if not exists chapter_label text;
create index if not exists chapter_states_read_at on public.chapter_states (user_id, read_at desc) where read_at is not null;

-- Clears history for one title, or for everything when `entry` is null. Row-level security still applies.
create or replace function public.clear_history(entry uuid default null)
returns void language sql security invoker set search_path = public as $$
  update chapter_states set read_at = null where read_at is not null and (entry is null or entry_id = entry);
$$;

revoke all on function public.clear_history(uuid) from public, anon;
grant execute on function public.clear_history(uuid) to authenticated;
