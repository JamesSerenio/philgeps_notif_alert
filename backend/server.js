import express from "express";
import cors from "cors";
import axios from "axios";
import * as cheerio from "cheerio";
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

const PHILGEPS_URL =
  "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashOpportunitiesSearchUI.aspx?menuIndex=3&ClickFrom=OpenOpp&Result=3";

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

function parsePhilgepsDate(value) {
  if (!value) return null;

  const match = cleanText(value).match(
    /(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)/i
  );

  if (!match) return null;

  let [, dd, mm, yyyy, hour, minute, ampm] = match;

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

function safeFirebaseData(text = "") {
  return String(text).replace(/[^\x00-\xFF]/g, "");
}

async function fetchHtml(url) {
  const response = await axios.get(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
      Accept: "text/html",
    },
    timeout: 30000,
  });

  return response.data;
}

function parseSearchResults(html) {
  const $ = cheerio.load(html);
  const posts = [];

  $("tr").each((_, row) => {
    const cells = $(row).find("td");

    if (cells.length < 4) return;

    const no = cleanText($(cells[0]).text());
    if (!/^\d+$/.test(no)) return;

    const postingDateText = cleanText($(cells[1]).text());
    const closingDateText = cleanText($(cells[2]).text());

    const titleCell = $(cells[3]);
    const titleLink = titleCell.find("a[href*='SplashBidNoticeAbstractUI']").first();

    const href = titleLink.attr("href");
    const title = cleanText(titleLink.text());
    const detailsText = cleanText(titleCell.text());

    if (!href || !title) return;

    const fullUrl = new URL(href, PHILGEPS_URL).toString();
    const refId = extractRefId(fullUrl);

    const postingDate = parsePhilgepsDate(postingDateText);
    const closingDate = parsePhilgepsDate(closingDateText);

    if (!isStillActive(closingDate)) return;

    const matchedLgu =
      WATCH_LGUS.find((lgu) => normalize(detailsText).includes(normalize(lgu))) ||
      "others";

    posts.push({
      id: refId || `${no}-${title}`,
      referenceNumber: refId,
      lgu: matchedLgu,
      procuringEntity: detailsText,
      title,
      abc: "",
      postingDate,
      closingDate,
      url: fullUrl,
    });
  });

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
      lgu: safeFirebaseData(post.lgu || ""),
      title: safeFirebaseData(post.title || ""),
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

  if (existing) return;

  const { error } = await supabase.from("philgeps_posts").insert({
    id: post.id,
    lgu: post.lgu,
    title: post.title,
    abc: post.abc,
    posting_date: post.postingDate,
    closing_date: post.closingDate,
    url: post.url,
    status: isPostedRecently(post.postingDate) ? "new" : "old",
    reference_number: post.referenceNumber,
    procuring_entity: post.procuringEntity,
  });

  if (!error && isPostedRecently(post.postingDate)) {
    await sendNotification(post);
  }
}

async function scrapePhilgeps() {
  const html = await fetchHtml(PHILGEPS_URL);
  const posts = parseSearchResults(html);

  console.log(`Scraped ${posts.length} active PhilGEPS post(s).`);

  return posts;
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
      .order("closing_date", { ascending: true });

    if (error) {
      return res.status(500).json({ error: error.message });
    }

    const items = (data || []).map((post) => ({
      id: post.id,
      lgu: post.lgu,
      title: post.title,
      abc: post.abc,
      postingDate: post.posting_date,
      closingDate: post.closing_date,
      url: post.url,
      status: post.status,
    }));

    res.json({
      checked: posts.length,
      items,
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

  res.json({ message: "Test notification sent" });
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