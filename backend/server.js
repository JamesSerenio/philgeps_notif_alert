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

let isRunning = false;

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

function formatPHDate(value) {
  if (!value) return "N/A";

  const date = new Date(value);

  if (isNaN(date.getTime())) return "N/A";

  return date.toLocaleString("en-PH", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
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

const MM = String(mm).padStart(2, "0");
const DD = String(dd).padStart(2, "0");
const HH = String(hour).padStart(2, "0");
const MIN = String(minute).padStart(2, "0");

return new Date(`${yyyy}-${MM}-${DD}T${HH}:${MIN}:00+08:00`).toISOString();  
}

function isStillActive(closingDate) {
  if (!closingDate) return true;
  return new Date(closingDate).getTime() >= Date.now();
}

function isPostedRecently(postingDate) {
  if (!postingDate) return false;

  const posted = new Date(postingDate);
  if (isNaN(posted.getTime())) return false;

  const ageHours =
    (Date.now() - posted.getTime()) / (1000 * 60 * 60);

  return ageHours <= 24;
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
    classification: getValueAfterLabel("Classification:") || getValueAfterLabel("Classification"),
    budgetLabel: getValueAfterLabel("Approved Budget for the Contract:")
    ? "ABC"
    : getValueAfterLabel("Approved Budget for the Contract")
    ? "ABC"
    : getValueAfterLabel("Estimated Budget for the Contract:")
    ? "EBC"
    : getValueAfterLabel("Estimated Budget for the Contract")
    ? "EBC"
    : "ABC",

    abc:
    getValueAfterLabel("Approved Budget for the Contract:") ||
    getValueAfterLabel("Approved Budget for the Contract") ||
    getValueAfterLabel("Estimated Budget for the Contract:") ||
    getValueAfterLabel("Estimated Budget for the Contract"),
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
    classification: "",
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
  classification: bidDetails.classification || "",
  budgetType: bidDetails.budgetLabel || "ABC",
    abc:
    Number(
        String(bidDetails.abc || "0")
        .replace(/PHP/gi, "")
        .replace(/,/g, "")
        .trim()
    ) || 0,
  postingDate,
  closingDate,
  url: `https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/PrintableBidNoticeAbstractUI.aspx?refID=${bidDetails.referenceNumber || refId}`,
});
  }

  return posts;
}

async function getDeviceTokens() {
  const { data, error } = await supabase
    .from("device_tokens")
    .select("token")
    .not("token", "is", null);

  if (error) return [];

  return [...new Set((data || []).map((item) => item.token).filter(Boolean))];
}

