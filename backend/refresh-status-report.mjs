// Public/read-only deployment and database evidence. Never prints keys or private rows.
import {readFile,writeFile} from 'node:fs/promises';
const config=await readFile(new URL('../lib/utils/supabase_client.dart',import.meta.url),'utf8');
const url=config.match(/supabaseUrl\s*=\s*'([^']+)'/)[1];
const key=config.match(/supabaseAnonKey\s*=\s*'([^']+)'/)[1];
const backend=process.env.SCRAPER_BACKEND_URL || 'https://philgepsnotifalert-production.up.railway.app';
const report={checkedAt:new Date().toISOString(),backend,supabaseHost:new URL(url).hostname};
for(const [name,path] of [['deployment','/'],['run','/check/status'],['history','/check/last-success']]){
 const r=await fetch(backend+path,{signal:AbortSignal.timeout(30000)});report[name]={status:r.status,body:await r.json()};
}
report.sameSupabaseProject=report.deployment.body.supabaseHost===report.supabaseHost;
report.records={};
for(const source of ['existing','modern']){
 const r=await fetch(`${url}/rest/v1/philgeps_posts?select=id,official_notice_id,official_url,closing_date&source=eq.${source}&order=created_at.desc&limit=5`,{headers:{apikey:key,Authorization:`Bearer ${key}`,Prefer:'count=exact'},signal:AbortSignal.timeout(30000)});
 report.records[source]={status:r.status,range:r.headers.get('content-range'),samples:await r.json()};
}
await writeFile(new URL('../tool/deployed-refresh-evidence.json',import.meta.url),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
