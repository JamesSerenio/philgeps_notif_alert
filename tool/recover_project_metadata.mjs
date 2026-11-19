// Fill missing shared fields from saved editor JSON, by stable project ID.
// Uses compare-and-set filters; never writes editor sections or existing values.
import {readFile,writeFile} from 'node:fs/promises';
const config=await readFile('C:/Projects/philgeps-editor/src/supabase.js','utf8');
const url=config.match(/supabaseUrl\s*=\s*'([^']+)'/)[1],key=config.match(/supabaseKey\s*=\s*'([^']+)'/)[1];
const headers={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json',Prefer:'return=representation'};
async function read(table,query){const r=await fetch(`${url}/rest/v1/${table}?${query}`,{headers});if(!r.ok)throw Error(`${table} HTTP ${r.status}`);return r.json();}
const projects=await read('philgeps_posts','select=*&is_bidding_doc=eq.true');
const states=await read('bid_docs_editor_state','select=project_id,bid_security,updated_at');
const mapping={title:'projectTitle',reference_number:'referenceNumber',procuring_entity:'procuringEntity',lgu:'municipality',area_of_delivery:'province'};
const results=[];
for(const p of projects){
 const state=states.find(s=>String(s.project_id)===String(p.id)),setup=state?.bid_security?.documentSetup;
 if(!setup)continue;
 const patch={};
 for(const [column,key] of Object.entries(mapping))if(!String(p[column]??'').trim()&&String(setup[key]??'').trim())patch[column]=String(setup[key]).trim();
 if(p.is_manual===true&&!p.manual_deadline&&/^\d{4}-\d{2}-\d{2}$/.test(setup.closingDate||''))patch.manual_deadline=setup.closingDate;
 if(!Object.keys(patch).length)continue;
 const params=new URLSearchParams({id:`eq.${p.id}`,select:'id,title,reference_number,procuring_entity,lgu,area_of_delivery,manual_deadline,posting_date'});
 for(const column of Object.keys(patch))params.set(column,p[column]==null?'is.null':`eq.${p[column]}`);
 const response=await fetch(`${url}/rest/v1/philgeps_posts?${params}`,{method:'PATCH',headers,body:JSON.stringify(patch)});
 const body=await response.json();
 results.push({id:p.id,reference:setup.referenceNumber,status:response.status,updated:Array.isArray(body)?body.length:0,error:Array.isArray(body)?(body.length?'':'No row updated; check UPDATE policy or concurrent change'):body.message,fields:Object.keys(patch),row:Array.isArray(body)?body[0]:undefined});
}
await writeFile('tool/project-metadata-recovery.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
