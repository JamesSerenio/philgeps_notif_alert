import {test} from 'node:test';
import assert from 'node:assert/strict';
import {collectModernProvince,readModernPage,postModernPage} from './modern-pagination.js';
import {searchExisting} from './existing-philgeps.js';
import {matchesLgu,safeError,publicNavigation,failureStatus} from './portal-runtime.js';
import {officialModernUrl,modernAgency} from './modern-philgeps.js';
const response=(status=200)=>({status:()=>status,ok:()=>status>=200&&status<300});
function modernPage(pages,{failAt=0,dropFilter=false,split=false}={}) {
 let number=1,filters={},closed=false;
 const posts=[];
 return {
  posts,
  async goto(){number=1;return response();},
  locator(){return{waitFor:async()=>{}};},
  async waitForNavigation(){await Promise.resolve();return response(number===failAt?503:200);},
  async waitForTimeout(){},
  async evaluate(fn,args){
   if(args?.filters){filters={...args.filters};number=args.next?Number(new URL(args.next).searchParams.get('page')):1;posts.push({number,filters:{...filters},next:args.next});return;}
   const part=split&&filters.from ? [{referenceNumber:filters.from==='01-Jan-2000'?'1':'2'}] : pages[number-1];
   if(fn.name==='readModernPage'){
    const total=split&&filters.from ? 1 : pages.flat().length;
    const count=split&&filters.from ? 1 : pages.length;
    return{page:number,pages:count,total,area:dropFilter&&number===2?'':filters.area,from:filters.from,to:filters.to,next:number<count?`https://philgeps.gov.ph/indexes/view-more-open-tenders?page=${number+1}`:null};
   }
   return part;
  },
 };
}
function dummyRows(){}
test('municipalities are case/space insensitive and do not match substrings of other towns',()=>{
 assert.equal(modernAgency('  MANOLO   fortich '),'MUNICIPALITY OF MANOLO FORTICH BUKIDNON');
 assert.equal(matchesLgu('project at SALAY, Misamis Oriental',' salay '),true);
 assert.equal(matchesLgu('Mansalay Oriental Mindoro','salay'),false);
 assert.equal(matchesLgu('IMPASUG-ONG BUKIDNON','impasugong'),true);
 assert.equal(officialModernUrl('/Indexes/viewLiveTenderDetails/146485/OPEN_MORE'),'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/146485/OPEN_MORE');
 assert.equal(safeError(Error('Bearer private-token https://x/?token=secret')),'Bearer [redacted] https://x/?token=[redacted]');
});
test('Modern POSTs each page with province/date filters and checks totals',async()=>{
 const page=modernPage([[{referenceNumber:'1'},{referenceNumber:'2'}],[{referenceNumber:'3'}]]);
 const result=await collectModernProvince(page,'Bukidnon',dummyRows,{log(){}});
 assert.equal(result.rows.length,3);assert.equal(result.failures.length,0);
 assert.equal(page.posts.length,2);
 assert.equal(page.posts[1].filters.area,'Bukidnon');
 assert.equal(page.posts[1].number,2);
});
test('100 genuine complete rows are not automatically marked truncated',async()=>{
 const result=await collectModernProvince(modernPage([Array.from({length:100},(_,i)=>({referenceNumber:String(i)}))]),'Bukidnon',dummyRows,{log(){}});
 assert.equal(result.rows.length,100);assert.equal(result.failures.length,0);
});
test('a verified empty municipality/province query succeeds',async()=>{
 const result=await collectModernProvince(modernPage([[]]),'Bukidnon',dummyRows,{log(){}});
 assert.equal(result.rows.length,0);assert.equal(result.failures.length,0);
});
test('Modern keeps earlier verified pages after HTTP failure or dropped filters',async()=>{
 for(const options of [{dropFilter:true},{failAt:2}]) {
  const result=await collectModernProvince(modernPage([[{referenceNumber:'1'}],[{referenceNumber:'2'}]],options),'Bukidnon',dummyRows,{log(){}});
  assert.equal(result.rows.length,1);assert.equal(result.failures.length,1);
  assert.match(result.failures[0].error,/filters|HTTP 503/);
 }
});
test('broad Modern queries split into inclusive nonoverlapping publication date ranges',async()=>{
 const page=modernPage([[{referenceNumber:'1'}],[{referenceNumber:'2'}]],{split:true});
 const result=await collectModernProvince(page,'Bukidnon',dummyRows,{maxPages:1,log(){}});
 assert.equal(result.failures.length,0);assert.equal(result.rows.length,2);
 assert.equal(page.posts[1].filters.from,'01-Jan-2000');
 assert.notEqual(page.posts[1].filters.to,page.posts[2].filters.from);
});
test('unexpected pagination origins are rejected before navigation',async()=>{
 await assert.rejects(postModernPage({}, {area:'Bukidnon'},'https://evil.example/indexes/view-more-open-tenders?page=2'),/Unexpected/);
});
test('transport failures do not incorrectly inherit the previous HTTP 200',async()=>{
 try {await publicNavigation({waitForNavigation:async()=>{throw Error('net::ERR_CONNECTION_RESET');}},async()=>{},'Existing PhilGEPS');assert.fail('expected failure');}
 catch(error){assert.equal(failureStatus(error,200),null);assert.match(error.message,/ERR_CONNECTION_RESET/);}
});
test('Existing valid empty search succeeds while request failures keep HTTP/query diagnostics',async()=>{
 for(const httpStatus of [200,403]) {
  const page={goto:async()=>response(httpStatus),waitForNavigation:async()=>response(),waitForTimeout:async()=>{},
   locator(selector){return{waitFor:async()=>{},fill:async()=>{},click:async()=>{},count:async()=>selector==='#pgCtrlDetailedSearch_pageDropDownList'?0:1};},
   context:()=>({newPage:async()=>({close:async()=>{}})}),
   evaluate:async fn=>fn.toString().includes('const text=document.body.innerText')?{keyword:' SUMILAO ',empty:true,count:0}:null};
  const args={page,keyword:'sumilao',existingPostIds:new Set(),isActive:()=>true,readRows:async()=>[],log(){}};
  if(httpStatus===200){const rows=await searchExisting(args);assert.equal(rows.length,0);assert.equal(rows.reports[0].parsing,'empty');}
  else await assert.rejects(searchExisting(args),e=>e.queryReport.httpStatus===403&&e.queryReport.query==='sumilao');
 }
});
