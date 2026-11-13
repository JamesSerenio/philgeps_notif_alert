// Explicit read-only live verification; never writes Supabase or sends notifications.
import { chromium } from 'playwright';
import { searchModern, readModernDetails, inspectModernDocument } from './modern-philgeps.js';
const browser = await chromium.launch({headless:true, channel:process.env.PLAYWRIGHT_CHANNEL || 'chrome'});
try {
  const page = await browser.newPage();
  for (const criteria of [{ reference:'130491' }, { title:'Food Supplies' }, { agency:'MUNICIPALITY OF SUMILAO BUKIDNON' }, { reference:'130491', closingFrom:'13-Nov-2026', closingTo:'30-Nov-2026' }]) {
    const rows = await searchModern(page, criteria);
    console.log(JSON.stringify({ criteria, count:rows.length, first:rows[0] }));
  }
  await page.goto('https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491');
  const details = await page.evaluate(readModernDetails);
  console.log(JSON.stringify({ details, document:await inspectModernDocument(page,details.preview) }));
} finally { await browser.close(); }
