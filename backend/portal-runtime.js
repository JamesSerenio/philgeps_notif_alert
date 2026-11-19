export const fold = value => String(value || '').toLowerCase().replace(/\s+/g, ' ').trim();
export function matchesLgu(value, lgu) {
  const words = fold(lgu).replace(/impasug-?ong/g, 'impasug ong').replace(/[^a-z0-9]+/g, ' ').trim();
  const text = fold(value).replace(/impasug-?ong/g, 'impasug ong').replace(/[^a-z0-9]+/g, ' ');
  return (` ${text.trim()} `).includes(` ${words} `);
}
export function safeError(error) {
  return String(error?.message || error || 'Unknown error')
    .replace(/Bearer\s+\S+/gi, 'Bearer [redacted]')
    .replace(/([?&](?:token|key|secret|_csrfToken)=)[^&\s]+/gi, '$1[redacted]').slice(0, 1500);
}
export function portalLog(record, log = console.log) {
  const row = { event: 'PORTAL_QUERY', at:new Date().toISOString(), ...record };
  if (row.error) row.error = safeError(row.error);
  log(JSON.stringify(row));
  return row;
}
export function checkResponse(response, source) {
  const status = response?.status() ?? null;
  if (response?.ok()) return status;
  const error = new Error(`${source} HTTP ${status ?? 'no response'}`);
  error.httpStatus = status;
  if ([401,403,429].includes(status)) error.accessLimited = true;
  throw error;
}
export async function publicNavigation(page, action, source) {
  try {
    const [response]=await Promise.all([page.waitForNavigation({waitUntil:'domcontentloaded',timeout:45000}),action()]);
    return checkResponse(response,source);
  } catch(error) {
    if(!Object.hasOwn(error,'httpStatus')) error.httpStatus=null;
    throw error;
  }
}
export const failureStatus = (error,lastStatus) => Object.hasOwn(error,'httpStatus') ? error.httpStatus : lastStatus;
export async function publicGoto(page, url, source) {
  try { return checkResponse(await page.goto(url, { waitUntil:'domcontentloaded', timeout:45000 }), source); }
  catch (error) {
    if(!Object.hasOwn(error,'httpStatus')) error.httpStatus=null;
    // One clean-session retry for a transport/redirect failure only. Never retry
    // CAPTCHA/login/authorization/rate-limit responses.
    if (error.accessLimited || !/ERR_TOO_MANY_REDIRECTS|ERR_CONNECTION_RESET|ERR_EMPTY_RESPONSE/.test(error.message)) throw error;
    await page.context().clearCookies();
    await page.waitForTimeout(1500);
    checkResponse(await page.goto(new URL('/',url).href,{waitUntil:'domcontentloaded',timeout:45000}),source);
    return checkResponse(await page.goto(url,{waitUntil:'domcontentloaded',timeout:45000}),source);
  }
}
