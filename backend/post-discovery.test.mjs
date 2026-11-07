import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const source = readFileSync(new URL('./server.js', import.meta.url), 'utf8');
function load(name, extra = {}) {
  const start = source.indexOf('async function ' + name + '(');
  const end = source.indexOf('\n/*', start);
  return vm.runInNewContext(source.slice(start, end) + '\n' + name, {
    console: { log() {}, error() {} }, cleanText: s => s.trim(), ...extra,
  });
}
test('detail refresh is not a new reference; all existing IDs retained', async () => {
  const rows = [{ id: '13306152', delivery_period: '' }, { id: 'complete', delivery_period: '30 days' }];
  const ids = await load('getExistingPostIds', { getStoredPosts: async () => rows })();
  assert.equal(ids.has('13306152'), false);
  assert.equal(ids.has('complete'), true);
  assert.equal(ids.allIds.has('13306152'), true);
});
test('paginates all stored posts including closed and noncanonical LGU records', async () => {
  const rows = Array.from({ length: 1002 }, (_, id) => ({ id, lgu: 'LGU SUMILAO', closing_date: '2020-01-01' }));
  const calls=[];
  const supabase={from(){return{select(){return this;},order(key,options){calls.push([key,options.ascending]);return this;},
    range:async(from,to)=>({data:rows.slice(from,to+1),error:null})};}};
  const result=await load('getStoredPosts',{supabase})();
  assert.equal(result.length,1002);
  assert.deepEqual(calls.slice(0,2),[['created_at',false],['id',false]]);
});
test('failed database reads abort rather than treating existing references as new', async () => {
  await assert.rejects(load('getExistingPostIds',{getStoredPosts:async()=>{throw Error('read failed');}})(),/read failed/);
});
for(const existing of [{created_at:'2026-10-30T18:31:19.257721Z'},null]) {
  test(existing?'upsert preserves first discovery and saved decisions':'late publication discovery gets NEW without changing publication date',async()=>{
    let submitted; let alertCount=0;
    const supabase={from(table){return{
      select(){return this;},eq(){return this;},
      maybeSingle:async()=>({data:table==='philgeps_posts'?existing:null,error:null}),
      upsert(row,options){submitted=row;assert.equal(options.onConflict,'id');return this;},
      single:async()=>({data:{created_at:existing?.created_at??'2026-11-07T21:48:00Z'},error:null}),
    };}};
    const recent=value=>value==='2026-11-07T21:48:00Z'||(!existing&&value!==undefined);
    await load('savePostAndNotify',{supabase,isPostedRecently:recent,sendNotification:async()=>{alertCount++;}})({
      id:'13321123',postingDate:'2026-10-01T00:00:00Z',referenceNumber:'13321123'
    });
    assert.equal(submitted.posting_date,'2026-10-01T00:00:00Z');
    for(const key of ['created_at','first_seen_at','is_bidding_doc','is_done','done_at'])assert.equal(Object.hasOwn(submitted,key),false,key);
    assert.equal(submitted.status,existing?'old':'new');
    assert.equal(alertCount,existing?0:1);
  });
}
test('24-hour notification boundary excludes expired, future and invalid discovery dates',()=>{
  const start=source.indexOf('function isPostedRecently(');
  const end=source.indexOf('\nfunction ',start+1);
  const FixedDate=class extends Date {static now(){return Date.parse('2026-11-08T05:48:00+08:00');}};
  const recent=vm.runInNewContext(source.slice(start,end)+'\nisPostedRecently',{Date:FixedDate});
  assert.equal(recent('2026-11-07T05:48:00+08:00'),false);
  assert.equal(recent('2026-11-08T05:48:00+08:00'),true);
  assert.equal(recent('2026-11-09T05:48:00+08:00'),false);
  assert.equal(recent(null),false);
});
