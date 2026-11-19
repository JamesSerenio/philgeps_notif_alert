// Real React UI with fixture REST responses; never changes production records.
const { chromium } = require('playwright');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { pathToFileURL } = require('node:url');
const root='C:/Projects/philgeps-editor';
const origin='http://127.0.0.1:5188';
const id='fc066763-84a8-4423-bbd8-eada9101c201';
const setup={projectTitle:'SUPPLY AND DELIVERY OF WATER METER AND FITTINGS',referenceNumber:'132124',procuringEntity:'MUNICIPALITY OF SUMILAO, BUKIDNON',municipality:'SUMILAO',province:'BUKIDNON',date:'2026-11-16',closingDate:'2026-11-19',isBlankEditor:true};
const projects=[{id,is_bidding_doc:true,is_manual:true,title:'',reference_number:'',procuring_entity:'',lgu:'',abc:null,created_at:'2026-11-16T00:00:00Z',manual_deadline:null},
 {id:'older',title:'Older saved project',reference_number:'OLD-REF',procuring_entity:'Older agency',lgu:'NAAWAN',area_of_delivery:'MISAMIS ORIENTAL',is_bidding_doc:true,is_manual:false,posting_date:'2026-10-01T00:00:00Z',closing_date:'2026-11-20T09:00:00+08:00',abc:0}];
