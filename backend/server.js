import express from "express";
import cors from "cors";
import { chromium } from "playwright";
import cron from "node-cron";
import admin from "firebase-admin";
import { createClient } from "@supabase/supabase-js";
import { PDFDocument } from "pdf-lib";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const app = express();

app.use(cors({ origin: "*" }));
app.use(express.json());

const PORT = process.env.PORT || 3000;
const execFileAsync = promisify(execFile);

app.post(
  "/normalize-pdf",
  express.raw({ type: "application/pdf", limit: "120mb" }),
  async (req, res) => {
    if (!Buffer.isBuffer(req.body) || req.body.length < 5) {
      return res.status(400).json({ error: "A PDF body is required." });
    }

    const jobDirectory = path.join(tmpdir(), `pdf-${randomUUID()}`);
    const inputPath = path.join(jobDirectory, "input.pdf");
    const outputPath = path.join(jobDirectory, "output.pdf");
    try {
      await mkdir(jobDirectory, { recursive: true });
      await writeFile(inputPath, req.body);
      await execFileAsync(
        "gs",
        [
          "-sDEVICE=pdfwrite",
          "-dCompatibilityLevel=1.7",
          "-dNOPAUSE",
          "-dBATCH",
          "-dSAFER",
          "-dQUIET",
          "-dShowAnnots=true",
          "-dPreserveAnnots=false",
          "-dDetectDuplicateImages=true",
          "-dCompressFonts=true",
          `-sOutputFile=${outputPath}`,
          inputPath,
        ],
        { maxBuffer: 10 * 1024 * 1024 },
      );
      const normalizedPdf = await readFile(outputPath);
      res.set({
        "Content-Type": "application/pdf",
        "Content-Length": String(normalizedPdf.length),
        "Cache-Control": "no-store",
      });
      return res.send(normalizedPdf);
    } catch (error) {
      console.error("PDF normalization failed:", error);
      return res.status(500).json({ error: "PDF normalization failed." });
    } finally {
      await rm(jobDirectory, { recursive: true, force: true }).catch(() => {});
    }
  },
);

app.post(
  "/render-compatible-pdf",
  express.raw({ type: "application/pdf", limit: "120mb" }),
  async (req, res) => {
    if (!Buffer.isBuffer(req.body) || req.body.length < 5) {
      return res.status(400).json({ error: "A PDF body is required." });
    }

    const jobDirectory = path.join(tmpdir(), `pdf-render-${randomUUID()}`);
    const inputPath = path.join(jobDirectory, "input.pdf");
    let browser;
    try {
      await mkdir(jobDirectory, { recursive: true });
      await writeFile(inputPath, req.body);
      browser = await chromium.launch({ headless: true, channel: "chromium" });
      const page = await browser.newPage({
        viewport: { width: 1400, height: 1100 },
        deviceScaleFactor: 2,
      });
      await page.goto(`file://${inputPath}`, {
        waitUntil: "load",
        timeout: 120000,
      });
      await page.waitForTimeout(2500);

      // Hide thumbnails and select Fit-to-page in Chromium's PDF viewer.
      await page.mouse.click(31, 28);
      await page.waitForTimeout(250);
      await page.mouse.click(725, 28);
      await page.waitForTimeout(500);

      const output = await PDFDocument.create();
      let previousImage;
      for (let pageNumber = 1; pageNumber <= 120; pageNumber += 1) {
        await page.mouse.click(510, 28);
        await page.keyboard.press("Control+A");
        await page.keyboard.type(String(pageNumber));
        await page.keyboard.press("Enter");
        await page.waitForTimeout(180);
        const image = await page.screenshot({
          type: "jpeg",
          quality: 92,
          clip: { x: 333, y: 59, width: 732, height: 1034 },
        });

        // The viewer clamps an out-of-range page number to the final page.
        // Stop when that same final page is captured for a second time.
        if (previousImage && Buffer.compare(previousImage, image) === 0) break;
        previousImage = image;
        const embedded = await output.embedJpg(image);
        const pdfPage = output.addPage([595.28, 841.89]);
        pdfPage.drawImage(embedded, {
          x: 0,
          y: 0,
          width: 595.28,
          height: 841.89,
        });
      }

      const compatibleBytes = await output.save({
        useObjectStreams: false,
        objectsPerTick: 25,
      });
      res.set({
        "Content-Type": "application/pdf",
        "Content-Length": String(compatibleBytes.length),
        "Cache-Control": "no-store",
      });
      return res.send(Buffer.from(compatibleBytes));
    } catch (error) {
      console.error("Compatible PDF rendering failed:", error);
      return res.status(500).json({ error: "Compatible PDF rendering failed." });
    } finally {
      if (browser) await browser.close().catch(() => {});
      await rm(jobDirectory, { recursive: true, force: true }).catch(() => {});
    }
  },
);


