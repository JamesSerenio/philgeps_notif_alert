# Refresh repair — 19 November 2026

The repair is implemented and tested locally. It has **not been committed, merged, or deployed** by this task. Pressing Check Updates against the existing Railway deployment still executes the old adapter.

## Deployed code versus repair

The active backend, confirmed by the owner, is Railway service **philgeps_notif_alert**, branch **main**, commit **87bc69ed9cb261288fa4b6db0aada65e70c45c5e**, root **/backend**, deployed 13 November. Flutter's default URL and the inspected live endpoint are `https://philgepsnotifalert-production.up.railway.app`. Existing compile-time `SCRAPER_BACKEND_URL` overrides still take precedence.

`87bc69e` merged PR #2 from `new_philgeps`; it already includes signed-out manual refresh and the original Modern adapter. Committed `new_philgeps` HEAD is `1b4b64fe1096ed53d03349a6076816e27b764f25`. Its only committed difference from the deployed backend tree is `tool/check_refresh_schema.mjs`. Merely redeploying either of these commits will not install this repair. The new scraper modules and modified callers in the working tree must be committed and merged.

The current public backend does not expose its Git SHA and Railway account logs are not connected here. The commit identity above is owner-confirmed, not inferred from a Railway deployment UUID. Public GitHub metadata independently confirms `new_philgeps` HEAD; its Vercel deployment status does not prove a Railway deployment. The new backend root response adds `build.commit`, `build.branch`, `build.service`, and `scraperVersion: province-post-pagination-v2` from Railway environment metadata so the next deployment can be checked directly.

## Failure trace

**Modern: confirmed adapter and portal issues.** `Modern search may be truncated; narrow the query before retrying.` was thrown by our old `searchModern()` guard, not supplied by PhilGEPS. Salay/Gitagum agency searches returned 100 unrelated nationwide results despite echoing the agency input. The old adapter treated this as fatal and discarded notices already collected for other LGUs. Separately, the official View More GET paginator drops its POSTed search filters: Bukidnon page 1 reported 399 records, while an ordinary GET of its next link returned page 2 of the nationwide 18,397-record catalogue. A native POST of the same next link with the form's province/filter fields retained Bukidnon and the 399-record total. View More notice URLs end in `/OPEN_MORE`; the old validator rejected those valid links.

The repair uses the verified province search for Bukidnon and Misamis Oriental, POSTs every official next link with current CSRF/session/form fields, checks the echoed filters, page number, unique IDs and total, and matches the monitored municipalities locally with normalized case/spacing and word boundaries. Larger result sets split into inclusive, nonoverlapping publication-date ranges. A failed page or query retains previous verified rows. A complete 100-row result is not classified as truncated just because it has 100 rows. Public notice metadata is saved even when documents require login.

**Existing: original exception was discarded; retry succeeds.** The deployed `Failed LGUs` string only retained names, so it cannot reveal the original Railway transport/browser exception. A local probe observed an intermittent `net::ERR_TOO_MANY_REDIRECTS`; a later real deployed run succeeded for Existing without a database change. The old scraper also clicked the ASP.NET search button before registering a navigation wait and could read the previous page, and its generic pager missed the actual page dropdown/`<Next>` controls. The replacement registers navigation waits before every postback, handles the actual dropdown, validates empty-result markers, checks HTTP responses, and permits one clean-session retry for redirect/reset transport failures. It never retries around login, CAPTCHA, authorization, or rate limits. The exact cause of the original all-LGU Railway failure remains unproven without those old logs; this report does not invent an exception for that run.

Both adapters now log `PORTAL_QUERY` with the coordinator's real run UUID, source, query, HTTP status (null for no response), parsed rows/page totals, and sanitized errors. Run results persist `sourceStats` and per-query errors, including retrieved, eligible, saved, new and refreshed counts. Partial success does not update a source's last-success timestamp. Server credentials, cookies and CSRF tokens are not logged.

A single-day publication-date POST was also verified live: `Bukidnon`, `19-Nov-2026` through `19-Nov-2026` returned 32 records over 2 pages, rather than the unbounded province's 399. The returned date fields matched and all 20 first-page notices were published on that date. Date splitting uses the current Philippine calendar day.

## Live verification and saved-data distinction

Read-only execution of the corrected adapters started at `2026-11-19T00:27:36Z` (08:27:36 PHT). It did not write Supabase or send notifications:

| Source | Official rows retrieved | Eligible notices after filtering | Query failures |
| --- | ---: | ---: | ---: |
| Existing, all 18 configured LGU terms | 19 | 18 | 0 |
| Modern, Bukidnon: 20 pages / 399 rows; Misamis Oriental: 22 pages / 427 rows | 826 | 167 unique notices | 0 |

