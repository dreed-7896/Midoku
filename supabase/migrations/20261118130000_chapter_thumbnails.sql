alter table public.chapter_states add column if not exists thumb text;
comment on column public.chapter_states.thumb is 'Chapter thumbnail picked by the person: "page:N" (a page of the chapter) or an image data URL.';
