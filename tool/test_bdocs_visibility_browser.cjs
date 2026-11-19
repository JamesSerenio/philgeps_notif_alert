// Real React list with a controlled clock and fixture Supabase responses.
const {chromium}=require('playwright');
const {spawn}=require('node:child_process');
const assert=require('node:assert/strict');
const root='C:/Projects/philgeps-editor';
const origin='http://127.0.0.1:5190';
const rows=[
  {id:'today',title:'Deadline today',manual_deadline:'2026-11-19'},
  {id:'closed',title:'Expired saved project',closing_date:'2026-11-18T10:00:00+08:00'},
  {id:'open',title:'Future project',closing_date:'2026-11-21T10:00:00+08:00'},
  {id:'blank',title:'Project without deadline'},
].map(p=>({...p,is_bidding_doc:true,is_manual:true}));
const original=JSON.stringify(rows);
const server=spawn(process.execPath,[root+'/node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5190','--strictPort'],{cwd:root,windowsHide:true,stdio:'ignore'});
let browser;
(async()=>{
 try{
  for(let i=0;i<100;i++){if(await fetch(origin).then(r=>r.ok).catch(()=>false))break;await new Promise(r=>setTimeout(r,100));}
  browser=await chromium.launch({channel:'chrome',headless:true});
  const page=await browser.newPage();
  await page.clock.install({time:new Date('2026-11-19T23:59:45+08:00')});
  await page.route('https://*.supabase.co/**',route=>route.fulfill({contentType:'application/json',body:JSON.stringify(rows)}));
  await page.goto(origin);
  await page.getByRole('heading',{name:'Deadline today',exact:true}).waitFor();
  assert.equal(await page.locator('.project-card').count(),3);
  assert.equal(await page.getByRole('heading',{name:'Expired saved project',exact:true}).count(),0);
  await page.clock.fastForward(30000);
  await page.getByRole('heading',{name:'Future project',exact:true}).waitFor();
  assert.equal(await page.getByRole('heading',{name:'Deadline today',exact:true}).count(),0);
  assert.equal(await page.locator('.project-card').count(),2);
  await page.getByRole('searchbox').fill('Expired saved project');
  assert.equal(await page.locator('.project-card').count(),0);
  assert.equal(JSON.stringify(rows),original);
  console.log('PASS React browser: expired projects hidden, midnight rollover removes card automatically, unknown deadlines retained, search cannot reshow closed bids, saved rows unchanged.');
 }catch(error){console.error(error);process.exitCode=1;}
 finally{await browser?.close();server.kill();}
})();