const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY;
const FIREBASE_SERVICE_ACCOUNT =
  process.env.FIREBASE_SERVICE_ACCOUNT;

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
  "manolo fortich",
];

const BASE_URL =
  "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/";

const SEARCH_URL =
  `${BASE_URL}SplashOpportunitiesSearchUI.aspx` +
  "?menuIndex=3&ClickFrom=OpenOpp&Result=3";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error(
    "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY."
  );
}

if (!FIREBASE_SERVICE_ACCOUNT) {
  throw new Error(
    "Missing FIREBASE_SERVICE_ACCOUNT."
  );
}

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY
);

/*
|--------------------------------------------------------------------------
| CHECKER LOCK
|--------------------------------------------------------------------------
*/

let isRunning = false;
let checkerStartedAt = 0;
let activeBrowser = null;
let currentRunId = 0;

// Kapag 20 minutes nang naka-lock, ire-reset.
const CHECKER_STALE_MS = 20 * 60 * 1000;

// Kapag 18 minutes na ang Chromium, sapilitang isasara.
const CHECKER_FORCE_STOP_MS = 18 * 60 * 1000;

/*
|--------------------------------------------------------------------------
| FIREBASE
|--------------------------------------------------------------------------
*/

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(FIREBASE_SERVICE_ACCOUNT)
    ),
  });
}

/*
|--------------------------------------------------------------------------
| HELPERS
|--------------------------------------------------------------------------
*/

function normalize(text = "") {
  return String(text)
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function cleanText(text = "") {
  return String(text)
    .replace(/\s+/g, " ")
    .trim();
}

function sanitizeData(text = "") {
  return String(text).replace(
    /[^\x00-\xFF]/g,
    ""
  );
}

function canonicalLgu(lgu = "") {
  const value = normalize(lgu);

  if (value === "impasug-ong") {
    return "impasugong";
  }

  return value;
}

function formatPHDate(value) {
  if (!value) return "N/A";

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "N/A";
  }

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

function parsePhilgepsDate(value) {
  const text = cleanText(value);

  const match = text.match(
    /(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})\s*(AM|PM))?/i
  );

  if (!match) {
    return null;
  }

  let [
    ,
    dd,
    mm,
    yyyy,
    hour = "12",
    minute = "00",
    ampm = "AM",
  ] = match;

  dd = Number(dd);
  mm = Number(mm);
  yyyy = Number(yyyy);
  hour = Number(hour);
  minute = Number(minute);

  if (
    ampm.toUpperCase() === "PM" &&
    hour !== 12
  ) {
    hour += 12;
  }

  if (
    ampm.toUpperCase() === "AM" &&
    hour === 12
  ) {
    hour = 0;
  }

  const MM = String(mm).padStart(2, "0");
  const DD = String(dd).padStart(2, "0");
  const HH = String(hour).padStart(2, "0");
  const MIN = String(minute).padStart(2, "0");

  const date = new Date(
    `${yyyy}-${MM}-${DD}T${HH}:${MIN}:00+08:00`
  );

  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function isStillActive(closingDate) {
  if (!closingDate) {
    return true;
  }

  const closing = new Date(closingDate);

  if (Number.isNaN(closing.getTime())) {
    return true;
  }

  return closing.getTime() >= Date.now();
}

function isPostedRecently(postingDate) {
  if (!postingDate) {
    return false;
  }

  const posted = new Date(postingDate);

  if (Number.isNaN(posted.getTime())) {
    return false;
  }

  const ageHours =
    (Date.now() - posted.getTime()) /
    (1000 * 60 * 60);

  return ageHours >= 0 && ageHours <= 24;
}

function extractRefId(url = "") {
  const match = String(url).match(
    /refID=(\d+)/i
  );

  return match ? match[1] : "";
}

function normalizeAreaOfDelivery(area = "") {
  const text = normalize(area);

  if (text.includes("bukidnon")) {
    return "Bukidnon";
  }

  if (text.includes("misamis oriental")) {
    return "Misamis Oriental";
  }

  return "";
}

function isAllowedAreaOfDelivery(area = "") {
  return normalizeAreaOfDelivery(area) !== "";
}

function parseBudgetAmount(value = "") {
  const cleaned = String(value)
    .replace(/PHP/gi, "")
    .replace(/[₱,]/g, "")
    .replace(/[^\d.-]/g, "")
    .trim();

  const amount = Number(cleaned);

  return Number.isFinite(amount)
    ? amount
    : 0;
}

/*
|--------------------------------------------------------------------------
| EXISTING POSTS
|--------------------------------------------------------------------------
*/

