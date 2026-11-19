import { failureStatus, fold, portalLog, publicGoto, publicNavigation, safeError } from './portal-runtime.js';
export const MODERN_MORE = 'https://philgeps.gov.ph/Indexes/viewMoreOpenTenders';
export function readModernPage() {
  const pager = document.querySelector('.paginator')?.innerText || '';
  const m = pager.replace(/,/g,'').match(/Page\s+(\d+)\s+of\s+(\d+).*?out of\s+(\d+)\s+total/s);
  const form = document.querySelector('#searchKeyword')?.form;
  return {
    page: m ? Number(m[1]) : null, pages: m ? Number(m[2]) : null, total: m ? Number(m[3]) : null,
    area: form?.elements.searchAreaDel?.value || '',
    keyword: form?.elements.searchKeyword?.value || '',
    from: form?.elements.searchPublishDateFrom?.value || '', to: form?.elements.searchPublishDateTo?.value || '',
    next: document.querySelector('.paginator a[rel="next"]')?.href || null,
  };
}
export const portalDate = date => `${String(date.getUTCDate()).padStart(2,'0')}-${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.getUTCMonth()]}-${date.getUTCFullYear()}`;
export async function postModernPage(page, filters, next = null) {
  if (next) {
    const url = new URL(next,MODERN_MORE);
    if (url.origin !== 'https://philgeps.gov.ph' || !/^\/indexes\/view-more-open-tenders$/i.test(url.pathname)) throw Error('Unexpected Modern pagination link');
  }
  await page.locator('#searchKeyword').waitFor();
  return publicNavigation(page,()=>page.evaluate(({filters,next}) => {
      const form = document.querySelector('#searchKeyword').form;
      // POST every page. The portal's GET paginator silently drops its filters.
      form.action = next || 'https://philgeps.gov.ph/Indexes/viewMoreOpenTenders';
      form.elements.searchAreaDel.value = filters.area;
      form.elements.searchKeyword.value = filters.keyword || '';
      form.elements.searchPublishDateFrom.value = filters.from || '';
      form.elements.searchPublishDateTo.value = filters.to || '';
      form.submit();
    },{filters,next}),'Modern PhilGEPS');
}
export async function collectModernProvince(page, area, readRows, { maxPages = 50, assertLease = async()=>{}, log = console.log } = {}) {
  const rows = new Map(), failures = [], reports = [];
  async function collect(from = null, to = null, depth = 0) {
    const filters = {area,from:from ? portalDate(from) : '',to:to ? portalDate(to) : ''};
    let status = null, lastPage = 0;
    try {
      await assertLease();
      await publicGoto(page, MODERN_MORE, 'Modern PhilGEPS');
      status = await postModernPage(page,filters);
      const signatures = new Set();
      let expectedTotal = null;
      const queryIds = new Set();
      for (let number=1; number<=maxPages; number++) {
        await assertLease();
        const info = await page.evaluate(readModernPage);
        const batch = await page.evaluate(readRows);
        lastPage = number;
        if (fold(info.area) !== fold(area) || info.from !== filters.from || info.to !== filters.to) throw Error('Modern portal dropped province/date filters');
        if (info.page !== number || info.total === null) throw Error('Modern pagination metadata not verified');
        // Keep verified parent-page rows even if a later split/query fails.
        for (const row of batch) rows.set(row.referenceNumber,row);
        if (number === 1 && info.pages > maxPages) {
          const start = from || new Date('2000-01-01T00:00:00Z');
          const end = to || new Date(new Date(Date.now()+8*3600000).toISOString().slice(0,10)+'T00:00:00Z');
          const days = Math.round((end-start)/86400000);
          if (days > 0 && depth < 20) {
            const middle = new Date(start.getTime()+Math.floor(days/2)*86400000);
            reports.push(portalLog({source:'modern',query:filters,httpStatus:status,parsing:'split_date_range',pages:info.pages,total:info.total},log));
            await collect(start,middle,depth+1);
            await collect(new Date(middle.getTime()+86400000),end,depth+1);
            return;
          }
        }
        if (expectedTotal === null) expectedTotal = info.total;
        if (info.total !== expectedTotal) throw Error('Modern result total changed during pagination; coverage incomplete');
        const signature = batch.map(row=>row.referenceNumber).join('|');
        if (signatures.has(signature) && batch.length) throw Error('Modern pagination repeated the same result page');
        signatures.add(signature);
        for (const row of batch) { rows.set(row.referenceNumber,row);queryIds.add(row.referenceNumber); }
        reports.push(portalLog({source:'modern',query:filters,httpStatus:status,parsing:'ok',page:number,pages:info.pages,rows:batch.length,total:info.total},log));
        if (!info.next) {
          if (number !== info.pages || queryIds.size !== expectedTotal) throw Error(`Modern coverage mismatch: ${queryIds.size} of ${expectedTotal} records`);
          return;
        }
        if (number === maxPages) throw Error('Modern single-day result limit reached; partial coverage retained');
        await page.waitForTimeout(500);
        status = await postModernPage(page,filters,info.next);
      }
    } catch(error) {
      const record=portalLog({source:'modern',query:filters,httpStatus:failureStatus(error,status),parsing:'failed',page:lastPage,error:safeError(error)},log);
      reports.push(record);failures.push(record);
      if(error.accessLimited) throw Object.assign(error,{partialRows:[...rows.values()],reports,failures});
    }
  }
  await collect();
  return {rows:[...rows.values()],failures,reports};
}
