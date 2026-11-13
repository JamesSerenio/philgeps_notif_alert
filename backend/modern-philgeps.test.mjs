import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { officialModernUrl, modernDate, modernAgency, modernStorageId, inspectModernDocument } from './modern-philgeps.js';

test('official links retain each notice identity and reject untrusted origins', () => {
  assert.equal(officialModernUrl('/Indexes/viewLiveTenderDetails/130491'), 'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491');
  assert.equal(officialModernUrl('https://example.com/Indexes/viewLiveTenderDetails/130491'), null);
  assert.equal(officialModernUrl('/Indexes/login'), null);
  assert.equal(modernAgency('sumilao'), 'MUNICIPALITY OF SUMILAO BUKIDNON');
  assert.equal(modernAgency('balingasag'), 'MUNICIPALITY OF BALINGASAG MISAMIS ORIENTAL');
  assert.equal(modernStorageId('130491'), '-130491');
  assert.throws(()=>modernStorageId('-130491'));
});
test('portal dates keep PHT midnight, noon and closing-hour semantics', () => {
  assert.equal(modernDate('12-Nov-2026'), '2026-11-11T16:00:00.000Z');
  assert.equal(modernDate('19-Nov-2026 09:00 AM'), '2026-11-19T01:00:00.000Z');
  assert.equal(modernDate('19-Nov-2026 12:00 PM'), '2026-11-19T04:00:00.000Z');
  assert.equal(modernDate('unavailable'), null);
});
test('BDocs access is based on response content, never Preview text alone', async () => {
  for (const [status, type, body, disposition, expected] of [
    [200,'text/html','Your session has been expired, please login in again to continue.','','access_required'],
    [403,'text/html','','','access_required'],
    [302,'text/html','','','access_required'],
    [200,'text/html','Documents Preview','','unverified'],
    [200,'application/pdf','not really a pdf','','unverified'],
    [200,'application/pdf','%PDF-1.7','','preview'],
    [200,'application/pdf','%PDF-1.7','attachment; filename=bid.pdf','download'],
  ]) {
    const page = { request: { get: async () => ({ status:()=>status, ok:()=>status===200, headers:()=>({'content-type':type,'content-disposition':disposition}), text:async()=>body, body:async()=>Buffer.from(body) }) } };
    assert.equal((await inspectModernDocument(page,'/Tenders/tender_doc_view/130491/130491')).status,expected);
  }
  await assert.rejects(inspectModernDocument({request:{get:async()=>({status:()=>429})}}, '/Tenders/tender_doc_view/130491/130491'), /request limit/);
});

const server = readFileSync(new URL('./server.js',import.meta.url),'utf8');
test('either source may fail while the other saves, with accurate counts and per-source history', async () => {
  for (const failed of ['existing','modern']) {
    const writes=[], history=[];
    const makePosts = source => {
      if (source===failed) throw Error(`${source} unavailable`);
      return Object.assign([{id:source==='existing'?'130491':'-130491'}],{checkedLgus:['sumilao'],failedLgus:[]});
    };
    const start=server.indexOf('async function runChecker('), end=server.indexOf('\n/*',start);
    const run=vm.runInNewContext(server.slice(start,end)+'\nrunChecker',{
      isRunning:false,currentRunId:0,checkerStartedAt:0,activeBrowser:null,CHECKER_FORCE_STOP_MS:60000,
      setTimeout,clearTimeout,console:{log(){},error(){}},WATCH_LGUS:['sumilao'],chromium:{},
      deleteOldNotificationLogs:async()=>{},deleteExpiredPosts:async()=>{},
      getExistingPostIds:async()=>Object.assign(new Set(),{allIds:new Set(['130491'])}),
      scrapePhilgeps:async()=>makePosts('existing'),scrapeModern:async()=>makePosts('modern'),
      savePostAndNotify:async p=>writes.push(p.id),sendDeadlineReminders:async()=>{},
      supabase:{rpc:async (name,row)=>{assert.equal(name,'record_philgeps_source_refresh');history.push(row);return{error:null};}},
    });
    const posts=await run();
    assert.equal(writes.length,1);
    assert.equal(posts.length,1);
    assert.equal(posts.newCount,failed==='existing'?1:0);
    assert.equal(posts.failedLgus[0],failed);
    assert.equal(history.length,2);
    assert.equal(history.find(r=>r.p_source!==failed).p_error,null);
    assert.match(history.find(r=>r.p_source===failed).p_error,/unavailable/);
    assert.match(posts.sourceErrors[failed],/unavailable/);
  }
});