async function getExistingPostIds() {
  const { data, error } = await supabase
    .from("philgeps_posts")
    .select("id,delivery_period")
    .limit(5000);

  if (error) {
    console.error(
      "Existing post IDs fetch failed:",
      error.message
    );

    return new Set();
  }

  return new Set(
    (data || [])
      // Existing rows created before delivery_period was added must be
      // revisited once so their PhilGEPS detail value can be backfilled.
      .filter((item) =>
        cleanText(
          item.delivery_period || ""
        ).length > 0
      )
      .map((item) =>
        String(item.id || "").trim()
      )
      .filter(Boolean)
  );
}

/*
|--------------------------------------------------------------------------
| GET BID DETAILS
|--------------------------------------------------------------------------
*/

async function getBidDetails(page, url) {
  await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: 60000,
  });

  await page.waitForTimeout(700);

  return page.evaluate(() => {
    const clean = (text) =>
      (text || "")
        .replace(/\s+/g, " ")
        .trim();

    const normalizeLabel = (text) =>
      clean(text)
        .toLowerCase()
        .replace(/:$/, "")
        .trim();

    const getValueAfterLabel = (
      ...labels
    ) => {
      const expectedLabels =
        labels.map(normalizeLabel);

      const rows = Array.from(
        document.querySelectorAll("tr")
      );

      for (const row of rows) {
        const cells = Array.from(
          row.querySelectorAll("th, td")
        );

        for (
          let index = 0;
          index < cells.length;
          index += 1
        ) {
          const label = normalizeLabel(
            cells[index].textContent
          );

          if (
            !expectedLabels.includes(label)
          ) {
            continue;
          }

          for (
            let nextIndex = index + 1;
            nextIndex < cells.length;
            nextIndex += 1
          ) {
            const value = clean(
              cells[nextIndex].textContent
            );

            if (value) {
              return value;
            }
          }
        }
      }

      const elements = Array.from(
        document.querySelectorAll(
          "td, th, span, div"
        )
      );

      for (const element of elements) {
        const label = normalizeLabel(
          element.textContent
        );

        if (
          !expectedLabels.includes(label)
        ) {
          continue;
        }

        const next =
          element.nextElementSibling;

        if (next) {
          const value = clean(
            next.textContent
          );

          if (value) {
            return value;
          }
        }
      }

      return "";
    };

    const approvedBudget =
      getValueAfterLabel(
        "Approved Budget for the Contract",
        "Approved Budget for the Contract:"
      );

    const estimatedBudget =
      getValueAfterLabel(
        "Estimated Budget for the Contract",
        "Estimated Budget for the Contract:"
      );

    return {
      referenceNumber:
        getValueAfterLabel(
          "Reference Number",
          "Reference Number:"
        ),

      procuringEntity:
        getValueAfterLabel(
          "Procuring Entity",
          "Procuring Entity:"
        ),

      title:
        getValueAfterLabel(
          "Title",
          "Title:"
        ),

      areaOfDelivery:
        getValueAfterLabel(
          "Area of Delivery",
          "Area of Delivery:"
        ),

      deliveryPeriod:
        getValueAfterLabel(
          "Delivery Period",
          "Delivery Period:"
        ),

      classification:
        getValueAfterLabel(
          "Classification",
          "Classification:"
        ),

      budgetLabel:
        estimatedBudget ? "EBC" : "ABC",

      abc:
        approvedBudget ||
        estimatedBudget,
    };
  });
}

/*
|--------------------------------------------------------------------------
| SEARCH ONE LGU
|--------------------------------------------------------------------------
*/

