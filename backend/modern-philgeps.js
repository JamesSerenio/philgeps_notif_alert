import { collectModernProvince } from './modern-pagination.js';
import { fold, matchesLgu, portalLog, publicGoto, safeError } from './portal-runtime.js';
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
  lgu = fold(lgu);
  const province = /^(talakag|libona|malitbog|sumilao|impasugong|impasug-ong|baungon|manolo fortich)$/i.test(lgu) ? 'BUKIDNON' : 'MISAMIS ORIENTAL';
  const name = /^impasugong$/i.test(lgu) ? 'IMPASUG-ONG' : lgu.toUpperCase();
  return `MUNICIPALITY OF ${name} ${province}`;
}
export function officialModernUrl(value) {
  try {
    const url = new URL(value, MODERN_INDEX);
    return url.origin === 'https://philgeps.gov.ph' && /^\/Indexes\/viewLiveTenderDetails\/[1-9]\d*(?:\/OPEN_MORE)?$/i.test(url.pathname) ? url.href : null;
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
  if (criteria.agency && rows.some(row => fold(row.procuringEntity) !== fold(criteria.agency))) {
    throw new Error('Modern index ignored the agency filter; use the verified province-paginated search.');
  }
  if (rows.length >= 100) {
    throw new Error('Modern index reached its 100-row display bound; use the province-paginated search.');
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
  if ([301,302,303,401,403].includes(response.status())) return { status: 'access_required', url: MODERN_INDEX, httpStatus:response.status() };
  if (!response.ok()) return { status: 'unverified', url: null, httpStatus:response.status() };
  const type = response.headers()['content-type'] || '';
  if (type.includes('application/pdf') && (await response.body()).subarray(0,5).toString() === '%PDF-') {
    return { status: /attachment/i.test(response.headers()['content-disposition'] || '') ? 'download' : 'preview', url, httpStatus:response.status() };
  }
  // An HTML wrapper or a Preview label does not prove a document is available.
  const html = await response.text();
  if (/please\s+log(?:in|\s+in)|not authorized|access denied|payment required/i.test(html)) return { status: 'access_required', url: MODERN_INDEX, httpStatus:response.status() };
  return { status: 'unverified', url: null, httpStatus:response.status() };
}

export async function scrapeModern({ chromium, watchLgus, assertLease, onBrowser, runId, log = console.log }) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox','--disable-dev-shm-usage'] });
  onBrowser(browser);
  const posts = new Map();
  const checkedLgus = [], failedLgus = [], queryErrors = {}, reports = [];
  let retrievedCount = 0, eligibleCount = 0;
  let sourceLimited = false;
  const record = row => { const item=portalLog({runId,...row},log);reports.push(item);return item; };
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(30000);
    page.setDefaultNavigationTimeout(45000);
    await publicGoto(page,MODERN_INDEX,'Modern PhilGEPS');
    const detailPage = await context.newPage();
    detailPage.setDefaultNavigationTimeout(45000);
    for (const province of ['Bukidnon','Misamis Oriental']) {
      if(sourceLimited) break;
      let rows = [];
      try {
        const result = await collectModernProvince(page,province,readModernRows,{assertLease,
          log: text => { const item=JSON.parse(text);item.runId=runId;reports.push(item);log(JSON.stringify(item)); }});
        rows=result.rows;
        if(result.failures.length) {
          failedLgus.push(province);queryErrors[province]=result.failures.map(item=>item.error).join('; ');
        }
      } catch(error) {
        rows=error.partialRows || [];
        failedLgus.push(province);queryErrors[province]=safeError(error);
        record({source:'modern',query:province,httpStatus:error.httpStatus ?? null,parsing:'failed',error:safeError(error)});
        if(error.accessLimited) { retrievedCount+=rows.length;checkedLgus.push(province);break; }
      }
      checkedLgus.push(province);
      retrievedCount += rows.length;
      for (const row of rows) {
        const lgu = watchLgus.find(item=>matchesLgu(`${row.title} ${row.procuringEntity}`,item));
        if (!lgu) continue;
        const url = officialModernUrl(row.url);
        if (!url) continue;
        const noticeId = new URL(url).pathname.match(/viewLiveTenderDetails\/(\d+)/i)[1];
        const id = modernStorageId(noticeId);
        if (posts.has(id)) continue;
        const closingDate = modernDate(row.closingDate), postingDate = modernDate(row.postingDate);
        if (!closingDate || !postingDate) {
          if(!failedLgus.includes(province)) failedLgus.push(province);
          queryErrors[`${province}/${noticeId}`]='Notice dates not verified';
          continue;
        }
        if (Date.parse(closingDate)<Date.now()) continue;
        await assertLease();
        let details;
        try {
          const status=await publicGoto(detailPage,url,'Modern PhilGEPS');
          details=await detailPage.evaluate(readModernDetails);
          record({source:'modern',query:province,noticeId,httpStatus:status,parsing:'notice_ok'});
        } catch(error) {
          if(!failedLgus.includes(province)) failedLgus.push(province);
          queryErrors[`${province}/${noticeId}`]=safeError(error);
          record({source:'modern',query:province,noticeId,httpStatus:error.httpStatus ?? null,parsing:'notice_failed',error:safeError(error)});
          if(error.accessLimited) {sourceLimited=true;break;}
          continue;
        }
        if (!/bukidnon|misamis oriental/i.test(details.areaOfDelivery)) continue;
        eligibleCount++;
        let limited = false;
        const document = await inspectModernDocument(detailPage, details.preview).catch(error => {
          record({source:'modern',query:province,noticeId,httpStatus:error.code==='MODERN_RATE_LIMIT'?429:null,parsing:'document_unverified',error:safeError(error)});
          if (error.code === 'MODERN_RATE_LIMIT') {
            limited=true;sourceLimited=true;
            if(!failedLgus.includes(province)) failedLgus.push(province);
            queryErrors[province]=safeError(error);
          }
          return { status: 'unverified', url: null };
        });
        record({source:'modern',query:province,noticeId,httpStatus:document.httpStatus ?? null,parsing:`document_${document.status}`});
        posts.set(id, { ...row, ...details, id, source: 'modern', officialNoticeId: noticeId, url, lgu:fold(lgu), postingDate, closingDate, abc: Number(details.abc.replace(/[^\d.]/g,'')) || 0, budgetType: 'ABC', documentStatus: document.status, documentUrl: document.url });
        if(limited) break;
        await page.waitForTimeout(500);
      }
      await page.waitForTimeout(500);
    }
    return Object.assign([...posts.values()],{checkedLgus,failedLgus,queryErrors,reports,retrievedCount,eligibleCount});
  } catch(error) {
    failedLgus.push('source initialization');queryErrors['source initialization']=safeError(error);
    record({source:'modern',query:'source initialization',httpStatus:error.httpStatus ?? null,parsing:'failed',error:safeError(error)});
    return Object.assign([...posts.values()],{checkedLgus,failedLgus,queryErrors,reports,retrievedCount,eligibleCount});
  } finally { await browser.close().catch(()=>{}); }
}