All 167 eligible Modern notices had a verified access-required response for the document preview. They remain valid public notices. Example official references: [147539](https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/147539/OPEN_MORE), [129841](https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/129841/OPEN_MORE), and [146485](https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/146485/OPEN_MORE). Stable storage IDs are `-147539`, `-129841`, and `-146485`; displayed references remain positive.

A real unsigned production `POST /check` was also run through the normal job lock/cooldown. It accepted run **64f554e4-f8a5-42a4-bb8a-c8c13242f159** at 08:33:44 PHT and finished at 08:34:50 PHT: **0 new, 2 existing records refreshed**, Existing succeeded, Modern failed at the old guard. Production Modern saves are therefore **0**, not 167. The 167 count is verified retrieval by the corrected local adapter, not a claim of production insertion. The database remains 283 Existing records and 0 Modern records until the fix is deployed and a successful normal refresh saves them. Source counts can change as notices close.

Reproduce read-only evidence with `node backend/verify-refresh-live.mjs` (installed Chrome, no database writes). It writes `tool/live-refresh-evidence.json`. `node backend/refresh-status-report.mjs` compares the live backend/project and public per-source counts into `tool/deployed-refresh-evidence.json`. These generated files are ignored by Git.

## Database checks

Flutter and Railway both use **sfgjpefqqqjgpwjvarru.supabase.co**. Source metadata columns are readable on `philgeps_posts`. Both control/history tables exist and correctly deny anonymous SELECT with PostgreSQL `42501`; this is not the earlier missing-table `PGRST205`. The real accepted/finished job and source-history updates demonstrate that deployed service-role access to the claim, finish, and source-history path works. The existing-record writes also succeeded.

Full live constraint definitions and function privilege inspection are unavailable through the public client/schema endpoint. Run the read-only `supabase/verify_refresh_dependencies.sql` as the database owner to inspect the primary/foreign/unique keys and service-role grants. Expected dependencies are `scrape_control` id 1, `claim_scrape_run`, `finish_scrape_run`, `philgeps_source_refresh`, `record_philgeps_source_refresh`, the source/official-ID metadata and unique index, and existing notification/decision tables. This repair introduces no database schema change and does not require rekeying or clearing records. Actual insertion of the first Modern row still needs the repaired backend deployed.

## Changes to merge and deploy

Include all new runtime modules, not only modified tracked files:

- `backend/existing-philgeps.js`: synchronized ASP.NET search and paging, verified empty searches, partial results and actual errors.
- `backend/modern-pagination.js`: official province search, native POST pagination, coverage checks and date splitting.
- `backend/portal-runtime.js`: normalization, bounded transport recovery, safe HTTP/error diagnostics.
- `backend/modern-philgeps.js`, `backend/server.js`, `backend/scrape-control.js`: adapter wiring, `/OPEN_MORE` URLs, partial saves, per-source counters, run UUID correlation, and deployment identity.
- `lib/screens/home_page.dart`: normalized app search and bounded Supabase fetches, retaining the signed-out one-tap flow and automatic reload.
- Tests/package test command, read-only verification scripts, this guide and the dependency-inspection SQL.

Commit these changes on `new_philgeps`, push that branch, merge its PR into **main**, and deploy the resulting main commit to the existing Railway **philgeps_notif_alert** HTTP service (root `/backend`, `npm start`). Keep the separate cron service, its secret and **`0 22 * * *`** schedule unchanged. Redeploy the Flutter frontend for its search/timeout changes.

After deployment: (1) read backend `/` and confirm the new main SHA and `province-post-pagination-v2`; (2) tap Check Updates signed out; (3) follow the same returned run UUID, including in `PORTAL_QUERY`/`SCRAPE_START`/`SCRAPE_FINISH`; (4) inspect `sourceStats` saved counts and any query errors; (5) query Supabase for `source=modern`; (6) select Modern PhilGEPS in the app and confirm the same saved IDs appear without reloading the page. Do not manually seed records or mark refresh success to hide failed coverage.

## Checks

32 backend adapter, HTTP-route, preservation and schedule tests pass. All 13 selected Flutter signed-out refresh/source/date tests pass, including case/extra-space search queries. Web build and Wasm dry run pass. Analysis has no errors and retains the two existing diagnostics (missing flutter_lints include and deprecated anonKey). The daily schedule, notification-log deduplication, saved decisions and PDF/Word implementations are preserved.