async function searchPhilgepsByKeyword(
  page,
  keyword,
  existingPostIds,
  runId
) {
  if (runId !== currentRunId) {
    return [];
  }

  await page.goto(SEARCH_URL, {
    waitUntil: "domcontentloaded",
    timeout: 60000,
  });

  await page.waitForSelector(
    "#txtKeyword",
    {
      timeout: 30000,
    }
  );

  await page.fill(
    "#txtKeyword",
    keyword
  );

  await page.click("#btnSearch");

  await page.waitForLoadState(
    "domcontentloaded"
  );

  await page.waitForTimeout(1200);

  const rows = await page.$$eval(
    "a[href*='SplashBidNoticeAbstractUI.aspx']",
    (links) => {
      return links.map((link) => {
        const row =
          link.closest("tr");

        const cells = row
          ? Array.from(
              row.querySelectorAll("td")
            )
          : [];

        return {
          href:
            link.getAttribute("href"),

          title:
            link.textContent
              ?.replace(/\s+/g, " ")
              .trim() || "",

          postingDate:
            cells[1]?.textContent
              ?.replace(/\s+/g, " ")
              .trim() || "",

          closingDate:
            cells[2]?.textContent
              ?.replace(/\s+/g, " ")
              .trim() || "",

          details:
            cells[3]?.textContent
              ?.replace(/\s+/g, " ")
              .trim() || "",
        };
      });
    }
  );

  const posts = [];

  for (const item of rows) {
    if (runId !== currentRunId) {
      console.log(
        `Checker run ${runId} cancelled.`
      );

      break;
    }

    if (!item.href || !item.title) {
      continue;
    }

    const postingDate =
      parsePhilgepsDate(
        item.postingDate
      );

    const closingDate =
      parsePhilgepsDate(
        item.closingDate
      );

    if (!isStillActive(closingDate)) {
      continue;
    }

    const fullUrl = new URL(
      item.href,
      SEARCH_URL
    ).toString();

    const refId =
      extractRefId(fullUrl);

    if (!refId) {
      console.log(
        `Skipped without reference ID: ${item.title}`
      );

      continue;
    }

    /*
     * MAHALAGANG FIX:
     * Kapag existing na ang post sa Supabase,
     * hindi na bubuksan ulit ang detail page.
     */
    if (existingPostIds.has(refId)) {
      continue;
    }

    const lgu =
      canonicalLgu(keyword);

    let bidDetails = {
      referenceNumber: refId,
      procuringEntity: "",
      title: item.title,
      areaOfDelivery: "",
      deliveryPeriod: "",
      classification: "",
      budgetLabel: "ABC",
      abc: "",
    };

    try {
      bidDetails =
        await getBidDetails(
          page,
          fullUrl
        );
    } catch (error) {
      console.error(
        `Detail scrape failed ${refId}:`,
        error.message
      );
    }

    const cleanArea =
      normalizeAreaOfDelivery(
        bidDetails.areaOfDelivery || ""
      );

    if (
      !isAllowedAreaOfDelivery(
        cleanArea
      )
    ) {
      console.log(
        `Skipped ${
          bidDetails.referenceNumber ||
          refId
        }: area not allowed (${
          bidDetails.areaOfDelivery ||
          "none"
        })`
      );

      continue;
    }

    const finalReferenceNumber =
      cleanText(
        bidDetails.referenceNumber
      ) || refId;

    const post = {
      id: finalReferenceNumber,

      referenceNumber:
        finalReferenceNumber,

      lgu,

      procuringEntity:
        cleanText(
          bidDetails.procuringEntity
        ) || item.details,

      title:
        cleanText(
          bidDetails.title
        ) || item.title,

      areaOfDelivery:
        cleanArea,

      deliveryPeriod:
        cleanText(
          bidDetails.deliveryPeriod
        ),

      classification:
        cleanText(
          bidDetails.classification
        ),

      budgetType:
        bidDetails.budgetLabel === "EBC"
          ? "EBC"
          : "ABC",

      abc:
        parseBudgetAmount(
          bidDetails.abc
        ),

      postingDate,

      closingDate,

      url:
        `${BASE_URL}` +
        "PrintableBidNoticeAbstractUI.aspx" +
        `?refID=${encodeURIComponent(
          finalReferenceNumber
        )}`,
    };

    posts.push(post);

    existingPostIds.add(
      finalReferenceNumber
    );
  }

  return posts;
}

/*
|--------------------------------------------------------------------------
| DEVICE TOKENS
|--------------------------------------------------------------------------
*/

async function getDeviceTokens() {
  const { data, error } = await supabase
    .from("device_tokens")
    .select("token")
    .not("token", "is", null);

  if (error) {
    console.error(
      "Device token fetch failed:",
      error.message
    );

    return [];
  }

  return [
    ...new Set(
      (data || [])
        .map((item) => item.token)
        .filter(Boolean)
    ),
  ];
}

/*
|--------------------------------------------------------------------------
| SEND NOTIFICATION
|--------------------------------------------------------------------------
*/

