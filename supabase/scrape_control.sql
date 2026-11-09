-- Additive migration only. Existing posts, decisions and notification tables are untouched.
create table if not exists public.scrape_control (
  id integer primary key check (id = 1),
  run jsonb,
  last_success_at timestamptz,
  last_manual_at timestamptz,
  last_automatic_slot text,
  lease_until timestamptz
);
insert into public.scrape_control(id) values (1) on conflict do nothing;
alter table public.scrape_control enable row level security;
revoke all on public.scrape_control from anon, authenticated;
grant all on public.scrape_control to service_role;

create or replace function public.claim_scrape_run(
  p_run_id uuid, p_trigger text, p_slot text, p_cooldown_seconds integer
) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.scrape_control%rowtype;
begin
  select * into s from public.scrape_control where id = 1 for update;
  if p_trigger not in ('MANUAL', 'AUTOMATIC') then raise exception 'Invalid trigger'; end if;
  if s.run->>'status' = 'running' and s.lease_until > now() then
    return jsonb_build_object('accepted', false, 'reason', 'running', 'run', s.run);
  end if;
  if p_trigger = 'AUTOMATIC' and (p_slot is null or s.last_automatic_slot = p_slot) then
    return jsonb_build_object('accepted', false, 'reason', 'scheduled_already', 'run', s.run);
  end if;
  if p_trigger = 'MANUAL' and s.last_manual_at > now() - make_interval(secs => greatest(p_cooldown_seconds, 120)) then
    return jsonb_build_object('accepted', false, 'reason', 'rate_limited', 'run', s.run);
  end if;
  update public.scrape_control set
    run = jsonb_build_object('id', p_run_id, 'trigger', p_trigger, 'status', 'running', 'startedAt', now()),
    lease_until = now() + interval '30 minutes',
    last_manual_at = case when p_trigger = 'MANUAL' then now() else last_manual_at end,
    last_automatic_slot = case when p_trigger = 'AUTOMATIC' then p_slot else last_automatic_slot end
  where id = 1 returning * into s;
  return jsonb_build_object('accepted', true, 'run', s.run);
end;
$$;

create or replace function public.finish_scrape_run(p_run_id uuid, p_result jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.scrape_control set
    run = run || p_result,
    lease_until = null,
    last_success_at = case when p_result->>'status' = 'completed' then now() else last_success_at end
  where id = 1 and run->>'id' = p_run_id::text;
end;
$$;
revoke all on function public.claim_scrape_run(uuid,text,text,integer) from public, anon, authenticated;
revoke all on function public.finish_scrape_run(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.claim_scrape_run(uuid,text,text,integer) to service_role;
grant execute on function public.finish_scrape_run(uuid,jsonb) to service_role;
