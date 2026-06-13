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

async function fetchSearchByKeyword(keyword) {
  const first = await axios.get(SEARCH_URL, {
    headers: {
      "User-Agent": "Mozilla/5.0",
      Accept: "text/html",
    },
    timeout: 30000,
  });

  const cookies = (first.headers["set-cookie"] || [])
    .map((cookie) => cookie.split(";")[0])
    .join("; ");

  const $ = cheerio.load(first.data);
  const payload = new URLSearchParams();

  $("input").each((_, el) => {
    const name = $(el).attr("name");
    const value = $(el).attr("value") || "";

    if (name) {
      payload.append(name, value);
    }
  });

  payload.set("txtSearch", keyword);
  payload.set("btnSearch", "Search");

  const second = await axios.post(SEARCH_URL, payload.toString(), {
    headers: {
      "User-Agent": "Mozilla/5.0",
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "text/html",
      Referer: SEARCH_URL,
      Cookie: cookies,
    },
    timeout: 30000,
  });

  return second.data;
}

function parseSearchResults(html, keyword) {
  const $ = cheerio.load(html);
  const posts = [];

  $("a[href*='SplashBidNoticeAbstractUI.aspx']").each((_, el) => {
    const link = $(el);
    const href = link.attr("href");
    const title = cleanText(link.text());

    if (!href || !title) return;

    const row = link.closest("tr");
    const cells = row.find("td");

    const postingDateText = cleanText($(cells[1]).text());
    const closingDateText = cleanText($(cells[2]).text());
    const detailsText = cleanText($(cells[3]).text());

    const combined = normalize(`${title} ${detailsText}`);
    const key = normalize(keyword);

    if (!combined.includes(key)) return;

    const postingDate = parsePhilgepsDate(postingDateText);
    const closingDate = parsePhilgepsDate(closingDateText);

    if (!isStillActive(closingDate)) return;

    const fullUrl = new URL(href, SEARCH_URL).toString();
    const refId = extractRefId(fullUrl);
    const lgu = canonicalLgu(keyword);

    posts.push({
      id: refId || `${lgu}-${title}`,
      referenceNumber: refId,
      lgu,
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
    abc: post.abc,
    posting_date: post.postingDate,
    closing_date: post.closingDate,
    url: post.url,
    status: isPostedRecently(post.postingDate) ? "new" : "old",
    reference_number: post.referenceNumber,
    procuring_entity: post.procuringEntity,
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

  for (const lgu of WATCH_LGUS) {
    try {
      const html = await fetchSearchByKeyword(lgu);
      const posts = parseSearchResults(html, lgu);

      console.log(`${lgu}: scraped ${posts.length} active post(s)`);

      allPosts.push(...posts);
    } catch (error) {
      console.error(`${lgu} scrape failed: ${error.message}`);
    }
  }

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