async function sendNotification(
  post,
  type = "new"
) {
  const notificationType =
    type === "deadline"
      ? "deadline"
      : "new";

  const { error: logError } =
    await supabase
      .from("notification_logs")
      .insert({
        post_id: post.id,
        lgu: post.lgu,
        title: post.title,
        posting_date:
          post.postingDate,
        closing_date:
          post.closingDate,
        status:
          notificationType,
        classification:
          post.classification,
        abc: post.abc || 0,
        budget_type:
          post.budgetType ||
          "ABC",
        procuring_entity:
          post.procuringEntity,
        url: post.url,
        notification_type:
          notificationType,
      });

  if (logError) {
    if (logError.code === "23505") {
      console.log(
        `Duplicate notification skipped: ${post.id} - ${notificationType}`
      );

      return;
    }

    console.error(
      "Notification log insert failed:",
      logError.message
    );

    return;
  }

  const tokens =
    await getDeviceTokens();

  console.log(
    `Sending ${notificationType} notification to ${tokens.length} token(s)`
  );

  if (tokens.length === 0) {
    console.log(
      "No device tokens found."
    );

    return;
  }

  const response =
    await admin
      .messaging()
      .sendEachForMulticast({
        tokens,

        data: {
          url: String(
            post.url ||
              "https://notices.philgeps.gov.ph/"
          ),

          postId: String(
            post.id || ""
          ),

          apiUrl:
            "https://philgepsnotifalert-production.up.railway.app/add-bidding-doc",

          notificationType:
            String(
              notificationType
            ),

          title:
            notificationType ===
            "deadline"
              ? `DEADLINE ALERT - ${String(
                  post.lgu || ""
                ).toUpperCase()}`
              : `NEW PHILGEPS POST - ${String(
                  post.lgu || ""
                ).toUpperCase()}`,

          body:
            `📌 ${
              post.title || "N/A"
            }\n\n` +
            `Posted: ${formatPHDate(
              post.postingDate
            )}\n` +
            `Closing: ${formatPHDate(
              post.closingDate
            )}\n` +
            `Status: ${notificationType}\n` +
            `Classification: ${
              post.classification ||
              "N/A"
            }\n` +
            `${
              post.budgetType ||
              "ABC"
            }: ${(
              post.abc || 0
            ).toLocaleString(
              "en-US",
              {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2,
              }
            )}\n` +
            `Procuring Entity: ${
              post.procuringEntity ||
              "N/A"
            }`,

          lgu:
            sanitizeData(
              post.lgu || ""
            ),

          postTitle:
            sanitizeData(
              post.title || ""
            ),

          postingDate:
            sanitizeData(
              formatPHDate(
                post.postingDate
              )
            ),

          closingDate:
            sanitizeData(
              formatPHDate(
                post.closingDate
              )
            ),

          status:
            sanitizeData(
              notificationType
            ),

          classification:
            sanitizeData(
              post.classification ||
              ""
            ),

          procuringEntity:
            sanitizeData(
              post.procuringEntity ||
              ""
            ),
        },

        webpush: {
          headers: {
            TTL: "86400",
            Urgency: "high",
          },
        },
      });

  console.log(
    "FCM success:",
    response.successCount
  );

  console.log(
    "FCM failed:",
    response.failureCount
  );

  response.responses.forEach(
    (result, index) => {
      if (!result.success) {
        console.error(
          "FCM token failed:",
          index,
          result.error?.code,
          result.error?.message
        );
      }
    }
  );
}

/*
|--------------------------------------------------------------------------
| SAVE POST
|--------------------------------------------------------------------------
*/

async function savePostAndNotify(post) {
  const row = {
    id: post.id,
    lgu: post.lgu,
    title: post.title,
    posting_date:
      post.postingDate,
    closing_date:
      post.closingDate,
    url: post.url,

    status:
      isPostedRecently(
        post.postingDate
      )
        ? "new"
        : "old",

    reference_number:
      post.referenceNumber,

    procuring_entity:
      post.procuringEntity,

    area_of_delivery:
      post.areaOfDelivery,

    delivery_period:
      post.deliveryPeriod,

    classification:
      post.classification,

    abc: post.abc || 0,

    budget_type:
      post.budgetType || "ABC",
  };

  const { error } = await supabase
    .from("philgeps_posts")
    .upsert(row, {
      onConflict: "id",
    });

  if (error) {
    console.error(
      `Post upsert failed ${post.id}:`,
      error.message
    );

    return;
  }

  console.log(
    `Stored post: ${post.id} - ${post.title}`
  );

  if (
    !isPostedRecently(
      post.postingDate
    )
  ) {
    return;
  }

  const {
    data: existingNewLog,
    error: logCheckError,
  } = await supabase
    .from("notification_logs")
    .select("id")
    .eq("post_id", post.id)
    .eq(
      "notification_type",
      "new"
    )
    .maybeSingle();

  if (logCheckError) {
    console.error(
      `New notification check failed ${post.id}:`,
      logCheckError.message
    );

    return;
  }

  if (!existingNewLog) {
    await sendNotification(
      post,
      "new"
    );
  } else {
    console.log(
      `New alert already sent: ${post.id}`
    );
  }
}

/*
|--------------------------------------------------------------------------
| SCRAPE ALL LGUS
|--------------------------------------------------------------------------
*/

async function scrapePhilgeps(
  existingPostIds,
  runId
) {
  const allPosts = [];
  let browser = null;

  try {
    browser =
      await chromium.launch({
        headless: true,

        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
          "--disable-gpu",
        ],
      });

    if (runId !== currentRunId) {
      await browser
        .close()
        .catch(() => {});

      return [];
    }

    activeBrowser = browser;

    const page =
      await browser.newPage();

    page.setDefaultNavigationTimeout(
      60000
    );

    page.setDefaultTimeout(
      30000
    );

    for (const lgu of WATCH_LGUS) {
      if (
        runId !== currentRunId
      ) {
        console.log(
          `Checker run ${runId} cancelled before ${lgu}.`
        );

        break;
      }

      try {
        const posts =
          await searchPhilgepsByKeyword(
            page,
            lgu,
            existingPostIds,
            runId
          );

        console.log(
          `${lgu}: found ${posts.length} new matching post(s)`
        );

        allPosts.push(...posts);
      } catch (error) {
        console.error(
          `${lgu} scrape failed:`,
          error.message
        );
      }
    }
  } finally {
    if (browser) {
      await browser
        .close()
        .catch(() => {});

      console.log(
        "Chromium browser closed."
      );
    }

    if (
      activeBrowser === browser
    ) {
      activeBrowser = null;
    }
  }

  const uniquePosts =
    Array.from(
      new Map(
        allPosts.map((post) => [
          post.id,
          post,
        ])
      ).values()
    );

  console.log(
    `Total new matching posts: ${uniquePosts.length}`
  );

  return uniquePosts;
}

