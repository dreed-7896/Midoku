alter table public.chapter_states add column if not exists marks integer[];
comment on column public.chapter_states.marks is 'Bookmarked pages of the chapter (whole-chapter page numbers).';
