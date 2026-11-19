import {readFile,writeFile} from 'node:fs/promises';
const config=await readFile('C:/Projects/philgeps-editor/src/supabase.js','utf8');
const url=config.match(/supabaseUrl\s*=\s*'([^']+)'/)[1],key=config.match(/supabaseKey\s*=\s*'([^']+)'/)[1];
const headers={apikey:key,Authorization:`Bearer ${key}`};
async function get(table,query){const r=await fetch(`${url}/rest/v1/${table}?${query}`,{headers});if(!r.ok)throw Error(`${table} HTTP ${r.status} ${(await r.json()).message}`);return r.json();}
const posts=await get('philgeps_posts','select=*&is_bidding_doc=eq.true&order=created_at.desc');
const states=await get('bid_docs_editor_state','select=project_id,bid_security,updated_at');
const keys=['projectTitle','referenceNumber','procuringEntity','municipality','province','closingDate','date','isBlankEditor'];
const report={host:new URL(url).hostname,columns:Object.keys(posts[0]||{}),projects:posts.map(p=>{const s=states.find(s=>String(s.project_id)===String(p.id));const setup=s?.bid_security?.documentSetup;return{id:p.id,is_manual:p.is_manual,title:p.title,reference_number:p.reference_number,procuring_entity:p.procuring_entity,lgu:p.lgu,area_of_delivery:p.area_of_delivery,closing_date:p.closing_date,manual_deadline:p.manual_deadline,abc:p.abc,setup:setup?Object.fromEntries(keys.map(k=>[k,setup[k]])):null,editorUpdatedAt:s?.updated_at};})};
await writeFile('tool/project-metadata-evidence.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
