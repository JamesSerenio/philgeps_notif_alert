// Read-only bounded portal diagnostics. No database writes or notifications.
import { chromium } from 'playwright';
import { searchModern, modernAgency } from './modern-philgeps.js';
const browser = await chromium.launch({headless:true,channel:process.env.PLAYWRIGHT_CHANNEL || 'chrome'});
try {
  let page = await browser.newPage();
  page.setDefaultTimeout(10000);
  page.setDefaultNavigationTimeout(45000);
  const existing = 'https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashOpportunitiesSearchUI.aspx?menuIndex=3&ClickFrom=OpenOpp&Result=3';
  try {
    const response = await page.goto(existing,{waitUntil:'domcontentloaded'});
    console.log('EXISTING',response.status(),page.url());
    console.log(JSON.stringify(await page.evaluate(()=>({inputs:[...document.querySelectorAll('input:not([type=hidden]),select,button')].map(e=>({id:e.id,name:e.name,type:e.type})),forms:[...document.forms].map(f=>({action:f.action,method:f.method}))}))));
    console.log('SELECTORS',await page.locator('#txtKeyword').count(),await page.locator('#btnSearch').count());
    if(await page.locator('#txtKeyword').count()) {
      await page.locator('#txtKeyword').fill('sumilao');
      await Promise.all([page.waitForNavigation({waitUntil:'domcontentloaded'}),page.locator('#btnSearch').click()]);
      console.log('EXISTING SEARCH',await page.locator('a[href*="SplashBidNoticeAbstractUI.aspx"]').count());
    }
  } catch(error) { console.log('EXISTING ERROR',error.message); }
  await page.close();
  page = await browser.newPage();
  page.setDefaultTimeout(10000);
  page.setDefaultNavigationTimeout(45000);
  for (const lgu of ['alubijid','lagonglong','balingasag','villanueva','salay','gitagum','libertad','initao','naawan','laguindingan','talakag','libona','malitbog','sumilao','impasugong','baungon','manolo fortich']) {
    try { const rows = await searchModern(page,{agency:modernAgency(lgu)}); console.log('MODERN',lgu,rows.length,JSON.stringify(rows[0] || {})); }
    catch(error) { console.log('MODERN ERROR',lgu,error.message); }
    console.log(JSON.stringify(await page.evaluate(()=>({url:location.href,agency:document.querySelector('#searchAgencyName')?.value,rows:document.querySelectorAll('a[href*="viewLiveTenderDetails"]').length,pager:[...document.querySelectorAll('a')].filter(a=>a.rel==='next'||/next|view more/i.test(a.textContent)).map(a=>({text:a.textContent.trim(),href:a.href,rel:a.rel}))}))));
    await page.waitForTimeout(1000);
  }
} finally {await browser.close();}
