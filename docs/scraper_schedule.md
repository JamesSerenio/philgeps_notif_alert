# Automatic and manual PhilGEPS checks

The existing Railway service is a continuous Express HTTP server built from `backend/Dockerfile` (or the existing Nixpacks configuration). It remains online for dashboard requests. The old in-process 30-minute schedule has been removed, along with the unused node-cron dependency. Opening the dashboard only reads Supabase and last-success metadata; it does not start Playwright.

## Required production setup

These steps have not been applied to your Railway or Supabase accounts.

1. Run `supabase/scrape_control.sql` once in the existing Supabase project's SQL editor. It adds one protected control table and service-role-only RPCs. It does not delete, recreate, or update posts, notification logs, device tokens, decisions, or document records.
2. Keep the HTTP service's existing root directory (`backend`), Dockerfile/build settings, `npm start`, Supabase credentials and Firebase service account. Do not put a Railway cron schedule on this HTTP service. Keep it continuously available (disable sleeping/serverless behavior for this service), and use one replica as the normal deployment configuration.
3. Set HTTP-service variables:
   - `MANUAL_SCRAPER_EMAILS`: comma-separated approved email addresses (empty means nobody may start manual runs).
   - `SCRAPER_CRON_SECRET`: a strong random secret, shared only with the cron worker.
   - Keep `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `FIREBASE_SERVICE_ACCOUNT` on the HTTP server.
4. In Supabase Authentication, create/invite the approved email accounts and enable email authentication. Configure the Magic Link email template to include the numeric `{{ .Token }}` code so the dashboard can verify the code on web and mobile. Automatic account creation is disabled in the dashboard sign-in request. The server requires a confirmed, non-anonymous user whose email is on the allowlist.
5. Create **one separate Railway cron service** from the same repository, with root directory `backend`, using the existing Dockerfile. In that service's dashboard settings apply:

   | Setting | Value |
   | --- | --- |
   | Start command | `node cron-worker.js` |
   | Cron schedule (UTC) | `0 10,22 * * *` |
   | Restart policy | Never |
   | Replicas | 1 |
   | HTTP health check | None |

   Set `SCRAPER_BACKEND_URL` to the continuously running backend's HTTPS URL and `SCRAPER_CRON_SECRET` to the same server-only secret. Do not give the worker the Supabase service-role key or Firebase credential; it uses the HTTP service's scraper. The worker waits for completion, exits 0 on success/intentional skip, and exits 1 on failure/timeout. Remove any old Railway schedules or external schedulers that call `/check`.
6. Deploy the HTTP service and updated Flutter app after applying the migration and variables. The default Flutter backend URL remains the existing production Railway URL. Override it when necessary using `flutter build web --dart-define=SCRAPER_BACKEND_URL=https://your-backend.example` (without a trailing slash). No privileged key or cron secret belongs in Flutter.

Railway schedules use UTC and require the cron process to exit: [Railway cron documentation](https://docs.railway.com/cron-jobs). At 10:00 UTC it is 6 PM Philippine Time; at 22:00 UTC it is 6 AM Philippine Time the following day. The worker's trigger endpoint accepts only these hours, with a ten-minute launch allowance for Railway startup delays, and deduplicates each time slot in the database. A deployment at other hours exits without scraping.

`backend/railway-cron.toml` records the matching legacy config-as-code settings. For new services, use the dashboard settings above: Railway's [config-as-code documentation](https://docs.railway.com/config-as-code) says new services cannot opt into TOML config-as-code. Do not apply the cron settings to the continuously running HTTP service.

Supabase email code behavior is documented in [passwordless email authentication](https://supabase.com/docs/guides/auth/auth-email-passwordless).

## Endpoint behavior

- `POST /check`: requires a Supabase user access token in `Authorization: Bearer ...`. The server verifies it with Supabase Auth and checks the email allowlist. Returns 202 with a run ID on acceptance; 200 with the existing run if already active; 429 with `Retry-After: 120` for the shared manual cooldown; 401/403 for unauthorized callers. GET `/check` no longer starts scraping.
- `GET /check/status`: same user authorization; returns current run status, counters, errors and `lastSuccessAt`. It never starts a scrape.
- `POST /internal/check`: requires the server-only cron secret; requests the same scraper and notifications with trigger `AUTOMATIC`. Outside-schedule and duplicate-slot invocations are skipped.
- `GET /internal/check`: same cron authorization, for worker status polling.
- `GET /check/last-success`: public read-only timestamp metadata. It cannot start work or access posts/tokens.
- The old single-reference `/refresh-delivery-period` Playwright endpoint now also requires approved-user authorization.

The database serializes claims across replicas and worker invocations. The 120-second manual cooldown is measured from the previous manual start and does not change the automatic cron. A manual request during any active run joins that run; a cron trigger during a manual run also joins it instead of opening another browser. The application does not queue an extra overlapping scrape. Database failures fail closed.

The browser execution limit remains 18 minutes. A 30-minute database lease allows recovery after a crashed deployment; expired status is presented as a failed run. Before each post write and deadline reminder, the scraper checks that it still owns the lease. The previous stale-lock reset, which could start a second run before the old one had finished, has been removed. Supabase HTTP requests have a 30-second timeout.

## Dashboard behavior and data

The yellow button shows `Check Updates`, `Checking PhilGEPS...`, `Updated successfully`, `No new opportunities found`, or `Update failed — Retry`. It is disabled during sign-in/request/scraping. If necessary, the approved user enters an email verification code first. A valid session is reused and refreshed when expired.

The dashboard polls completion every five seconds for up to 25 minutes, with a timeout on individual requests. Acceptance and busy responses never show success. After backend completion, the app waits for any old post fetch and performs a fresh Supabase reload. A refresh failure is reported rather than silently displaying success. The last successful scrape is read on startup and every minute and rendered explicitly in UTC+8/PHT, independent of the device's timezone.

Both trigger types call the same existing scraper with all 18 configured LGU search terms, geographic restrictions, upsert-by-reference logic, first-discovery timestamp preservation, saved-decision preservation, new-alert deduplication and deadline notifications. Existing complete-detail records retain the existing skip behavior; `refreshedCount` counts only existing candidates actually processed. A failed LGU makes the overall run fail while preserving any records already saved. No existing Supabase data is cleared. Bidding Documents, Done, copy, PhilGEPS links and dashboard filters retain their existing code.

Every run logs structured `SCRAPE_START` and `SCRAPE_FINISH` events with MANUAL/AUTOMATIC, times, duration, checked/failed LGUs, new and refreshed counts, and status. Existing scraper logs remain. Counts on thrown failures reflect saves completed before the failure; a startup failure has no checked LGUs. The control table retains the latest run and last successful time across restarts; Railway logs retain individual run history.

## Validation

Results will be recorded after the final checks. No production scrape, remote migration, notification send, or Railway deployment was performed. Database concurrency and cooldown behavior require the supplied SQL migration; local coordinator tests mock its atomic claim boundary.

## Files for this change

Modified: `backend/server.js`, `backend/package.json`, `backend/package-lock.json`, `lib/main.dart`, `lib/screens/home_page.dart`, `lib/widgets/home/dashboard_sections.dart`, `README.md`.

Added: `backend/scrape-control.js`, `backend/cron-worker.js`, `backend/railway-cron.toml`, `backend/scrape-control.test.mjs`, `supabase/scrape_control.sql`, `lib/services/scrape_api.dart`, `lib/widgets/home/scraper_sign_in.dart`, `test/scrape_api_test.dart`, `test/dashboard_scrape_test.dart`, and this guide. This is separate from the preceding PDF Editor removal.
