import assert from 'node:assert/strict';
import {test} from 'node:test';
import {isBiddingProjectClosed} from 'file:///C:/Projects/philgeps-editor/src/lib/projectFormatters.js';

test('BDocs visibility uses official deadlines and the full Philippine manual day',()=>{
  const before=Date.parse('2026-11-19T23:59:59+08:00');
  const after=Date.parse('2026-11-20T00:00:00+08:00');
  const project={id:'unchanged',manual_deadline:'2026-11-19',closing_date:'2026-12-01T12:00:00+08:00',is_bidding_doc:true};
  const original=structuredClone(project);
  assert.equal(isBiddingProjectClosed(project,before),false);
  assert.equal(isBiddingProjectClosed(project,after),true);
  assert.equal(isBiddingProjectClosed({closing_date:'2026-11-19T10:00:00+08:00'},Date.parse('2026-11-19T09:59:59+08:00')),false);
  assert.equal(isBiddingProjectClosed({closing_date:'2026-11-19T10:00:00+08:00'},Date.parse('2026-11-19T10:00:00+08:00')),true);
  assert.equal(isBiddingProjectClosed({status:' CLOSED '},before),true);
  assert.equal(isBiddingProjectClosed({closing_date:'not verified'},before),false);
  assert.equal(isBiddingProjectClosed({},before),false);
  assert.deepEqual(project,original);
});
