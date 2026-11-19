-- Read-only: inspect the deployed refresh dependencies, without changing data.
select table_name,column_name,data_type,is_nullable from information_schema.columns
where table_schema='public' and table_name in ('philgeps_posts','scrape_control','philgeps_source_refresh','notification_logs')
order by table_name,ordinal_position;
select tablename,indexname,indexdef from pg_indexes where schemaname='public'
and tablename in ('philgeps_posts','notification_logs','scrape_control','philgeps_source_refresh');
select conrelid::regclass as table_name,conname,pg_get_constraintdef(oid) as definition
from pg_constraint where connamespace='public'::regnamespace
and conrelid in (to_regclass('public.philgeps_posts'),to_regclass('public.notification_logs'),to_regclass('public.scrape_control'),to_regclass('public.philgeps_source_refresh'));
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments,
 has_function_privilege('service_role',p.oid,'EXECUTE') as server_can_execute,
 has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') as signed_in_can_execute
from pg_proc p join pg_namespace n on p.pronamespace=n.oid where n.nspname='public'
and p.proname in ('claim_scrape_run','finish_scrape_run','record_philgeps_source_refresh','set_bid_doc_state');
select c.relname,c.relrowsecurity,
 (has_table_privilege('service_role',c.oid,'SELECT')
  and has_table_privilege('service_role',c.oid,'INSERT')
  and has_table_privilege('service_role',c.oid,'UPDATE')) as server_has_required_access,
 has_table_privilege('anon',c.oid,'SELECT') as anon_can_read
from pg_class c join pg_namespace n on c.relnamespace=n.oid where n.nspname='public'
and c.relname in ('philgeps_posts','scrape_control','philgeps_source_refresh','notification_logs');
select source,count(*) as stored_notices,min(created_at) as first_discovered,max(created_at) as last_discovered
from public.philgeps_posts group by source;