/*
|--------------------------------------------------------------------------
| DELETE OLD DATA
|--------------------------------------------------------------------------
*/

async function deleteOldNotificationLogs() {
  console.log(
    "Notification logs are kept to prevent duplicate alerts."
  );
}

async function deleteExpiredPosts() {
  const now =
    new Date().toISOString();

  const { error } = await supabase
    .from("philgeps_posts")
    .delete()
    .lt("closing_date", now);

  if (error) {
    console.error(
      "Delete expired posts failed:",
      error.message
    );
  }
}

/*
|--------------------------------------------------------------------------
| DEADLINE REMINDERS
|--------------------------------------------------------------------------
*/

async function sendDeadlineReminders() {
  const now = new Date();

  const next30Hours =
    new Date(
      now.getTime() +
        30 * 60 * 60 * 1000
    );

  await deleteExpiredPosts();

  const { data, error } = await supabase
    .from("philgeps_posts")
    .select("*")
    .gte(
      "closing_date",
      now.toISOString()
    )
    .lte(
      "closing_date",
      next30Hours.toISOString()
    );

  if (error) {
    console.error(
      "Deadline reminder fetch failed:",
      error.message
    );

    return;
  }

  for (const item of data || []) {
    const {
      data: existingLog,
      error: existingLogError,
    } = await supabase
      .from("notification_logs")
      .select("id")
      .eq("post_id", item.id)
      .eq(
        "notification_type",
        "deadline"
      )
      .maybeSingle();

    if (existingLogError) {
      console.error(
        `Deadline log check failed ${item.id}:`,
        existingLogError.message
      );

      continue;
    }

    if (existingLog) {
      console.log(
        `Deadline alert already sent: ${item.id}`
      );

      continue;
    }

    await sendNotification(
      {
        id: item.id,
        lgu: item.lgu,
        title: item.title,

        postingDate:
          item.posting_date,

        closingDate:
          item.closing_date,

        url: item.url,

        classification:
          item.classification,

        procuringEntity:
          item.procuring_entity,

        abc: item.abc || 0,

        budgetType:
          item.budget_type ||
          "ABC",
      },

      "deadline"
    );
  }
}

/*
|--------------------------------------------------------------------------
| RESET STALE CHECKER
|--------------------------------------------------------------------------
*/

async function stopStaleChecker() {
  const elapsed =
    Date.now() -
    checkerStartedAt;

  console.warn(
    `Stale checker detected after ${Math.ceil(
      elapsed / 60000
    )} minute(s). Restarting.`
  );

  // I-cancel ang lumang run.
  currentRunId += 1;

  const browserToClose =
    activeBrowser;

  activeBrowser = null;

  if (browserToClose) {
    await browserToClose
      .close()
      .catch(() => {});
  }

  isRunning = false;
  checkerStartedAt = 0;
}

/*
|--------------------------------------------------------------------------
| MAIN CHECKER
|--------------------------------------------------------------------------
*/

