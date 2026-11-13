// Read only: print public column types, never keys or row contents.
import { readFileSync } from 'node:fs';
const config = readFileSync(new URL('../lib/utils/supabase_client.dart',import.meta.url),'utf8');
const url = config.match(/supabaseUrl\s*=\s*'([^']+)'/)[1];
const key = config.match(/supabaseAnonKey\s*=\s*'([^']+)'/)[1];
const response = await fetch(`${url}/rest/v1/`,{headers:{apikey:key,Authorization:`Bearer ${key}`,Accept:'application/openapi+json'}});
if (!response.ok) throw Error(`Public schema HTTP ${response.status}`);
const schema = await response.json();
for (const table of ['philgeps_posts','notification_logs','scrape_control']) {
  const props=schema.definitions?.[table]?.properties || {};
  console.log(JSON.stringify({table,columns:Object.fromEntries(Object.entries(props).map(([k,v])=>[k,{type:v.type,format:v.format}]))}));
}
