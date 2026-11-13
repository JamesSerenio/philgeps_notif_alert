// Public portal adapter. No credentials, private APIs, or access-control bypasses.
export const MODERN_INDEX = 'https://philgeps.gov.ph/Indexes/index';
// Existing official reference IDs are positive. A negative numeric namespace
// supports both legacy text and integer primary/FK columns without rekeying them.
export function modernStorageId(noticeId) {
  if (!/^[1-9]\d*$/.test(noticeId)) throw new Error('Invalid Modern notice ID');
  return `-${noticeId}`;
}
// The portal's agency field does not match a bare municipality substring.
export function modernAgency(lgu) {
  const province = /^(talakag|libona|malitbog|sumilao|impasugong|impasug-ong|baungon|manolo fortich)$/i.test(lgu) ? 'BUKIDNON' : 'MISAMIS ORIENTAL';
  const name = /^impasugong$/i.test(lgu) ? 'IMPASUG-ONG' : lgu.toUpperCase();
  return `MUNICIPALITY OF ${name} ${province}`;
}
export function officialModernUrl(value) {
  try {
    const url = new URL(value, MODERN_INDEX);
    return url.origin === 'https://philgeps.gov.ph' && /^\/Indexes\/viewLiveTenderDetails\/\d+$/.test(url.pathname) ? url.href : null;
  } catch { return null; }
}
export function modernDate(value) {
  const m = value?.trim().match(/^(\d{1,2})-([A-Za-z]{3})-(\d{4})(?:\s+(\d{1,2}):(\d{2})\s*(AM|PM))?/);
  if (!m) return null;
  const month = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(m[2].toLowerCase()) + 1;
  if (!month) return null;
  const hour = m[4] ? Number(m[4]) % 12 + (m[6] === 'PM' ? 12 : 0) : 0;
  return new Date(`${m[3]}-${String(month).padStart(2,'0')}-${m[1].padStart(2,'0')}T${String(hour).padStart(2,'0')}:${m[5] || '00'}:00+08:00`).toISOString();
}

// Functions run inside the browser; also used against captured official fixtures.
export function readModernRows() {
  return [...document.querySelectorAll('a[href*="/Indexes/viewLiveTenderDetails/"]')].map(a => {
    const cells = [...(a.closest('tr')?.querySelectorAll('td') || [])].map(c => c.textContent.trim().replace(/\s+/g,' '));
    return { url: a.href, referenceNumber: cells[0], title: cells[1], procurementMode: cells[2], classification: cells[3], procuringEntity: cells[4], postingDate: cells[5], closingDate: cells[6] };
  }).filter(r => r.title);
}
export function readModernDetails() {
  const root = document.querySelector('#block_content');
  if (!root) throw new Error('Modern notice details unavailable or access required.');
  const text = root.innerText;
  const field = label => {
    const at = text.indexOf(label);
    return at < 0 ? '' : text.slice(at + label.length).replace(/^\s*:\s*/, '').trim().split('\n').find(s => s.trim())?.trim() || '';
  };
  return { areaOfDelivery: field('Delivery/Project Location:'), deliveryPeriod: field('Delivery Period:'), abc: field('Approved Budget of the Contract:'), preview: root.querySelector('a[href_path*="/Tenders/tender_doc_view/"]')?.getAttribute('href_path') || '' };
}

export async function searchModern(page, criteria) {
  const response = await page.goto(MODERN_INDEX, { waitUntil: 'domcontentloaded' });
  if (!response?.ok()) throw new Error(`Modern PhilGEPS HTTP ${response?.status()}`);
  const fields = { reference: 'searchRefNo', title: 'searchNoticeTitle', agency: 'searchAgencyName', publicationFrom: 'searchPublishDateFrom', publicationTo: 'searchPublishDateTo', closingFrom: 'searchClosingDateFrom', closingTo: 'searchClosingDateTo', classification: 'searchClassification', mode: 'searchModeProc' };
  await page.locator('#frmSearch').waitFor();
  await Promise.all([page.waitForNavigation({ waitUntil: 'domcontentloaded' }), page.evaluate(({ criteria, fields }) => {
    const form = document.querySelector('#frmSearch');
    for (const [key, name] of Object.entries(fields)) if (criteria[key]) form.elements[name].value = criteria[key];
    // Native POST retains the portal's session cookie and CSRF token.
    form.submit();
  }, { criteria, fields })]);
  await page.locator('#frmSearch').waitFor();
  const rows = await page.evaluate(readModernRows);
  if (rows.length >= 100 || await page.locator('a[rel="next"]').count()) {
    throw new Error('Modern search may be truncated; narrow the query before retrying.');
  }
  return rows;
}

export async function inspectModernDocument(page, preview) {
  if (!/^\/Tenders\/tender_doc_view\/\d+\/\d+$/.test(preview)) return { status: 'unverified', url: null };
  const url = new URL(preview, MODERN_INDEX).href;
  const response = await page.request.get(url, { timeout: 30000, maxRedirects: 0 });
  if (response.status() === 429) {
    const error = new Error('Modern PhilGEPS request limit reached. Retry after the portal permits access.');
    error.code = 'MODERN_RATE_LIMIT';
    throw error;
  }
  if ([301,302,303,401,403].includes(response.status())) return { status: 'access_required', url: MODERN_INDEX };
  if (!response.ok()) return { status: 'unverified', url: null };
  const type = response.headers()['content-type'] || '';
  if (type.includes('application/pdf') && (await response.body()).subarray(0,5).toString() === '%PDF-') {
    return { status: /attachment/i.test(response.headers()['content-disposition'] || '') ? 'download' : 'preview', url };
  }
  // An HTML wrapper or a Preview label does not prove a document is available.
  const html = await response.text();
  if (/please\s+log(?:in|\s+in)|not authorized|access denied|payment required/i.test(html)) return { status: 'access_required', url: MODERN_INDEX };
  return { status: 'unverified', url: null };
}

export async function scrapeModern({ chromium, watchLgus, assertLease, onBrowser }) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox','--disable-dev-shm-usage'] });
  onBrowser(browser);
  const posts = new Map();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(30000);
    page.setDefaultNavigationTimeout(45000);
    for (const lgu of watchLgus) {
      await assertLease();
      const rows = await searchModern(page, { agency: modernAgency(lgu) });
      for (const row of rows) {
        const url = officialModernUrl(row.url);
        if (!url) continue;
        const noticeId = new URL(url).pathname.split('/').pop();
        const id = modernStorageId(noticeId);
        if (posts.has(id)) continue;
        await assertLease();
        const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
        if (!response?.ok()) throw new Error(`Modern notice HTTP ${response?.status()}. Retry later.`);
        const details = await page.evaluate(readModernDetails);
        if (!/bukidnon|misamis oriental/i.test(details.areaOfDelivery)) continue;
        const document = await inspectModernDocument(page, details.preview).catch(error => {
          if (error.code === 'MODERN_RATE_LIMIT') throw error;
          return { status: 'unverified', url: null };
        });
        posts.set(id, { ...row, ...details, id, source: 'modern', officialNoticeId: noticeId, url, lgu, postingDate: modernDate(row.postingDate), closingDate: modernDate(row.closingDate), abc: Number(details.abc.replace(/[^\d.]/g,'')) || 0, budgetType: 'ABC', documentStatus: document.status, documentUrl: document.url });
        await page.waitForTimeout(500);
      }
      await page.waitForTimeout(500);
    }
    return [...posts.values()];
  } finally { await browser.close(); }
}
