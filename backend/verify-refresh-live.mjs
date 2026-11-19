// Execute the production scraper adapters read-only. Never writes Supabase or sends alerts.
import {chromium} from 'playwright';
import {readFile,writeFile} from 'node:fs/promises';
import vm from 'node:vm';
import {searchExisting} from './existing-philgeps.js';
import {scrapeModern} from './modern-philgeps.js';
import {postModernPage,readModernPage,portalDate,MODERN_MORE} from './modern-pagination.js';
import {readModernRows,MODERN_INDEX} from './modern-philgeps.js';
if(process.argv.includes('--dates-only')) {
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 try {
  const page=await browser.newPage();
  await page.goto(MODERN_INDEX,{waitUntil:'domcontentloaded'});
  await page.goto(MODERN_MORE,{waitUntil:'domcontentloaded'});
  const day=portalDate(new Date(new Date(Date.now()+8*3600000).toISOString().slice(0,10)+'T00:00:00Z'));
  const criteria={area:'Bukidnon',from:day,to:day};
  const status=await postModernPage(page,criteria);
  const metadata=await page.evaluate(readModernPage),rows=await page.evaluate(readModernRows);
  const passed=metadata.from===day&&metadata.to===day&&rows.every(row=>row.postingDate.trim()===day);
  const file=new URL('../tool/live-refresh-evidence.json',import.meta.url);
  const evidence=JSON.parse(await readFile(file,'utf8'));
  evidence.dateFilter={criteria,status,metadata,parsed:rows.length,passed};
  await writeFile(file,JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence.dateFilter));
  if(!passed) process.exitCode=1;
 } finally {await browser.close();}
 process.exit(process.exitCode || 0);
}
const source=await readFile(new URL('./server.js',import.meta.url),'utf8');
const watchLgus=['alubijid','lagonglong','balingasag','villanueva','salay','gitagum','libertad','initao','naawan','laguindingan','talakag','libona','malitbog','sumilao','impasugong','impasug-ong','baungon','manolo fortich'];
const sandbox={console,Date,URL};
for(const name of ['normalize','cleanText','canonicalLgu','parsePhilgepsDate','isStillActive','normalizeAreaOfDelivery','parseBudgetAmount','getBidDetails','readSearchRows']) {
 const start=source.indexOf(`async function ${name}(`)>=0?source.indexOf(`async function ${name}(`):source.indexOf(`function ${name}(`);
 if(start<0)throw Error(`Missing helper ${name}`);
 const boundaries=[source.indexOf('\nfunction ',start+1),source.indexOf('\nasync function ',start+1),source.indexOf('\n/*',start+1)].filter(x=>x>=0);
 const end=Math.min(...boundaries);
 sandbox[name]=vm.runInNewContext(source.slice(start,end)+`\n${name}`,sandbox);
}
const evidence={checkedAt:new Date().toISOString(),existing:{queries:[],notices:[]},modern:{}};
const browser=await chromium.launch({headless:true,channel:'chrome'});
try {
 const context=await browser.newContext();
 const page=await context.newPage();
 const ids=new Set();
 for(const keyword of watchLgus) {
  try {
   const posts=await searchExisting({page,keyword,existingPostIds:ids,isActive:()=>true,
    getBidDetails:sandbox.getBidDetails,readRows:sandbox.readSearchRows,parseDate:sandbox.parsePhilgepsDate,isStillActive:sandbox.isStillActive,
    normalizeArea:sandbox.normalizeAreaOfDelivery,parseBudget:sandbox.parseBudgetAmount,canonicalLgu:sandbox.canonicalLgu,runId:'read-only-verification'});
   evidence.existing.queries.push({query:keyword,eligible:posts.length,retrieved:posts.retrievedCount,reports:posts.reports,failures:posts.failures});
   evidence.existing.notices.push(...posts);
  } catch(error) {evidence.existing.queries.push({query:keyword,error:error.message,reports:error.reports});evidence.existing.notices.push(...(error.partialPosts||[]));}
  await page.waitForTimeout(500);
 }
} finally {await browser.close();await writeFile(new URL('../tool/live-refresh-evidence.json',import.meta.url),JSON.stringify(evidence,null,2));}
const modern=await scrapeModern({chromium:{launch:opts=>chromium.launch({...opts,channel:'chrome'})},watchLgus,assertLease:async()=>{},onBrowser:()=>{},runId:'read-only-verification'});
evidence.modern={retrieved:modern.retrievedCount,eligible:modern.length,failedQueries:modern.failedLgus,queryErrors:modern.queryErrors,reports:modern.reports,notices:[...modern]};
evidence.completedAt=new Date().toISOString();
evidence.durationMs=Date.now()-Date.parse(evidence.checkedAt);
await writeFile(new URL('../tool/live-refresh-evidence.json',import.meta.url),JSON.stringify(evidence,null,2));
console.log('VERIFIED',JSON.stringify({existing:evidence.existing.queries.map(q=>({query:q.query,retrieved:q.retrieved,eligible:q.eligible,error:q.error})),modern:{retrieved:modern.retrievedCount,eligible:modern.length,failed:modern.failedLgus,samples:modern.slice(0,8).map(p=>({id:p.id,reference:p.referenceNumber,url:p.url,area:p.areaOfDelivery,document:p.documentStatus}))}}));
