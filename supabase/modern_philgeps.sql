-- Additive migration. Existing primary IDs and all dependent selections remain intact.
begin;
alter table public.philgeps_posts
  add column if not exists source text not null default 'existing',
  add column if not exists official_notice_id text,
  add column if not exists official_url text,
  add column if not exists procurement_mode text,
  add column if not exists document_status text not null default 'unverified',
  add column if not exists document_url text;
do $$ begin
  if exists (select 1 from public.philgeps_posts where source = 'existing' and id::text like '-%') then
    raise exception 'Negative legacy IDs found; review Modern ID namespace before applying migration';
  end if;
end $$;
update public.philgeps_posts set official_notice_id = coalesce(nullif(reference_number::text, ''), id::text), official_url = url
where source = 'existing' and official_notice_id is null;
create unique index if not exists philgeps_source_notice_idx
  on public.philgeps_posts(source, official_notice_id);
create table if not exists public.philgeps_source_refresh (
  source text primary key check (source in ('existing','modern')),
  last_success_at timestamptz,
  last_attempt_at timestamptz,
  error text
);
insert into public.philgeps_source_refresh(source) values ('existing'), ('modern') on conflict do nothing;
alter table public.philgeps_source_refresh enable row level security;
revoke all on public.philgeps_source_refresh from anon, authenticated;
grant all on public.philgeps_source_refresh to service_role;
create or replace function public.record_philgeps_source_refresh(p_source text, p_error text)
returns void language sql security definer set search_path = public as $$
  insert into public.philgeps_source_refresh(source, last_attempt_at, last_success_at, error)
  values (p_source, now(), case when p_error is null then now() else null end, p_error)
  on conflict (source) do update set
    last_attempt_at = excluded.last_attempt_at,
    error = excluded.error,
    last_success_at = case when excluded.error is null then excluded.last_attempt_at
      else philgeps_source_refresh.last_success_at end;
$$;
revoke all on function public.record_philgeps_source_refresh(text,text) from public, anon, authenticated;
grant execute on function public.record_philgeps_source_refresh(text,text) to service_role;
commit;
