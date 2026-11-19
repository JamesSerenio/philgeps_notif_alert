-- Run as project owner in sfgjpefqqqjgpwjvarru. Additive; stable IDs and all
-- editor/company/pricing/document JSON are preserved. No public UPDATE grant.
begin;
alter table public.philgeps_posts add column if not exists project_metadata_overrides jsonb not null default '{}'::jsonb;

create or replace function public.sync_editor_project_metadata()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  p public.philgeps_posts%rowtype;
  setup jsonb := new.bid_security->'documentSetup';
  prior jsonb := case when tg_op='UPDATE' then old.bid_security->'documentSetup' else '{}'::jsonb end;
  flags jsonb; k text; v text; prior_value text; changed boolean;
begin
  if setup is null or jsonb_typeof(setup)<>'object' then return new; end if;
  select * into p from public.philgeps_posts where id=new.project_id and is_bidding_doc=true for update;
  if not found then raise exception 'Project is missing or is not a BDocs project'; end if;
  flags := coalesce(p.project_metadata_overrides,'{}'::jsonb);
  foreach k in array array['projectTitle','referenceNumber','procuringEntity','municipality','province'] loop
    if not (setup ? k) then continue; end if;
    v := trim(coalesce(setup->>k,''));
    changed := (prior->>k) is distinct from (setup->>k);
    -- A new/changed setup is an explicit edit. Blank hydration defaults must not
    -- erase an imported project's existing identity.
    if v<>'' or (p.is_manual and changed) then
      prior_value:=case k when 'projectTitle' then p.title when 'referenceNumber' then p.reference_number when 'procuringEntity' then p.procuring_entity when 'municipality' then p.lgu else p.area_of_delivery end;
      if changed or prior_value is distinct from v then
        flags := flags || jsonb_build_object(case k when 'projectTitle' then 'title' when 'referenceNumber' then 'reference_number' when 'procuringEntity' then 'procuring_entity' when 'municipality' then 'lgu' else 'area_of_delivery' end,true);
      end if;
      case k
        when 'projectTitle' then p.title:=v;
        when 'referenceNumber' then p.reference_number:=v;
        when 'procuringEntity' then p.procuring_entity:=v;
        when 'municipality' then p.lgu:=v;
        when 'province' then p.area_of_delivery:=v;
      end case;
    end if;
  end loop;
  if p.is_manual=true and setup ? 'closingDate' then
    v:=nullif(trim(setup->>'closingDate'),'');
    if v is not null and v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Manual deadline must be YYYY-MM-DD'; end if;
    p.manual_deadline:=v::date;
  end if;
  update public.philgeps_posts set title=p.title,reference_number=p.reference_number,
    procuring_entity=p.procuring_entity,lgu=p.lgu,area_of_delivery=p.area_of_delivery,
    manual_deadline=p.manual_deadline,project_metadata_overrides=flags where id=p.id;
  return new;
end $$;
revoke all on function public.sync_editor_project_metadata() from public,anon,authenticated;
drop trigger if exists sync_editor_project_metadata on public.bid_docs_editor_state;
create trigger sync_editor_project_metadata after insert or update of bid_security
on public.bid_docs_editor_state for each row execute function public.sync_editor_project_metadata();

create or replace function public.version_editor_state()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin new.updated_at:=clock_timestamp(); return new; end $$;
drop trigger if exists version_editor_state on public.bid_docs_editor_state;
create trigger version_editor_state before insert or update on public.bid_docs_editor_state
for each row execute function public.version_editor_state();

-- Protect user-maintained metadata even if a scraper read races an editor save.
create or replace function public.preserve_manual_project_metadata()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare flags jsonb:=coalesce(old.project_metadata_overrides,'{}'::jsonb);
begin
  if current_user='service_role' or coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')='service_role' then
    if (old.is_manual and nullif(trim(old.title),'') is not null) or flags ? 'title' then new.title:=old.title; end if;
    if (old.is_manual and nullif(trim(old.reference_number),'') is not null) or flags ? 'reference_number' then new.reference_number:=old.reference_number; end if;
    if (old.is_manual and nullif(trim(old.procuring_entity),'') is not null) or flags ? 'procuring_entity' then new.procuring_entity:=old.procuring_entity; end if;
    if (old.is_manual and nullif(trim(old.lgu),'') is not null) or flags ? 'lgu' then new.lgu:=old.lgu; end if;
    if (old.is_manual and nullif(trim(old.area_of_delivery),'') is not null) or flags ? 'area_of_delivery' then new.area_of_delivery:=old.area_of_delivery; end if;
    new.manual_deadline:=old.manual_deadline;
    new.project_metadata_overrides:=old.project_metadata_overrides;
  end if;
  return new;
end $$;
drop trigger if exists preserve_manual_project_metadata on public.philgeps_posts;
create trigger preserve_manual_project_metadata before update on public.philgeps_posts
for each row execute function public.preserve_manual_project_metadata();

-- Recover only missing values, by the existing FK. Never write posting_date:
-- documentSetup.date is a document date, not an official publication date.
update public.philgeps_posts p set
 title=coalesce(nullif(trim(p.title),''),nullif(trim(s.bid_security->'documentSetup'->>'projectTitle'),''),p.title),
 reference_number=coalesce(nullif(trim(p.reference_number),''),nullif(trim(s.bid_security->'documentSetup'->>'referenceNumber'),''),p.reference_number),
 procuring_entity=coalesce(nullif(trim(p.procuring_entity),''),nullif(trim(s.bid_security->'documentSetup'->>'procuringEntity'),''),p.procuring_entity),
 lgu=coalesce(nullif(trim(p.lgu),''),nullif(trim(s.bid_security->'documentSetup'->>'municipality'),''),p.lgu),
 area_of_delivery=coalesce(nullif(trim(p.area_of_delivery),''),nullif(trim(s.bid_security->'documentSetup'->>'province'),''),p.area_of_delivery),
 project_metadata_overrides=coalesce(p.project_metadata_overrides,'{}'::jsonb)||coalesce((
   select jsonb_object_agg(m.col,true) from (values
    ('title','projectTitle'),('reference_number','referenceNumber'),('procuring_entity','procuringEntity'),
    ('lgu','municipality'),('area_of_delivery','province')) m(col,key)
   where nullif(trim(to_jsonb(p)->>m.col),'') is null
     and nullif(trim(s.bid_security->'documentSetup'->>m.key),'') is not null
 ),'{}'::jsonb),
 manual_deadline=case when p.is_manual=true and p.manual_deadline is null
   and (s.bid_security->'documentSetup'->>'closingDate') ~ '^\d{4}-\d{2}-\d{2}$'
   then (s.bid_security->'documentSetup'->>'closingDate')::date else p.manual_deadline end
from public.bid_docs_editor_state s where p.id=s.project_id and p.is_bidding_doc=true;
notify pgrst,'reload schema';
commit;

select id,title,reference_number,procuring_entity,lgu,area_of_delivery,manual_deadline,posting_date
from public.philgeps_posts where id in ('fc066763-84a8-4423-bbd8-eada9101c201','f0c311c2-c46f-4299-9794-b7f635655fbc');
