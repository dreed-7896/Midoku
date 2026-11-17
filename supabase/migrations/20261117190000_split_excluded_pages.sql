-- Pages left out of a chapter (credits, ads); applies whether or not the chapter is split.
alter table public.chapter_splits add column if not exists excluded int[] not null default '{}';
