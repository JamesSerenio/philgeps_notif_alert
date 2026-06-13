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
  "baungon"
];

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(FIREBASE_SERVICE_ACCOUNT)),
  });
}

function normalize(text = "") {
  return text.toLowerCase().replace(/\s+/g, " ").trim();
}

function toIsoDate(value) {
  if (!value) return null;

  const parsed = new Date(value);

  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  return parsed.toISOString();
}

function extractRefId(url = "") {
  const match = url.match(/refID=(\d+)/i);
  return match ? match[1] : "";
}

async function getDeviceTokens() {
  const { data, error } = await supabase
    .from("device_tokens")
    .select("token");

  if (error) return [];

  return data.map((item) => item.token).filter(Boolean);
}

async function sendNotification(post) {
  const tokens = await getDeviceTokens();

  if (tokens.length === 0) {
    return;
  }

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: `${post.lgu} posted in PhilGEPS`,
      body: post.title,
    },
    data: {
      url: post.url || "https://notices.philgeps.gov.ph/",
      postId: post.id,
      lgu: post.lgu,
      title: post.title,
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

  if (existing) {
    return;
  }

  const { error } = await supabase.from("philgeps_posts").insert({
    id: post.id,
    lgu: post.lgu,
    title: post.title,
    abc: post.abc,
    posting_date: post.postingDate,
    closing_date: post.closingDate,
    url: post.url,
    status: "new",
    reference_number: post.referenceNumber,
    procuring_entity: post.procuringEntity,
  });

  if (!error) {
    await sendNotification(post);
  }
}

async function scrapePhilgeps() {
  const url =
    "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashOpportunitiesSearchUI.aspx?ClickFrom=OpenOpp&DirectFrom=OpenOpp&SearchDirectFrom=SearchOpenOpp&menuIndex=3";

  const response = await axios.get(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 PhilGEPS Notif Alert",
    },
    timeout: 30000,
  });

  const $ = cheerio.load(response.data);
  const posts = [];

  $("a[href*='SplashBidNoticeAbstractUI.aspx']").each((index, element) => {
    const href = $(element).attr("href");
    const title = $(element).text().replace(/\s+/g, " ").trim();

    if (!href || !title) return;

    const fullUrl = new URL(href, url).toString();
    const refId = extractRefId(fullUrl);
    const rowText = $(element).closest("tr").text().replace(/\s+/g, " ").trim();

    const matchedLgu = WATCH_LGUS.find((lgu) =>
      normalize(rowText).includes(lgu)
    );

    if (!matchedLgu) return;

    posts.push({
      id: refId || `${matchedLgu}-${title}`,
      referenceNumber: refId,
      lgu: matchedLgu,
      procuringEntity: matchedLgu,
      title,
      abc: "",
      postingDate: new Date().toISOString(),
      closingDate: null,
      url: fullUrl,
    });
  });

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

    const { data } = await supabase
      .from("philgeps_posts")
      .select("*")
      .order("closing_date", { ascending: true });

    const items = data.map((post) => ({
      id: post.id,
      lgu: post.lgu,
      title: post.title,
      abc: post.abc,
      postingDate: post.posting_date,
      closingDate: post.closing_date,
      url: post.url,
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