import express from "express";
import cors from "cors";
import { chromium } from "playwright";
import cron from "node-cron";
import admin from "firebase-admin";
import { createClient } from "@supabase/supabase-js";

const app = express();

app.use(cors({ origin: "*" }));
app.use(express.json());

const PORT = process.env.PORT || 3000;

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const FIREBASE_SERVICE_ACCOUNT = process.env.FIREBASE_SERVICE_ACCOUNT;

const WATCH_LGUS = [
  "alubijid",
  "lagonglong",
  "balingasag",
  "villanueva",
  "salay",
  "gitagum",
  "libertad",
  "initao",
  "naawan",
  "laguindingan",
  "talakag",
  "libona",
  "malitbog",
  "sumilao",
  "impasugong",
  "impasug-ong",
  "baungon",
];

const ALLOWED_DELIVERY_AREAS = [
  "bukidnon",
  "misamis oriental",
];

const BASE_URL = "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/";
const SEARCH_URL =
  BASE_URL +
  "SplashOpportunitiesSearchUI.aspx?menuIndex=3&ClickFrom=OpenOpp&Result=3";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(FIREBASE_SERVICE_ACCOUNT)),
  });
}

function normalize(text = "") {
  return String(text).toLowerCase().replace(/\s+/g, " ").trim();
}

function cleanText(text = "") {
  return String(text).replace(/\s+/g, " ").trim();
}

function sanitizeData(text = "") {
  return String(text).replace(/[^\x00-\xFF]/g, "");
}

function canonicalLgu(lgu) {
  return lgu === "impasug-ong" ? "impasugong" : lgu;
}

function parsePhilgepsDate(value) {
  const text = cleanText(value);

  const match = text.match(
    /(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})\s*(AM|PM))?/i
  );

  if (!match) return null;

  let [, dd, mm, yyyy, hour = "12", minute = "00", ampm = "AM"] = match;

  dd = Number(dd);
  mm = Number(mm);
  yyyy = Number(yyyy);
  hour = Number(hour);
  minute = Number(minute);

  if (ampm.toUpperCase() === "PM" && hour !== 12) hour += 12;
  if (ampm.toUpperCase() === "AM" && hour === 12) hour = 0;

  return new Date(yyyy, mm - 1, dd, hour, minute).toISOString();
}

function isStillActive(closingDate) {
  if (!closingDate) return true;
  return new Date(closingDate).getTime() >= Date.now();
}

function isPostedRecently(postingDate) {
  if (!postingDate) return false;
  return Date.now() - new Date(postingDate).getTime() <= 24 * 60 * 60 * 1000;
}

function extractRefId(url = "") {
  const match = url.match(/refID=(\d+)/i);
  return match ? match[1] : "";
}

function normalizeAreaOfDelivery(area = "") {
  const text = normalize(area);

  if (text.includes("bukidnon")) return "Bukidnon";
  if (text.includes("misamis oriental")) return "Misamis Oriental";

  return "";
}

function isAllowedAreaOfDelivery(area = "") {
  return normalizeAreaOfDelivery(area) !== "";
}

async function getBidDetails(page, url) {
  await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: 60000,
  });

  await page.waitForTimeout(800);

  return await page.evaluate(() => {
    const clean = (text) => (text || "").replace(/\s+/g, " ").trim();

    const getValueAfterLabel = (label) => {
      const all = Array.from(document.querySelectorAll("td, span, div"));
      for (const el of all) {
        const text = clean(el.textContent);
        if (text.toLowerCase() === label.toLowerCase()) {
          const next = el.nextElementSibling;
          if (next) return clean(next.textContent);
        }
      }
      return "";
    };

    return {
      referenceNumber: getValueAfterLabel("Reference Number"),
      procuringEntity: getValueAfterLabel("Procuring Entity"),
      title: getValueAfterLabel("Title"),
      areaOfDelivery: getValueAfterLabel("Area of Delivery"),
    };
  });
}

