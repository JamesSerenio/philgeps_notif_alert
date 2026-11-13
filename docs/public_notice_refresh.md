# Signed-out Check Updates

Public notice refresh no longer requires email, OTP, or a Supabase user session. Flutter sends an unsigned `POST /check`, follows the returned run ID through unsigned `GET /check/status`, and reloads Supabase counts and results after the job finishes. Both Existing PhilGEPS and Modern PhilGEPS use the same existing job. Source failures are named and partial saves are reloaded without losing the error message.

The existing shared database lease, 120-second manual cooldown, and one-running-job behavior remain authoritative across browser sessions and server instances. Concurrent taps join the active job instead of queueing extra jobs. The public endpoints also have an in-process request limiter and uncached responses. No server credentials are exposed. The scheduled trigger still requires `SCRAPER_CRON_SECRET`; delivery-detail refresh still requires its existing allowlisted user authentication.

## Deploy this change

- Repository: `JamesSerenio/philgeps_notif_alert`.
- Implementation branch: **`new_philgeps`** (the local branch containing this change; these edits have not been committed or pushed by this task).
- Railway target: the existing continuously running **HTTP backend service serving `https://philgepsnotifalert-production.up.railway.app`**, root directory `backend`, start command `npm start` / `node server.js`. This identifies the exact live backend endpoint; Railway's internal service ID/display name and configured GitHub deployment branch cannot be confirmed without account access. Select `new_philgeps` as the deployment source after these changes are pushed.
- Redeploy the Flutter frontend too. Its default backend URL already points to that HTTP service; keep any existing `SCRAPER_BACKEND_URL` override.
- Keep the separate cron worker and its **`0 22 * * *`** schedule unchanged (06:00 PHT daily). Do not deploy the HTTP start command onto the cron worker or add another scheduler.
- This authentication change needs no new SQL migration or environment variable. Prior `scrape_control.sql` and Modern-source migrations must already be applied for the existing refresh job.

## Verification evidence

The deployed HTTP service was contacted without Authorization before deployment. `GET /` returned 200, while `POST /check` and `GET /check/status` both returned **401**, `Sign in to request a scrape.` No live run was started. A backend deployment is therefore required; removing only the Flutter prompt cannot fix the live endpoint.

Local tests exercise the actual Express route registrations and real HTTP requests with a simulated database/job boundary. They verify unsigned acceptance/polling, repeated requests sharing one run ID, exactly one `SCRAPE_START`/`SCRAPE_FINISH`, and continued rejection of unsigned cron calls. Flutter tests start signed out, tap Check Updates, verify no sign-in prompt or Authorization header, track the run, and reload both-source counts without page navigation. They also exercise an already-running response and named source failure while retaining partial data.

These tests simulate portal jobs and Supabase saves; they do not prove a production Railway scrape or production notification delivery. Railway deployment/log confirmation requires the Railway account connection.

Local validation passed: 22 backend tests, 13 selected Flutter VM tests, and the signed-out button flow in real headless Chrome (including an actual pointer tap). Web build and Wasm dry run passed. Static analysis reports no errors and the same two existing diagnostics: missing `flutter_lints` include and deprecated `anonKey` (exit 1).

On this Windows Flutter SDK, the normal Chrome test stalls because its test server returns 404 for installed CanvasKit files. `node tool/test_signed_out_browser.cjs` runs the browser test with those same local SDK assets routed before the test iframe starts. It changes neither the SDK nor production application. Override `FLUTTER_BIN`, `CHROME_EXECUTABLE`, or `FLUTTER_CANVASKIT_PATH` for a different installation. The ordinary VM command is `flutter test test/dashboard_scrape_test.dart test/scrape_api_test.dart test/modern_sources_test.dart test/post_dates_test.dart --no-pub`.

After deployment, open the updated Flutter frontend in a fresh signed-out browser, tap Check Updates once, and verify one structured `SCRAPE_START` with `trigger: MANUAL` and a run ID in that HTTP service's Railway logs. A repeated tap/session must report the same ID while active. Wait for `SCRAPE_FINISH`, inspect `sourceErrors`, and confirm dashboard counts and Modern search results change without a browser reload. Existing request limits and portal access requirements still apply.
