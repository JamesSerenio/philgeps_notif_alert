import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import vm from 'node:vm';
import express from 'express';
import { AUTOMATIC_CRON, scheduledSlot, secretMatches, manualAuthorization, publicRefreshLimit, createScrapeControl } from './scrape-control.js';

test('only 22 UTC schedules the daily 6 AM Philippine-time scrape', () => {
  assert.equal(AUTOMATIC_CRON, '0 22 * * *');
  for (let hour = 0; hour < 24; hour++) {
    const date = new Date(`2026-11-10T${String(hour).padStart(2, '0')}:00:00Z`);
    assert.equal(scheduledSlot(date) !== null, hour === 22);
    if (scheduledSlot(date)) assert.match(new Intl.DateTimeFormat('en', {
      timeZone: 'Asia/Manila', hour: 'numeric', hour12: true,
    }).format(date), /^6 AM$/);
  }
  assert.equal(scheduledSlot(new Date('2026-11-10T22:10:00Z')), '2026-11-10T22:00:00Z');
  assert.equal(scheduledSlot(new Date('2026-11-10T22:11:00Z')), null);
  const source = readFileSync(new URL('./server.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /cron\.schedule|setInterval\(/);
  assert.match(readFileSync(new URL('./railway-cron.toml', import.meta.url), 'utf8'), /cronSchedule = "0 22 \* \* \*"/);
});

test('cron authorization fails closed including missing configuration', () => {
  assert.equal(secretMatches(undefined, undefined), false);
  assert.equal(secretMatches('wrong', 'secret'), false);
  assert.equal(secretMatches('secret', 'secret'), true);
});

async function authorize(user, token = 'session', error = null) {
  let status, body, passed = false;
  const middleware = manualAuthorization({ auth: { getUser: async () => ({ data: { user }, error }) } }, 'owner@example.com');
  await middleware({ headers: token ? { authorization: `Bearer ${token}` } : {} }, {
    status(value) { status = value; return this; }, json(value) { body = value; }, set() {},
  }, () => { passed = true; });
  return { status, body, passed };
}
test('protected delivery refresh still needs a verified, allowlisted Supabase user', async () => {
  const user = { email: 'owner@example.com', email_confirmed_at: '2026-01-01' };
  assert.equal((await authorize(user)).passed, true);
  assert.equal((await authorize(user, null)).status, 401);
  assert.equal((await authorize(user, 'invalid', new Error())).status, 401);
  assert.equal((await authorize({ ...user, is_anonymous: true })).status, 403);
  assert.equal((await authorize({ ...user, email: 'other@example.com' })).status, 403);
  assert.equal((await authorize({ ...user, email_confirmed_at: null })).status, 403);
});

test('public notice refresh accepts signed-out callers and bounds request traffic', () => {
  let now = 0, calls = 0, code, retry;
  const limit = publicRefreshLimit({ limit: 2, now: () => now });
  const response = { set(k,v) { if (k === 'Retry-After') retry = v; }, status(v) { code = v; return this; }, json() {} };
  for (let i=0;i<3;i++) limit({headers:{}},response,()=>calls++);
  assert.equal(calls,2);
  assert.equal(code,429);
  assert.equal(retry,'60');
  now=60000;
  limit({headers:{}},response,()=>calls++);
  assert.equal(calls,3);
});

// Mock the atomic database claim while testing the real coordinator's lifecycle.
function store() {
  const state = { id: 1, run: null, last_success_at: null };
  let finishes = 0;
  return {
    state, get finishes() { return finishes; },
    from() { return { select() { return this; }, eq() { return this; }, single: async () => ({ data: { ...state } }) }; },
    async rpc(name, args) {
      if (name === 'claim_scrape_run') {
        if (state.run?.status === 'running') return { data: { accepted: false, reason: 'running', run: state.run } };
        state.run = { id: args.p_run_id, trigger: args.p_trigger, status: 'running' };
        state.lease_until = new Date(Date.now() + 30 * 60000).toISOString();
        return { data: { accepted: true, run: { ...state.run } } };
      }
      finishes++;
      if (state.run.id === args.p_run_id) state.run = { ...state.run, ...args.p_result };
      if (args.p_result.status === 'completed') state.last_success_at = new Date().toISOString();
      return {};
    },
  };
}
async function settled(db) {
  for (let i = 0; i < 100 && !db.finishes; i++) await new Promise(resolve => setImmediate(resolve));
  assert.equal(db.finishes, 1);
}

test('real HTTP routes allow signed-out refresh and polling, join one job, and keep cron private', async () => {
  const db = store(), app = express(), logs = [];
  let calls = 0, release;
  const pending = new Promise(resolve => { release = resolve; });
  const source = readFileSync(new URL('./server.js', import.meta.url), 'utf8');
  const start = source.indexOf('const scrapeControl =');
  const end = source.indexOf('\n/*', start);
  vm.runInNewContext(source.slice(start, end), {
    app, supabase: db, publicRefreshLimit, manualAuthorization, scheduledSlot, secretMatches,
    process: { env: { SCRAPER_CRON_SECRET: 'test-secret' } }, console,
    createScrapeControl: options => createScrapeControl({ ...options, log: line => logs.push(JSON.parse(line)) }),
    runChecker: async () => { calls++; return pending; },
  });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/check/status`)).status, 200);
    const initial = await fetch(`${base}/check`, { method: 'POST' });
    assert.equal(initial.status, 202);
    const started = await initial.json();
    const repeated = await Promise.all(Array.from({length:5}, async () => {
      const response = await fetch(`${base}/check`, { method: 'POST' });
      assert.equal(response.status, 200);
      return response.json();
    }));
    assert.ok(repeated.every(item => item.run.id === started.run.id && item.reason === 'running'));
    assert.equal(calls, 1);
    assert.equal((await fetch(`${base}/internal/check`, { method:'POST' })).status, 401);
    assert.equal((await fetch(`${base}/internal/check`)).status, 401);
    release(Object.assign([{id:'123'},{id:'-130491'}], {newCount:1,checkedLgus:['existing','modern'],failedLgus:[]}));
    await settled(db);
    const result = await (await fetch(`${base}/check/status`)).json();
    assert.equal(result.run.id, started.run.id);
    assert.equal(result.run.status, 'completed');
    assert.equal(result.run.newCount, 1);
    assert.equal(logs.filter(item => item.event === 'SCRAPE_START').length, 1);
    assert.equal(logs.filter(item => item.event === 'SCRAPE_FINISH').length, 1);
    assert.equal(logs[0].trigger, 'MANUAL');
  } finally {
    release(Object.assign([], {newCount:0,checkedLgus:[],failedLgus:[]}));
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});

test('manual and automatic requests share one run across coordinators and log accurate totals', async () => {
  assert.equal(scheduledSlot(new Date('2026-11-10T12:00:00Z')), null);
  const db = store(), logs = [];
  let release, calls = 0;
  const pending = new Promise(resolve => { release = resolve; });
  const run = async assertLease => { calls++; await assertLease(); return pending; };
  const a = createScrapeControl({ supabase: db, run, log: s => logs.push(JSON.parse(s)) });
  const b = createScrapeControl({ supabase: db, run, log() {} });
  const started = await a.start('MANUAL');
  const duplicate = await b.start('AUTOMATIC', '2026-11-10T22:00:00Z');
  assert.equal(duplicate.accepted, false);
  assert.equal(duplicate.run.id, started.run.id);
  assert.equal(calls, 1);
  const posts = [{ id: 'new' }, { id: 'existing' }];
  Object.assign(posts, { newCount: 1, checkedLgus: ['sumilao'], failedLgus: [] });
  release(posts);
  await settled(db);
  assert.equal(db.state.run.status, 'completed');
  assert.equal(db.state.run.refreshedCount, 1);
  assert.equal(db.state.run.newCount, 1);
  assert.ok(db.state.last_success_at);
  assert.equal(logs[0].trigger, 'MANUAL');
  assert.ok(logs[1].durationMs >= 0);
  assert.ok(logs[1].finishedAt);
});

test('Playwright browser and context close on success and scraping errors', async () => {
  const source = readFileSync(new URL('./server.js', import.meta.url), 'utf8');
  const start = source.indexOf('async function scrapePhilgeps(');
  const end = source.indexOf('\n/*', start);
  for (const mode of ['success', 'lgu-failure', 'page-failure']) {
    const closed = [];
    const context = {
      newPage: async () => {
        if (mode === 'page-failure') throw new Error('Page creation failed');
        return { setDefaultNavigationTimeout() {}, setDefaultTimeout() {} };
      },
      close: async () => { closed.push('context'); },
    };
    const scrape = vm.runInNewContext(source.slice(start, end) + '\nscrapePhilgeps', {
      currentRunId: 1, activeBrowser: null, WATCH_LGUS: ['sumilao'],
      console: { log() {}, error() {} },
      chromium: { launch: async () => ({ newContext: async () => context,
        close: async () => { closed.push('browser'); } }) },
      searchPhilgepsByKeyword: async () => {
        if (mode === 'lgu-failure') throw new Error('PhilGEPS unavailable');
        return [];
      },
    });
    if (mode === 'page-failure') await assert.rejects(scrape(new Set(), 1), /Page creation failed/);
    else {
      const posts = await scrape(new Set(), 1);
      assert.equal(posts.failedLgus.length, mode === 'lgu-failure' ? 1 : 0);
    }
    assert.deepEqual(closed, ['context', 'browser']);
  }
});

test('partial LGU failure and thrown failure never update last-success time', async () => {
  for (const thrown of [false, true]) {
    const db = store();
    const control = createScrapeControl({ supabase: db, log() {}, run: async () => {
      if (thrown) throw Error('PhilGEPS unavailable');
      return Object.assign([], { newCount: 0, checkedLgus: ['sumilao'], failedLgus: ['sumilao'] });
    } });
    await control.start('AUTOMATIC', '2026-11-10T22:00:00Z');
    await settled(db);
    assert.equal(db.state.run.status, 'failed');
    assert.equal(db.state.last_success_at, null);
  }
});

test('cooldown rejection does not launch a scraper', async () => {
  const control = createScrapeControl({ supabase: { rpc: async () => ({ data: { accepted: false, reason: 'rate_limited' } }) },
    run: () => assert.fail('must not run') });
  assert.equal((await control.start('MANUAL')).reason, 'rate_limited');
});

test('expired status reports failure rather than continuing to report running', async () => {
  const db = store();
  db.state.run = { status: 'running', id: 'crashed' };
  db.state.lease_until = '2020-01-01T00:00:00Z';
  const control = createScrapeControl({ supabase: db, run() {} });
  assert.equal((await control.snapshot()).run.status, 'failed');
});

test('cron worker authenticates, polls completion, and exits (success and failure)', async () => {
  for (const status of ['completed', 'failed']) {
    const requests = [];
    const server = createServer((req, res) => {
      requests.push(req.method);
      assert.equal(req.headers.authorization, 'Bearer test-secret');
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(req.method === 'POST'
        ? { accepted: true, run: { id: 'run' } }
        : { run: { id: 'run', status, error: status === 'failed' ? 'Test failure' : null } }));
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const child = spawn(process.execPath, [new URL('./cron-worker.js', import.meta.url).pathname.replace(/^\/(\w:)/, '$1')], {
        env: { ...process.env, SCRAPER_BACKEND_URL: `http://127.0.0.1:${server.address().port}`, SCRAPER_CRON_SECRET: 'test-secret' },
        stdio: 'ignore',
      });
      const timeout = setTimeout(() => child.kill(), 10000);
      const [code] = await once(child, 'exit');
      clearTimeout(timeout);
      assert.equal(code, status === 'completed' ? 0 : 1);
      assert.deepEqual(requests, ['POST', 'GET']);
    } finally { await new Promise(resolve => server.close(resolve)); }
  }
});