async function runChecker({
  sendAlerts = true,
} = {}) {
  if (isRunning) {
    const elapsed =
      Date.now() -
      checkerStartedAt;

    if (
      elapsed <
      CHECKER_STALE_MS
    ) {
      console.log(
        `Checker already running for ${Math.ceil(
          elapsed / 60000
        )} minute(s). Skipping this run.`
      );

      return null;
    }

    await stopStaleChecker();
  }

  const runId =
    ++currentRunId;

  isRunning = true;
  checkerStartedAt =
    Date.now();

  const forceStopTimer =
    setTimeout(async () => {
      if (
        isRunning &&
        currentRunId === runId
      ) {
        console.error(
          `Checker run ${runId} exceeded 18 minutes. Closing Chromium.`
        );

        const browserToClose =
          activeBrowser;

        activeBrowser = null;

        if (browserToClose) {
          await browserToClose
            .close()
            .catch(() => {});
        }
      }
    }, CHECKER_FORCE_STOP_MS);

  try {
    await deleteOldNotificationLogs();
    await deleteExpiredPosts();

    const existingPostIds =
      await getExistingPostIds();

    console.log(
      `Starting checker run ${runId}. Existing posts: ${existingPostIds.size}`
    );

    const posts =
      await scrapePhilgeps(
        existingPostIds,
        runId
      );

    if (
      runId !== currentRunId
    ) {
      console.log(
        `Checker run ${runId} stopped because a newer run started.`
      );

      return null;
    }

    for (const post of posts) {
      if (
        runId !== currentRunId
      ) {
        return null;
      }

      if (sendAlerts) {
        await savePostAndNotify(
          post
        );
      } else {
        const row = {
          id: post.id,
          lgu: post.lgu,
          title: post.title,

          posting_date:
            post.postingDate,

          closing_date:
            post.closingDate,

          url: post.url,

          status:
            isPostedRecently(
              post.postingDate
            )
              ? "new"
              : "old",

          reference_number:
            post.referenceNumber,

          procuring_entity:
            post.procuringEntity,

          area_of_delivery:
            post.areaOfDelivery,

          delivery_period:
            post.deliveryPeriod,

          classification:
            post.classification,

          abc: post.abc || 0,

          budget_type:
            post.budgetType ||
            "ABC",
        };

        const { error } =
          await supabase
            .from(
              "philgeps_posts"
            )
            .upsert(row, {
              onConflict: "id",
            });

        if (error) {
          console.error(
            `Post upsert failed ${post.id}:`,
            error.message
          );
        }
      }
    }

    if (
      sendAlerts &&
      runId === currentRunId
    ) {
      await sendDeadlineReminders();
    }

    return posts;
  } catch (error) {
    console.error(
      `Checker run ${runId} failed:`,
      error.message
    );

    throw error;
  } finally {
    clearTimeout(
      forceStopTimer
    );

    /*
     * Ang latest run lang ang maaaring
     * mag-release ng checker lock.
     */
    if (
      currentRunId === runId
    ) {
      isRunning = false;
      checkerStartedAt = 0;
      activeBrowser = null;
    }
  }
}

/*
|--------------------------------------------------------------------------
| GET STORED POSTS
|--------------------------------------------------------------------------
*/

async function getStoredPosts() {
  const uniqueLgus = [
    ...new Set(
      WATCH_LGUS.map(
        canonicalLgu
      )
    ),
  ];

  const { data, error } =
    await supabase
      .from("philgeps_posts")
      .select("*")
      .in("lgu", uniqueLgus)
      .order(
        "closing_date",
        {
          ascending: true,
        }
      )
      .limit(5000);

  if (error) {
    throw error;
  }

  return data || [];
}

/*
|--------------------------------------------------------------------------
| ROOT
|--------------------------------------------------------------------------
*/

app.get("/", (req, res) => {
  res.json({
    message:
      "PhilGEPS Notif & Alert backend running",

    checkerRunning:
      isRunning,

    checkerStartedAt:
      checkerStartedAt
        ? new Date(
            checkerStartedAt
          ).toISOString()
        : null,
  });
});

/*
|--------------------------------------------------------------------------
| CHECK ENDPOINT
|--------------------------------------------------------------------------
*/

app.all(
  "/check",
  async (req, res) => {
    try {
      const posts =
        await runChecker({
          sendAlerts: true,
        });

      const checkerBusy =
        posts === null;

      const items =
        await getStoredPosts();

      return res.json({
        busy: checkerBusy,

        checked:
          checkerBusy
            ? 0
            : posts.length,

        totalStored:
          items.length,

        message:
          checkerBusy
            ? "Checker is still running. Existing Supabase posts returned."
            : "PhilGEPS check completed.",

        items,
      });
    } catch (error) {
      console.error(
        "/check error:",
        error.message
      );

      return res
        .status(500)
        .json({
          error:
            error.message,
        });
    }
  }
);

/*
|--------------------------------------------------------------------------
| SET BIDDING DOC
|--------------------------------------------------------------------------
*/

app.post(
  "/set-bidding-doc",
  async (req, res) => {
    try {
      const {
        postId,
        isBiddingDoc,
      } = req.body;

      if (!postId) {
        return res
          .status(400)
          .json({
            error:
              "postId is required",
          });
      }

      const { data, error } =
        await supabase
          .from(
            "philgeps_posts"
          )
          .update({
            is_bidding_doc:
              isBiddingDoc ===
              true,
          })
          .eq("id", postId)
          .select(
            "id,is_bidding_doc"
          );

      if (error) {
        return res
          .status(500)
          .json({
            error:
              error.message,
          });
      }

      return res.json({
        success: true,
        postId,
        data,
      });
    } catch (error) {
      return res
        .status(500)
        .json({
          error:
            error.message,
        });
    }
  }
);

/*
|--------------------------------------------------------------------------
| REFRESH DELIVERY PERIOD
|--------------------------------------------------------------------------
*/