async function searchPhilgepsByKeyword(page, keyword) {
  await page.goto(SEARCH_URL, {
    waitUntil: "domcontentloaded",
    timeout: 60000,
  });

  await page.waitForSelector("#txtKeyword", { timeout: 30000 });

  await page.fill("#txtKeyword", keyword);
  await page.click("#btnSearch");

  await page.waitForLoadState("domcontentloaded");
  await page.waitForTimeout(1500);

  const rows = await page.$$eval(
    "a[href*='SplashBidNoticeAbstractUI.aspx']",
    (links) => {
      return links.map((link) => {
        const row = link.closest("tr");
        const cells = row ? Array.from(row.querySelectorAll("td")) : [];

        return {
          href: link.getAttribute("href"),
          title: link.textContent?.replace(/\s+/g, " ").trim() || "",
          postingDate: cells[1]?.textContent?.replace(/\s+/g, " ").trim() || "",
          closingDate: cells[2]?.textContent?.replace(/\s+/g, " ").trim() || "",
          details: cells[3]?.textContent?.replace(/\s+/g, " ").trim() || "",
        };
      });
    }
  );

  const posts = [];

  for (const item of rows) {
    if (!item.href || !item.title) continue;

    const postingDate = parsePhilgepsDate(item.postingDate);
    const closingDate = parsePhilgepsDate(item.closingDate);

    if (!isStillActive(closingDate)) continue;

    const fullUrl = new URL(item.href, SEARCH_URL).toString();
    const refId = extractRefId(fullUrl);
    const lgu = canonicalLgu(keyword);

    let bidDetails = {
    referenceNumber: refId,
    procuringEntity: "",
    title: item.title,
    areaOfDelivery: "",
    };

    try {
    bidDetails = await getBidDetails(page, fullUrl);
    } catch (error) {
    console.error(`Detail scrape failed ${refId}: ${error.message}`);
    }

const cleanAreaOfDelivery = normalizeAreaOfDelivery(
  bidDetails.areaOfDelivery || ""
);

if (!isAllowedAreaOfDelivery(cleanAreaOfDelivery)) {
  console.log(
    `Skipped ${bidDetails.referenceNumber || refId}: area not allowed (${bidDetails.areaOfDelivery || "none"})`
  );
  continue;
}

posts.push({
  id: bidDetails.referenceNumber || refId || `${lgu}-${item.title}`,
  referenceNumber: bidDetails.referenceNumber || refId,
  lgu,
  procuringEntity: bidDetails.procuringEntity || item.details,
  title: bidDetails.title || item.title,
  areaOfDelivery: cleanAreaOfDelivery,
  postingDate,
  closingDate,
  url: fullUrl,
});
  }

  return posts;
}

async function getDeviceTokens() {
  const { data, error } = await supabase.from("device_tokens").select("token");

  if (error) return [];

  return (data || []).map((item) => item.token).filter(Boolean);
}

async function sendNotification(post) {
  const tokens = await getDeviceTokens();

  if (tokens.length === 0) return;

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: `${post.lgu} posted in PhilGEPS`,
      body: post.title,
    },
    data: {
      url: String(post.url || "https://notices.philgeps.gov.ph/"),
      postId: String(post.id || ""),
      lgu: sanitizeData(post.lgu || ""),
      title: sanitizeData(post.title || ""),
    },
  });

  await supabase.from("notification_logs").insert({
    post_id: post.id,
    title: `${post.lgu} posted in PhilGEPS`,
    message: post.title,
  });
}

async function savePostAndNotify(post) {
  const { data: existing } = await supabase
    .from("philgeps_posts")
    .select("id")
    .eq("id", post.id)
    .maybeSingle();

  const row = {
    id: post.id,
    lgu: post.lgu,
    title: post.title,
    posting_date: post.postingDate,
    closing_date: post.closingDate,
    url: post.url,
    status: isPostedRecently(post.postingDate) ? "new" : "old",
    reference_number: post.referenceNumber,
    procuring_entity: post.procuringEntity,
    area_of_delivery: post.areaOfDelivery,
  };

  const { error } = await supabase
    .from("philgeps_posts")
    .upsert(row, { onConflict: "id" });

  if (error) {
    console.error(error.message);
    return;
  }

  if (!existing && isPostedRecently(post.postingDate)) {
    await sendNotification(post);
  }
}

async function scrapePhilgeps() {
  const allPosts = [];

  const browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });

  const page = await browser.newPage();

  for (const lgu of WATCH_LGUS) {
    try {
      const posts = await searchPhilgepsByKeyword(page, lgu);

      console.log(`${lgu}: scraped ${posts.length} active post(s)`);

      allPosts.push(...posts);
    } catch (error) {
      console.error(`${lgu} scrape failed: ${error.message}`);
    }
  }

  await browser.close();

  const uniquePosts = Array.from(
    new Map(allPosts.map((post) => [post.id, post])).values()
  );

  console.log(`Total matching active posts: ${uniquePosts.length}`);

  return uniquePosts;
}

async function runChecker() {
  const posts = await scrapePhilgeps();

  for (const post of posts) {
    await savePostAndNotify(post);
  }

  return posts;
}

app.get("/", (req, res) => {
  res.json({
    message: "PhilGEPS Notif & Alert backend running",
  });
});

app.all("/check", async (req, res) => {
  try {
    const posts = await runChecker();

    const { data, error } = await supabase
      .from("philgeps_posts")
      .select("*")
      .in("lgu", WATCH_LGUS.map(canonicalLgu))
      .order("closing_date", { ascending: true });

    if (error) {
      return res.status(500).json({
        error: error.message,
      });
    }

    res.json({
      checked: posts.length,
      items: data || [],
    });
  } catch (error) {
    res.status(500).json({
      error: error.message,
    });
  }
});

app.post("/send-test-notification", async (req, res) => {
  const tokens = await getDeviceTokens();

  if (tokens.length === 0) {
    return res.json({ message: "No device tokens found" });
  }

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "PhilGEPS Notif & Alert",
      body: "Test notification working. Tap to open PhilGEPS.",
    },
    data: {
      url: "https://notices.philgeps.gov.ph/",
    },
  });

  res.json({
    message: "Test notification sent",
  });
});

cron.schedule("*/5 * * * *", async () => {
  try {
    await runChecker();
    console.log("PhilGEPS checked.");
  } catch (error) {
    console.error(error.message);
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});