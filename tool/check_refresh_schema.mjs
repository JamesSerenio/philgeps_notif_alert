// Read-only diagnosis using the app's public configuration; never prints keys or rows.
import { readFileSync } from 'node:fs';
const config = readFileSync(new URL('../lib/utils/supabase_client.dart', import.meta.url), 'utf8');
const url = config.match(/supabaseUrl\s*=\s*'([^']+)'/)[1];
const key = config.match(/supabaseAnonKey\s*=\s*'([^']+)'/)[1];
for (const [table, select] of [['philgeps_posts','source,official_notice_id'],['scrape_control','id'],['philgeps_source_refresh','source']]) {
  const response = await fetch(`${url}/rest/v1/${table}?select=${select}&limit=1`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  const data = await response.json();
  console.log(JSON.stringify({ table, status: response.status, code: data.code || null,
    message: response.ok ? 'Available to public client' : data.message }));
}