app.post(
  "/refresh-delivery-period",
  async (req, res) => {
    const referenceNumber = cleanText(
      req.body?.referenceNumber || ""
    );
    if (!referenceNumber) {
      return res.status(400).json({
        error: "referenceNumber is required",
      });
    }

    let browser;
    try {
      const url =
        "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/" +
        `PrintableBidNoticeAbstractUI.aspx?refID=${encodeURIComponent(referenceNumber)}`;
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
      const details = await getBidDetails(page, url);
      const deliveryPeriod = cleanText(details.deliveryPeriod || "");
      if (!deliveryPeriod) {
        return res.status(404).json({
          error: "Delivery Period was not found on PhilGEPS",
        });
      }

      const { error } = await supabase
        .from("philgeps_posts")
        .update({ delivery_period: deliveryPeriod })
        .eq("reference_number", referenceNumber);
      if (error) throw error;

      return res.json({
        success: true,
        referenceNumber,
        deliveryPeriod,
      });
    } catch (error) {
      console.error(
        `Delivery Period refresh failed ${referenceNumber}:`,
        error.message
      );
      return res.status(500).json({ error: error.message });
    } finally {
      if (browser) await browser.close().catch(() => {});
    }
  }
);

/*
|--------------------------------------------------------------------------
| ADD BIDDING DOC
|--------------------------------------------------------------------------
*/

app.post(
  "/add-bidding-doc",
  async (req, res) => {
    try {
      console.log(
        "ADD BIDDING DOC BODY:",
        req.body
      );

      const { postId } =
        req.body;

      if (!postId) {
        return res
          .status(400)
          .json({
            error:
              "postId is required",
          });
      }

      const { data, error } =
        await supabase
          .from(
            "philgeps_posts"
          )
          .update({
            is_bidding_doc:
              true,
          })
          .eq("id", postId)
          .select(
            "id,is_bidding_doc"
          );

      if (error) {
        console.error(
          "ADD BIDDING DOC ERROR:",
          error.message
        );

        return res
          .status(500)
          .json({
            error:
              error.message,
          });
      }

      console.log(
        "ADD BIDDING DOC UPDATED:",
        data
      );

      return res.json({
        success: true,
        postId,
        data,
      });
    } catch (error) {
      console.error(
        "ADD BIDDING DOC CATCH:",
        error.message
      );

      return res
        .status(500)
        .json({
          error:
            error.message,
        });
    }
  }
);

/*
|--------------------------------------------------------------------------
| TEST NOTIFICATION
|--------------------------------------------------------------------------
*/

app.all(
  "/send-test-notification",
  async (req, res) => {
    try {
      const tokens =
        await getDeviceTokens();

      if (
        tokens.length === 0
      ) {
        return res.json({
          message:
            "No device tokens found",
        });
      }

      const response =
        await admin
          .messaging()
          .sendEachForMulticast({
            tokens,

            data: {
              title:
                "PhilGEPS Notif & Alert",

              body:
                "Test notification working. Tap to open PhilGEPS.",

              url:
                "https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/PrintableBidNoticeAbstractUI.aspx?refID=13038413",

              postId:
                "13038413",
            },

            webpush: {
              headers: {
                TTL: "86400",
                Urgency:
                  "high",
              },
            },
          });

      console.log(
        "TEST FCM success:",
        response.successCount
      );

      console.log(
        "TEST FCM failed:",
        response.failureCount
      );

      response.responses.forEach(
        (result, index) => {
          if (
            !result.success
          ) {
            console.error(
              "TEST FCM token failed:",
              index,
              result.error?.code,
              result.error
                ?.message
            );
          }
        }
      );

      return res.json({
        message:
          "Test notification sent",

        success:
          response.successCount,

        failed:
          response.failureCount,
      });
    } catch (error) {
      console.error(
        "Test notification failed:",
        error.message
      );

      return res
        .status(500)
        .json({
          error:
            error.message,
        });
    }
  }
);

/*
|--------------------------------------------------------------------------
| CRON — EVERY 30 MINUTES
|--------------------------------------------------------------------------
*/

cron.schedule(
  "*/30 * * * *",
  async () => {
    try {
      const posts =
        await runChecker({
          sendAlerts: true,
        });

      /*
       * Kapag null, busy pa ang checker.
       * Huwag mag-print ng fake na
       * "PhilGEPS checked".
       */
      if (posts === null) {
        return;
      }

      console.log(
        `PhilGEPS checked. ${posts.length} new post(s) processed.`
      );
    } catch (error) {
      console.error(
        "Scheduled PhilGEPS check failed:",
        error.message
      );
    }
  }
);

/*
|--------------------------------------------------------------------------
| START SERVER
|--------------------------------------------------------------------------
*/

app.listen(PORT, () => {
  console.log(
    `Server running on port ${PORT}`
  );
});