async function sendNotification(post, type = "new") {
  const notificationType = type === "deadline" ? "deadline" : "new";

  const { error: logError } = await supabase.from("notification_logs").insert({
    post_id: post.id,
    lgu: post.lgu,
    title: post.title,
    posting_date: post.postingDate,
    closing_date: post.closingDate,
    status: notificationType,
    classification: post.classification,
    abc: post.abc || 0,
    budget_type: post.budgetType || "ABC",
    procuring_entity: post.procuringEntity,
    url: post.url,
    notification_type: notificationType,
  });

  if (logError) {
    if (logError.code === "23505") {
      console.log(`Skipped duplicate notification: ${post.id} - ${notificationType}`);
      return;
    }

    console.error("Notification log insert failed:", logError.message);
    return;
  }

const tokens = await getDeviceTokens();

console.log(`Sending ${notificationType} notification to ${tokens.length} token(s)`);

if (tokens.length === 0) {
  console.log("No device tokens found, notification not sent.");
  return;
}

  const response = await admin.messaging().sendEachForMulticast({
    tokens,

    data: {
      url: String(post.url || "https://notices.philgeps.gov.ph/"),
      postId: String(post.id || ""),
      apiUrl: "https://philgepsnotifalert-production.up.railway.app/add-bidding-doc",
      notificationType: String(notificationType),

      title:
        notificationType === "deadline"
          ? `DEADLINE ALERT - ${String(post.lgu || "").toUpperCase()}`
          : `NEW PHILGEPS POST - ${String(post.lgu || "").toUpperCase()}`,

      body:
        `📌 ${post.title || "N/A"}\n\n` +
        `Posted: ${formatPHDate(post.postingDate)}\n` +
        `Closing: ${formatPHDate(post.closingDate)}\n` +
        `Status: ${notificationType}\n` +
        `Classification: ${post.classification || "N/A"}\n` +
        `${post.budgetType || "ABC"}: ${(post.abc || 0).toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })}\n` +
        `Procuring Entity: ${post.procuringEntity || "N/A"}`,

      lgu: sanitizeData(post.lgu || ""),
      postTitle: sanitizeData(post.title || ""),
      postingDate: sanitizeData(formatPHDate(post.postingDate)),
      closingDate: sanitizeData(formatPHDate(post.closingDate)),
      status: sanitizeData(notificationType),
      classification: sanitizeData(post.classification || ""),
      procuringEntity: sanitizeData(post.procuringEntity || ""),
    },

    webpush: {
      headers: {
        TTL: "86400",
        Urgency: "high",
      },
    },
  });

  console.log("FCM success:", response.successCount);
  console.log("FCM failed:", response.failureCount);

  response.responses.forEach((result, index) => {
    if (!result.success) {
      console.error(
        "FCM token failed:",
        index,
        result.error?.code,
        result.error?.message
      );
    }
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
    classification: post.classification,
    abc: post.abc || 0,
    budget_type: post.budgetType || "ABC",
  };

  const { error } = await supabase
    .from("philgeps_posts")
    .upsert(row, { onConflict: "id" });

  if (error) {
    console.error(error.message);
    return;
  }

if (isPostedRecently(post.postingDate)) {
  const { data: existingNewLog } = await supabase
    .from("notification_logs")
    .select("id")
    .eq("post_id", post.id)
    .eq("notification_type", "new")
    .maybeSingle();

  if (!existingNewLog) {
    await sendNotification(post, "new");
  } else {
    console.log(`New alert already sent: ${post.id}`);
  }
}
}

async function scrapePhilgeps() {
  const allPosts = [];
  let browser;

  try {
    browser = await chromium.launch({
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
      ],
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
  } finally {
    if (browser) {
      await browser.close();
      console.log("Chromium browser closed.");
    }
  }

  const uniquePosts = Array.from(
    new Map(allPosts.map((post) => [post.id, post])).values()
  );

  console.log(`Total matching active posts: ${uniquePosts.length}`);

  return uniquePosts;
}

async function deleteOldNotificationLogs() {
  console.log("Notification logs are kept to prevent duplicate alerts.");
}

async function deleteExpiredPosts() {
  const now = new Date().toISOString();

  const { error } = await supabase
    .from("philgeps_posts")
    .delete()
    .lt("closing_date", now);

  if (error) {
    console.error("Delete expired posts failed:", error.message);
  }
}

async function sendDeadlineReminders() {
  const now = new Date();
  const next24Hours = new Date(now.getTime() + 30 * 60 * 60 * 1000);

    await deleteExpiredPosts();

  const { data, error } = await supabase
    .from("philgeps_posts")
    .select("*")
    .gte("closing_date", now.toISOString())
    .lte("closing_date", next24Hours.toISOString());

  if (error) {
    console.error("Deadline reminder fetch failed:", error.message);
    return;
  }

  for (const item of data || []) {
    const { data: existingLog } = await supabase
    .from("notification_logs")
    .select("id")
    .eq("post_id", item.id)
    .eq("notification_type", "deadline")
    .maybeSingle();

    if (existingLog) {
    console.log(`Deadline alert already sent: ${item.id}`);
    continue;
    }

    await sendNotification(
      {
        id: item.id,
        lgu: item.lgu,
        title: item.title,
        postingDate: item.posting_date,
        closingDate: item.closing_date,
        url: item.url,
        classification: item.classification,
        procuringEntity: item.procuring_entity,
        abc: item.abc || 0,
        budgetType: item.budget_type || "ABC",
      },
      "deadline"
    );
  }
}

async function runChecker({ sendAlerts = true } = {}) {
  if (isRunning) {
    console.log("Checker already running. Skipping this run.");
    return [];
  }

  isRunning = true;

  try {
    await deleteOldNotificationLogs();
    await deleteExpiredPosts();

    const posts = await scrapePhilgeps();

    for (const post of posts) {
      if (sendAlerts) {
        await savePostAndNotify(post);
      } else {
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
          classification: post.classification,
          abc: post.abc || 0,
          budget_type: post.budgetType || "ABC",
        };

        const { error } = await supabase
          .from("philgeps_posts")
          .upsert(row, { onConflict: "id" });

        if (error) console.error(error.message);
      }
    }

    if (sendAlerts) {
      await sendDeadlineReminders();
    }

    return posts;
  } finally {
    isRunning = false;
  }
}

app.get("/", (req, res) => {
  res.json({
    message: "PhilGEPS Notif & Alert backend running",
  });
});

app.all("/check", async (req, res) => {
  try {
    const posts = await runChecker({ sendAlerts: true });

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

app.post("/set-bidding-doc", async (req, res) => {
  try {
    const { postId, isBiddingDoc } = req.body;

    if (!postId) {
      return res.status(400).json({
        error: "postId is required",
      });
    }

    const { data, error } = await supabase
      .from("philgeps_posts")
      .update({
        is_bidding_doc: isBiddingDoc === true,
      })
      .eq("id", postId)
      .select("id,is_bidding_doc");

    if (error) {
      return res.status(500).json({
        error: error.message,
      });
    }

    res.json({
      success: true,
      postId,
      data,
    });
  } catch (error) {
    res.status(500).json({
      error: error.message,
    });
  }
});

app.post("/add-bidding-doc", async (req, res) => {
  try {
    console.log("ADD BIDDING DOC BODY:", req.body);

    const { postId } = req.body;

    if (!postId) {
      return res.status(400).json({
        error: "postId is required",
      });
    }

    const { data, error } = await supabase
      .from("philgeps_posts")
      .update({ is_bidding_doc: true })
      .eq("id", postId)
      .select("id,is_bidding_doc");

    if (error) {
      console.error("ADD BIDDING DOC ERROR:", error.message);
      return res.status(500).json({
        error: error.message,
      });
    }

    console.log("ADD BIDDING DOC UPDATED:", data);

    res.json({
      success: true,
      postId,
      data,
    });
  } catch (error) {
    console.error("ADD BIDDING DOC CATCH:", error.message);
    res.status(500).json({
      error: error.message,
    });
  }
});

app.all("/send-test-notification", async (req, res) => {
  const tokens = await getDeviceTokens();

  if (tokens.length === 0) {
    return res.json({ message: "No device tokens found" });
  }

    const response = await admin.messaging().sendEachForMulticast({
    tokens,

// notification removed

data: {
    title: "PhilGEPS Notif & Alert",
    body: "Test notification working. Tap to open PhilGEPS.",
    url: "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/PrintableBidNoticeAbstractUI.aspx?refID=13038413",
    postId: "13038413",
},

webpush: {
  headers: {
    TTL: "86400",
    Urgency: "high",
  },
},
    });

  console.log("TEST FCM success:", response.successCount);
  console.log("TEST FCM failed:", response.failureCount);

  response.responses.forEach((result, index) => {
    if (!result.success) {
      console.error(
        "TEST FCM token failed:",
        index,
        result.error?.code,
        result.error?.message
      );
    }
  });

  res.json({
    message: "Test notification sent",
    success: response.successCount,
    failed: response.failureCount,
  });
});

cron.schedule("*/30 * * * *", async () => {
  try {
    await runChecker({ sendAlerts: true });
    console.log("PhilGEPS checked.");
  } catch (error) {
    console.error(error.message);
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});