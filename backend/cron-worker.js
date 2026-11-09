// This service only triggers the existing HTTP scraper and exits after completion.
import { setTimeout as delay } from 'node:timers/promises';

const base = process.env.SCRAPER_BACKEND_URL;
const secret = process.env.SCRAPER_CRON_SECRET;
if (!base || !secret) throw new Error('SCRAPER_BACKEND_URL and SCRAPER_CRON_SECRET are required.');
const headers = { authorization: `Bearer ${secret}` };
async function request(method) {
  const response = await fetch(new URL('/internal/check', base), {
    method, headers, signal: AbortSignal.timeout(30000),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  return body;
}
try {
  const result = await request('POST');
  if (result.reason === 'scheduled_already' || result.reason === 'outside_schedule') {
    console.log('Automatic trigger skipped:', result.reason);
  } else {
    const id = result.run.id;
    const deadline = Date.now() + 25 * 60 * 1000;
    while (true) {
      const { run } = await request('GET');
      if (run?.id !== id) throw new Error('Scrape status changed unexpectedly.');
      if (run.status === 'failed') throw new Error(run.error || 'Scrape failed.');
      if (run.status === 'completed') { console.log(JSON.stringify(run)); break; }
      if (Date.now() >= deadline) throw new Error('Timed out waiting for automatic scrape.');
      await delay(10000);
    }
  }
} catch (error) {
  console.error('Automatic worker failed:', error.message);
  process.exitCode = 1;
}
