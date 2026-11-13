# Automatic and manual PhilGEPS checks

The existing Railway service is a continuous Express HTTP server built from `backend/Dockerfile` (or the existing Nixpacks configuration). It remains online for dashboard requests. The old in-process 30-minute schedule has been removed, along with the unused node-cron dependency. Opening the dashboard only reads Supabase and last-success metadata; it does not start Playwright.

## Required production setup

These steps have not been applied to your Railway or Supabase accounts.

1. Run `supabase/scrape_control.sql` once in the existing Supabase project's SQL editor. It adds one protected control table and service-role-only RPCs. It does not delete, recreate, or update posts, notification logs, device tokens, decisions, or document records.
2. Keep the HTTP service's existing root directory (`backend`), Dockerfile/build settings, `npm start`, Supabase credentials and Firebase service account. Do not put a Railway cron schedule on this HTTP service. Keep it continuously available (disable sleeping/serverless behavior for this service), and use one replica as the normal deployment configuration.
3. Set HTTP-service variables:
   - `MANUAL_SCRAPER_EMAILS`: retained only for the protected single-reference delivery-detail refresh. It is not used by public Check Updates.
   - `SCRAPER_CRON_SECRET`: a strong random secret, shared only with the cron worker.
   - Keep `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `FIREBASE_SERVICE_ACCOUNT` on the HTTP server.
4. Public Check Updates does not require a Supabase account, email, OTP, or browser session. Existing authentication and allowlists still apply to protected delivery-detail actions. No service-role key or cron secret is sent from Flutter.
5. Create **one separate Railway cron service** from the same repository, with root directory `backend`, using the existing Dockerfile. In that service's dashboard settings apply:

   | Setting | Value |
   | --- | --- |
   | Start command | `node cron-worker.js` |
   | Cron schedule (UTC) | `0 22 * * *` |
   | Restart policy | Never |
   | Replicas | 1 |
   | HTTP health check | None |

   Set `SCRAPER_BACKEND_URL` to the continuously running backend's HTTPS URL and `SCRAPER_CRON_SECRET` to the same server-only secret. Do not give the worker the Supabase service-role key or Firebase credential; it uses the HTTP service's scraper. The worker waits for completion, exits 0 on success/intentional skip, and exits 1 on failure/timeout. Remove any old Railway schedules or external schedulers that call `/check`.
6. Deploy the HTTP service and updated Flutter app after applying the migration and variables. The default Flutter backend URL remains the existing production Railway URL. Override it when necessary using `flutter build web --dart-define=SCRAPER_BACKEND_URL=https://your-backend.example` (without a trailing slash). No privileged key or cron secret belongs in Flutter.

