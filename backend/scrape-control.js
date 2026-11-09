import { randomUUID, timingSafeEqual } from 'node:crypto';

export const AUTOMATIC_CRON = '0 22 * * *';
export const MANUAL_COOLDOWN_SECONDS = 120;

export function scheduledSlot(now = new Date()) {
  const hour = now.getUTCHours();
  if (hour !== 22 || now.getUTCMinutes() > 10) return null;
  return `${now.toISOString().slice(0, 10)}T${hour}:00:00Z`;
}

export function secretMatches(actual, expected) {
  if (!actual || !expected) return false;
  const a = Buffer.from(actual), b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

// Authorization is checked against Supabase Auth, never a client-supplied role.
export function manualAuthorization(supabase, allowedEmails) {
  const allowed = new Set(allowedEmails.split(',').map(s => s.trim().toLowerCase()).filter(Boolean));
  // Bound authentication traffic as well as scrape starts. No growing IP map.
  let windowStarted = Date.now(), requests = 0;
  return async (req, res, next) => {
    if (Date.now() - windowStarted >= 60000) { windowStarted = Date.now(); requests = 0; }
    if (++requests > 300) {
      res.set('Retry-After', '60');
      return res.status(429).json({ error: 'Too many requests. Retry in one minute.' });
    }
    const token = req.headers.authorization?.match(/^Bearer (.+)$/i)?.[1];
    if (!token) return res.status(401).json({ error: 'Sign in to request a scrape.' });
    try {
      const { data, error } = await supabase.auth.getUser(token);
      const user = data?.user;
      if (error || !user) return res.status(401).json({ error: 'Session expired. Sign in again.' });
      if (!user.email_confirmed_at || user.is_anonymous || !allowed.has(user.email?.toLowerCase())) {
        return res.status(403).json({ error: 'This account is not authorized to request scrapes.' });
      }
      return next();
    } catch {
      return res.status(503).json({ error: 'Unable to verify your session.' });
    }
  };
}

export function createScrapeControl({ supabase, run, log = console.log }) {
  let active = false;
  async function snapshot() {
    const { data, error } = await supabase.from('scrape_control').select('*').eq('id', 1).single();
    if (error) throw error;
    if (data.run?.status === 'running' && new Date(data.lease_until).getTime() <= Date.now()) {
      data.run = { ...data.run, status: 'failed', error: 'Scrape interrupted or timed out. Retry the update.' };
    }
    return data;
  }
  async function start(trigger, slot = null) {
    if (active) return { accepted: false, reason: 'running', run: (await snapshot()).run };
    const id = randomUUID();
    const { data, error } = await supabase.rpc('claim_scrape_run', {
      p_run_id: id, p_trigger: trigger, p_slot: slot,
      p_cooldown_seconds: MANUAL_COOLDOWN_SECONDS,
    });
    if (error) throw error;
    if (!data.accepted) return data;
    // The DB claim serializes all HTTP replicas and cron invocations.
    active = true;
    void execute(id, trigger);
    return data;
  }
  async function execute(id, trigger) {
    const started = Date.now();
    log(JSON.stringify({ event: 'SCRAPE_START', runId: id, trigger, startedAt: new Date(started).toISOString() }));
    let result;
    try {
      const assertLease = async () => {
        const state = await snapshot();
        if (state.run?.id !== id || state.run.status !== 'running') {
          throw new Error('Scraping lease expired or changed.');
        }
      };
      const posts = await run(assertLease);
      if (!posts) throw new Error('Scraper did not complete.');
      result = {
        status: posts.failedLgus.length ? 'failed' : 'completed',
        newCount: posts.newCount, refreshedCount: posts.length - posts.newCount,
        checkedLgus: posts.checkedLgus, failedLgus: posts.failedLgus,
        error: posts.failedLgus.length ? 'Some LGUs could not be checked. Retry the update.' : null,
      };
    } catch (error) {
      result = { status: 'failed', newCount: 0, refreshedCount: 0,
        checkedLgus: [], failedLgus: [], ...error.scrapeStats, error: error.message };
    }
    result.finishedAt = new Date().toISOString();
    result.durationMs = Date.now() - started;
    log(JSON.stringify({ event: 'SCRAPE_FINISH', runId: id, trigger, ...result }));
    try {
      const { error } = await supabase.rpc('finish_scrape_run', { p_run_id: id, p_result: result });
      if (error) throw error;
    } catch (error) {
      console.error('Unable to persist scrape completion:', error.message);
    } finally {
      active = false;
    }
  }
  return { snapshot, start };
}
