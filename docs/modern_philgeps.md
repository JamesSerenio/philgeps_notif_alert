# Modern PhilGEPS integration

The dashboard searches refreshed records from both official sources. All Sources is the default; source selection and existing keywords are saved locally. Publication and closing ranges use inclusive Philippine calendar dates. The current monitored LGUs and Bukidnon/Misamis Oriental restrictions remain in place. This is not an unrestricted nationwide live search.

## Deployment

1. Review and apply `supabase/modern_philgeps.sql` in the existing project. It adds metadata columns, a unique `(source, official_notice_id)` index, a protected refresh-history table, and a service-role-only history RPC. It never changes existing primary IDs or saved decisions. It rejects negative legacy IDs rather than silently colliding with them. Check existing table constraints and foreign keys before applying: the live schema was unavailable during development (the configured public key returned HTTP 401).
2. Deploy the backend with the existing server-only Supabase service-role and Firebase configuration. No Modern credentials are needed for permitted public searches. Keep Playwright Chromium installed through the existing build.
3. Deploy the Flutter app. The existing Railway worker, authorization, cooldown, shared lease, and `0 22 * * *` schedule remain in place. Both manual Check Updates and the scheduled worker invoke both adapters. Do not create another schedule.

Modern storage IDs are negative official notice numbers, e.g. `-130491`, supporting existing text or signed integer IDs without modifying old records. The visible reference remains `130491`; the source and official ID are stored separately. Existing positive IDs stay unchanged. Notifications and saved selections continue to use the primary ID. No cross-portal merge is inferred from equal numbers or similar titles. Both independently sourced records and links remain available until a match can be verified; unverified cross-portal identity cannot safely suppress an alert.

## Public portal verification (13 November 2026)

The official public search is a session/CSRF-protected POST to `https://philgeps.gov.ph/Indexes/index`. The adapter submits the native form, retaining the official cookie/token. It uses the links actually returned in result rows; it never converts a legacy reference into a Modern URL.

Read-only Chrome verification confirmed:

- Reference `130491`: one result, with official URL `https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491`.
- Title `Food Supplies`: 86 results.
- Agency `MUNICIPALITY OF SUMILAO BUKIDNON`: four results. Bare `SUMILAO` returned zero, so scheduled searches use complete agency names.
- Reference `130491` plus closing range `13-Nov-2026` through `30-Nov-2026`: one result closing at 09:00 AM PHT on 19 November.
- Notice details: Bukidnon, delivery period 15, ABC PHP 2,580,000.
- Documents → Preview requests `/Tenders/tender_doc_view/130491/130491`. The anonymous response, including in the browser search session, is an HTML session-expired/login page. It is **Login / Access Required**, not a verified public bidding document.

Document checks recognize official PDF responses by both MIME type and PDF signature, distinguishing attachment downloads from inline previews. Login/authorization responses link to the official portal. HTML wrappers, missing links, unexpected files, and network failures remain BDocs Not Verified. HTTP 429 stops the source rather than retrying around the limit. Login, CAPTCHA, payment and authorization are never bypassed. Other document formats or HTML preview wrappers need further official verification before being labeled accessible.

The adapter queries the existing monitored municipality agencies, retains actual official notice links, verifies detailed delivery location, and uses source-specific IDs. It spaces requests and reports a potentially truncated result set (100 or more rows / a next-page control) as a source failure instead of silently claiming a complete refresh. Broader agency coverage, nationwide results and verified pagination beyond that bound require additional portal verification.

## Refresh and preservation

Sources run independently within the existing single lease. A source failure does not stop the other portal. Records saved before a write failure are counted accurately. The dashboard reloads available data even after a partial refresh fails and shows each source's error and previous successful refresh. History is updated atomically: a failed attempt preserves that source's last successful timestamp.

Upserts omit `created_at`, saved BDocs decisions, Done flags and dates. First-discovery-based New Posts and existing notification-log checks are retained. Modern IDs cannot collide with positive legacy references. No database records, notification history, PDF editor, PDF generator, or Microsoft Word generator are deleted or rewritten by this change. No production migration, refresh, notification, or deployment was performed during development.

## Validation commands

Local results: 20 backend tests and 13 selected Flutter tests passed. Responsive tests exercise actual card/source/access taps and independent BDocs selections at 360, 768 and 1400 pixels, source filters, and inclusive closing dates. Web build and Wasm dry run passed. Analysis reported no errors and retained two pre-existing diagnostics (missing flutter_lints include and deprecated anonKey); its exit code is 1. Node syntax and whitespace checks passed.

- `cd backend` then `npm.cmd test`: adapter access/URL/date checks, existing discovery/notification tests, schedule/authorization tests, and both source-failure directions.
- `flutter test test/modern_sources_test.dart test/dashboard_scrape_test.dart test/scrape_api_test.dart test/post_dates_test.dart`: model preservation, source filters, searches, responsive navigation and refresh regressions.
- `flutter analyze --no-pub`; `flutter build web --no-pub`; `node --check backend/server.js`; `git diff --check`.
- Optional bounded public verification: `node backend/modern-probe.mjs` (installed Chrome; no database writes or alerts). Use sparingly and respect official request limits.

Remote SQL execution and constraints, production scheduler settings, authorized document access, physical mobile/tablet/desktop browser behavior, and PDF/Word workflows need validation against the configured deployment. Existing PDF/Word implementations were not present among the edited files and were not exercised here.