Railway schedules use UTC and require the cron process to exit: [Railway cron documentation](https://docs.railway.com/cron-jobs). The sole automatic run is at 22:00 UTC, which is 6 AM Philippine Time the following day. The worker's trigger endpoint accepts only this hour, with a ten-minute launch allowance for Railway startup delays, and deduplicates the daily time slot in the database. A deployment at other hours exits without scraping. Replace the previous `0 10,22 * * *` setting on the existing cron service with `0 22 * * *`; do not create a second cron service. The old 6 PM automatic run is disabled in both the cron configuration and backend guard. Manual `/check` requests have no time-of-day restriction.

`backend/railway-cron.toml` records the matching legacy config-as-code settings. For new services, use the dashboard settings above: Railway's [config-as-code documentation](https://docs.railway.com/config-as-code) says new services cannot opt into TOML config-as-code. Do not apply the cron settings to the continuously running HTTP service.

Supabase email code behavior is documented in [passwordless email authentication](https://supabase.com/docs/guides/auth/auth-email-passwordless).

## Endpoint behavior

- `POST /check`: public fixed-job refresh, without user authentication. Returns 202 with a run ID on acceptance; 200 with the existing run if already active; 429 with `Retry-After: 120` for the shared manual cooldown. An additional bounded request limiter returns 429 with `Retry-After: 60`. GET `/check` does not start scraping.
- `GET /check/status`: public, uncached run status, counters, source errors and `lastSuccessAt`, subject to the request limiter. It never starts a scrape.
- `POST /internal/check`: requires the server-only cron secret; requests the same scraper and notifications with trigger `AUTOMATIC`. Outside-schedule and duplicate-slot invocations are skipped.
- `GET /internal/check`: same cron authorization, for worker status polling.
- `GET /check/last-success`: public read-only timestamp metadata. It cannot start work or access posts/tokens.
- The old single-reference `/refresh-delivery-period` Playwright endpoint now also requires approved-user authorization.

The database serializes claims across replicas and worker invocations. The 120-second manual cooldown is measured from the previous manual start and does not change the automatic cron. A manual request during any active run joins that run; a cron trigger during a manual run also joins it instead of opening another browser. The application does not queue an extra overlapping scrape. Database failures fail closed.

The browser execution limit remains 18 minutes. A 30-minute database lease allows recovery after a crashed deployment; expired status is presented as a failed run. Before each post write and deadline reminder, the scraper checks that it still owns the lease. The previous stale-lock reset, which could start a second run before the old one had finished, has been removed. Supabase HTTP requests have a 30-second timeout.

## Dashboard behavior and data

The yellow button shows `Check Updates`, `Checking PhilGEPS…`, `Updated successfully`, `No new opportunities found`, or `Update failed — Retry`. It is disabled during the request and scraping. It never opens an email/OTP prompt or requests an access token. Signed-out callers start or join the shared public-notice refresh for both portals. Source errors remain visible after the dashboard reloads partial results.

The dashboard polls completion every five seconds for up to 25 minutes, with a timeout on individual requests. Acceptance and busy responses never show success. After backend completion, the app waits for any old post fetch and performs a fresh Supabase reload. A refresh failure is reported rather than silently displaying success. The last successful scrape is read on startup and every minute and rendered explicitly in UTC+8/PHT, independent of the device's timezone.

Both trigger types call the same existing scraper with all 18 configured LGU search terms, geographic restrictions, upsert-by-reference logic, first-discovery timestamp preservation, saved-decision preservation, new-alert deduplication and deadline notifications. Existing complete-detail records retain the existing skip behavior; `refreshedCount` counts only existing candidates actually processed. A failed LGU makes the overall run fail while preserving any records already saved. No existing Supabase data is cleared. Bidding Documents, Done, copy, PhilGEPS links and dashboard filters retain their existing code.

Every run logs structured `SCRAPE_START` and `SCRAPE_FINISH` events with MANUAL/AUTOMATIC, times, duration, checked/failed LGUs, new and refreshed counts, and status. Existing scraper logs remain. Counts on thrown failures reflect saves completed before the failure; a startup failure has no checked LGUs. The control table retains the latest run and last successful time across restarts; Railway logs retain individual run history.

## Validation

- Backend: 16 tests passed, including the sole daily 6 AM schedule, authentication, duplicate-run coordination, failure states, notification deduplication, browser/context cleanup on success and failure, and worker exit codes.
- Flutter: 12 tests passed, including mocked dashboard completion/refresh, repeated clicks, failure states, PHT display, and narrow mobile layout.
- flutter analyze: no errors; two existing diagnostics remain (missing flutter_lints include and deprecated anonKey). Exit code 1 due to those diagnostics.
- flutter build web: passed in the preceding implementation, including the Wasm dry run; not rerun for this backend schedule-only update. No Flutter implementation changed in this update.
- Node syntax checks and git diff --check: passed.
- The existing browser-only tests are excluded by the standard VM test command; dashboard interaction coverage here runs through the new mocked VM widget test.

 No production scrape, remote migration, notification send, or Railway deployment was performed. Database concurrency and cooldown behavior require the supplied SQL migration; local coordinator tests mock its atomic claim boundary.

## Files for this change

Modified: `backend/post-discovery.test.mjs`, `backend/server.js`, `backend/package.json`, `backend/package-lock.json`, `lib/main.dart`, `lib/screens/home_page.dart`, `lib/widgets/home/dashboard_sections.dart`, `README.md`.

Added: `backend/scrape-control.js`, `backend/cron-worker.js`, `backend/railway-cron.toml`, `backend/scrape-control.test.mjs`, `supabase/scrape_control.sql`, `lib/services/scrape_api.dart`, `lib/widgets/home/scraper_sign_in.dart`, `test/scrape_api_test.dart`, `test/dashboard_scrape_test.dart`, and this guide. This is separate from the preceding PDF Editor removal.

## Once-daily schedule update

This follow-up changes only `backend/scrape-control.js`, `backend/railway-cron.toml`, `backend/scrape-control.test.mjs`, the schedule comment in `backend/server.js`, `README.md`, and this guide. No files or dependencies were added. Manual authorization, rate limits, shared locking, scraping filters, browser cleanup, notifications, Flutter behavior, and Supabase data are unchanged.

Deploy the updated HTTP backend and cron worker, then change the existing Railway cron service schedule to `0 22 * * *`. Keep its start command `node cron-worker.js`, restart policy Never, and a single cron service/replica. Keep the HTTP service online without a cron schedule. If the preceding deployment is already configured, no additional SQL migration, authentication change, or Flutter deployment is needed. If not, complete the initial setup above. Live Railway settings were not changed here.
