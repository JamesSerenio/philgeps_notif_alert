import { failureStatus, fold, matchesLgu, portalLog, publicGoto, publicNavigation, safeError } from './portal-runtime.js';
export const EXISTING_SEARCH = 'https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashOpportunitiesSearchUI.aspx?menuIndex=3&ClickFrom=OpenOpp&Result=3';
export async function advanceExisting(page) {
  const selector = '#pgCtrlDetailedSearch_pageDropDownList';
  const control = page.locator(selector);
  if (await control.count()) {
    const next = await control.evaluate(select => select.selectedIndex+1 < select.options.length ? select.options[select.selectedIndex+1].value : null);
    if (next === null) return null;
    return publicNavigation(page,()=>control.selectOption(next),'Existing PhilGEPS');
  }
  const next = await page.evaluate(() => {
    return [...document.querySelectorAll('a')].find(a => /^next$/i.test(a.innerText.replace(/[<>›»]/g,'').trim()) && a.getAttribute('href') && !/disabled/i.test(a.className))?.getAttribute('href') || null;
  });
  if (!next) return null;
  return publicNavigation(page,()=>page.locator('a').filter({hasText:/<?next>?/i}).first().click(),'Existing PhilGEPS');
}
export async function searchExisting({page,keyword,existingPostIds,isActive,getBidDetails,readRows,parseDate,isStillActive,normalizeArea,parseBudget,canonicalLgu,maxPages=50,runId,log=console.log}) {
  keyword=fold(keyword);
  const posts=[], reports=[], failures=[];
  let status=null, parsed=0;
  let detailPage;
  const record=row=>{const item=portalLog({source:'existing',runId,query:keyword,httpStatus:status,...row},log);reports.push(item);return item;};
  try {
    if(!isActive()) return posts;
    status=await publicGoto(page,EXISTING_SEARCH,'Existing PhilGEPS');
    await page.locator('#txtKeyword').waitFor({timeout:15000});
    await page.locator('#txtKeyword').fill(keyword);
    status=await publicNavigation(page,()=>page.locator('#btnSearch').click(),'Existing PhilGEPS');
    detailPage=await page.context().newPage();
    const signatures=new Set(), ids=new Set();
    for(let number=1;number<=maxPages && isActive();number++) {
      await page.locator('#txtKeyword').waitFor({timeout:15000});
      const rows=await readRows(page);
      const state=await page.evaluate(()=>{
        const text=document.body.innerText;
        const count=text.match(/([\d,]+)\s+opportunities? found/i);
        return {keyword:document.querySelector('#txtKeyword')?.value || '',empty:/\b0\s+opportunities? found|no (?:records|opportunities|results)/i.test(text),count:count ? Number(count[1].replace(/,/g,'')) : null};
      });
      if(fold(state.keyword)!==keyword) throw Error('Existing portal did not retain the search keyword');
      if(!rows.length && !state.empty && state.count!==0) throw Error('Existing response has no parsed rows and no verified empty-result marker');
      const signature=rows.map(row=>row.href).join('|');
      if(rows.length && signatures.has(signature)) throw Error('Existing pagination repeated its result page');
      signatures.add(signature);parsed+=rows.length;
      record({parsing:rows.length?'ok':'empty',page:number,rows:rows.length,total:state.count});
      for(const item of rows) {
        const url=new URL(item.href || '',EXISTING_SEARCH);
        const refId=url.searchParams.get('refID');
        if(!refId || !item.title || ids.has(refId)) continue;
        ids.add(refId);
        if(existingPostIds.has(refId)) continue;
        const postingDate=parseDate(item.postingDate),closingDate=parseDate(item.closingDate);
        if(!postingDate || !closingDate) throw Error(`Existing notice ${refId} dates could not be parsed`);
        if(!isStillActive(closingDate)) continue;
        let details;
        try {details=await getBidDetails(detailPage,url.href);}
        catch(error) {failures.push(record({parsing:'detail_failed',noticeId:refId,error:safeError(error)}));continue;}
        const area=normalizeArea(details.areaOfDelivery);
        if(!area && !matchesLgu(`${details.procuringEntity} ${item.details}`,keyword)) continue;
        const id=String(details.referenceNumber || refId).trim();
        posts.push({id,referenceNumber:id,lgu:canonicalLgu(keyword),title:String(details.title || item.title).trim(),procuringEntity:String(details.procuringEntity || item.details).trim(),areaOfDelivery:area,deliveryPeriod:String(details.deliveryPeriod || '').trim(),classification:String(details.classification || '').trim(),abc:parseBudget(details.abc),budgetType:details.budgetLabel==='EBC'?'EBC':'ABC',postingDate,closingDate,url:`https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/PrintableBidNoticeAbstractUI.aspx?refID=${encodeURIComponent(id)}`});
        existingPostIds.add(refId);existingPostIds.add(id);
      }
      const nextStatus=await advanceExisting(page);
      if(nextStatus===null) return Object.assign(posts,{reports,failures,retrievedCount:parsed});
      status=nextStatus;
      if(number===maxPages) throw Error('Existing search page limit reached; coverage incomplete');
    }
    return Object.assign(posts,{reports,failures,retrievedCount:parsed});
  } catch(error) {
    error.queryReport=record({httpStatus:failureStatus(error,status),parsing:'failed',error:safeError(error)});
    error.partialPosts=posts;error.reports=reports;
    throw error;
  } finally {if(detailPage) await detailPage.close().catch(()=>{});}
}