const editors={[id]:{project_id:id,updated_at:'2026-11-16T00:00:00.000001+00:00',bid_security:{documentSetup:setup},technical_specs:[]}};
let revision=1,writes=0,trigger=true,browser;
const server=spawn(process.execPath,[root+'/node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5188','--strictPort'],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
let serverLog='';server.stdout.on('data',x=>serverLog+=x);server.stderr.on('data',x=>serverLog+=x);
async function waitUntil(fn){const start=Date.now();while(Date.now()-start<30000){if(await fn())return;await new Promise(r=>setTimeout(r,100));}throw Error('Timed out waiting for fixture assertion');}
(async()=>{
 const {projectMetadataPatch}=await import(pathToFileURL(root+'/src/lib/projectMetadata.js'));
 try {
  await waitUntil(()=>fetch(origin).then(r=>r.ok).catch(()=>false));
  browser=await chromium.launch({channel:'chrome',headless:true});
  const page=await browser.newPage({viewport:{width:1500,height:1000}});
  await page.route('https://*.supabase.co/**',async route=>{
   const req=route.request(),url=new URL(req.url()),table=url.pathname.split('/').pop(),method=req.method();
   const reply=(data,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(data),headers:{'access-control-allow-origin':'*'}});
   if(method==='OPTIONS')return reply(null);
   const single=req.headers().accept?.includes('vnd.pgrst.object');
   const projectId=(url.searchParams.get(table==='philgeps_posts'?'id':'project_id')||'').replace(/^eq\./,'');
   if(table==='philgeps_posts') {
    if(method==='POST'){const p=JSON.parse(req.postData());projects.push(p);return reply(single?p:[p],201);}
    const rows=projectId?projects.filter(p=>p.id===projectId):projects;
    return reply(single?rows[0]||null:rows);
   }
   if(table==='bid_docs_editor_state') {
    if(method==='PATCH'||method==='POST') {
     const payload=JSON.parse(req.postData()),key=payload.project_id||projectId,old=editors[key];
     const expected=(url.searchParams.get('updated_at')||'').replace(/^eq\./,'');
     if((method==='POST'&&old)||(method==='PATCH'&&(!old||old.updated_at!==expected)))return reply({code:'PGRST116',message:'Stale version'},406);
     const saved={...old,...payload,updated_at:`2026-11-19T00:00:00.${String(++revision).padStart(6,'0')}+00:00`};
     editors[key]=saved;writes++;
     const p=projects.find(p=>p.id===key);
     if(trigger&&payload.bid_security?.documentSetup)Object.assign(p,projectMetadataPatch(payload.bid_security.documentSetup,p));
     return reply(single?saved:[saved]);
    }
    if(url.searchParams.get('limit')==='0')return reply([]);
    const rows=editors[projectId]?[editors[projectId]]:[];
    return reply(single?rows[0]||null:rows);
   }
   return reply(single?null:[]);
  });
  await page.goto(origin+'/project/'+id);
  await page.getByLabel('Reference Number',{exact:true}).waitFor();
  await waitUntil(async()=>await page.locator('.save-status').innerText()==='Saved');
  assert.equal(projects[0].reference_number,'132124');
  await page.getByLabel('Project Title',{exact:true}).fill(setup.projectTitle+' UPDATED');
  await page.getByLabel('Project Title',{exact:true}).fill(setup.projectTitle);
  await page.getByRole('button',{name:'Back to projects',exact:true}).click();
  await page.waitForURL(origin+'/');
  const card=page.locator('.project-card').filter({has:page.getByRole('heading',{name:setup.projectTitle,exact:true})});
  await card.waitFor();
  const text=await card.innerText();
  for(const value of ['132124','SUMILAO','BUKIDNON',setup.procuringEntity,'Nov 19, 2026','Not available'])assert.ok(text.includes(value),value+' missing from card');
  await page.reload();await card.waitFor();
  await card.getByRole('button',{name:'Open Editor'}).click();
  await page.waitForURL(origin+'/project/'+id);
  assert.equal(await page.getByLabel('Reference Number',{exact:true}).inputValue(),'132124');
  assert.equal(await page.getByLabel('Project Title',{exact:true}).inputValue(),setup.projectTitle);
  await page.getByRole('button',{name:'Back to projects',exact:true}).click();
  const oldCard=page.locator('.project-card').filter({has:page.getByRole('heading',{name:'Older saved project',exact:true})});
  await oldCard.waitFor();assert.ok((await oldCard.innerText()).includes('₱0.00'));
  await oldCard.getByRole('button',{name:'Open Editor'}).click();
  await page.getByLabel('Reference Number',{exact:true}).waitFor();
  assert.equal(await page.getByLabel('Reference Number',{exact:true}).inputValue(),'OLD-REF');
  await page.getByRole('button',{name:'Back to projects',exact:true}).click();
  await page.getByRole('button',{name:/Blank Editor/}).click();
  await page.getByLabel('Project Title',{exact:true}).waitFor();
  const blankId=page.url().split('/').pop();
  assert.notEqual(blankId,id);
  for(const [label,value] of [['Project Title','New metadata project'],['Reference Number','NEW-TEST'],['Procuring Entity','New agency'],['Province','BUKIDNON'],['Municipality','SUMILAO']])await page.getByLabel(label,{exact:true}).fill(value);
  await page.getByRole('button',{name:'Back to projects',exact:true}).click();
  await page.getByRole('heading',{name:'New metadata project',exact:true}).waitFor();
  assert.equal(projects.find(p=>p.id===blankId).reference_number,'NEW-TEST');
  trigger=false;
  await page.goto(origin+'/project/'+id);
  await page.getByLabel('Project Title',{exact:true}).fill('Unsaved shared title');
  await waitUntil(async()=>await page.locator('.save-status').innerText()==='Error saving');
  assert.ok((await page.locator('.save-error-detail').innerText()).includes('project_metadata_sync.sql'));
  assert.equal(projects[0].title,setup.projectTitle);
  // Another tab saves while this tab retains an unsaved local draft.
  trigger=true;
  const newerSetup={...setup,projectTitle:'Newer saved title from another tab'};
  editors[id]={...editors[id],bid_security:{documentSetup:newerSetup},updated_at:'2026-11-19T01:00:00.000099+00:00'};
  Object.assign(projects[0],projectMetadataPatch(newerSetup,projects[0]));
  await page.reload();
  await waitUntil(async()=>await page.locator('.save-status').innerText()==='Error saving');
  assert.ok((await page.locator('.save-error-detail').innerText()).includes('another tab changed'));
  assert.equal(projects[0].title,newerSetup.projectTitle);
  assert.equal(editors[id].bid_security.documentSetup.projectTitle,newerSetup.projectTitle);
  console.log('PASS React browser fixture: 132124 repair, save/back/list, browser reload/reopen stable ID, blank project, older project, null versus zero ABC, actionable missing-trigger failure, stale local draft rejection. Editor writes:',writes);
 }catch(error){console.error(error.message);if(browser)console.error((await browser.contexts()[0].pages()[0].locator('body').innerText()).slice(0,3500));console.error(serverLog.slice(-1000));process.exitCode=1;}
 finally{await browser?.close();server.kill();}
})();
