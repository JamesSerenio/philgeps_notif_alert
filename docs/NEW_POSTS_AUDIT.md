# NEW-post audit: November 8, 2026

Read-only verification used Flutter's configured Supabase host, sfgjpefqqqjgpwjvarru.supabase.co, with the same public credential used by the app. All eight references returned HTTP 200. There are 281 visible records. None qualifies for NEW at November 8, 05:48 Philippine time. No database rows were changed during verification.

| Reference | First stored (Philippine time) | Stored publication date (PH) | Closing (PH) | Stored status |
| --- | --- | --- | --- | --- |
| 13306152 | October 24, 01:00:57 | October 24 | November 13, 12:00 | old |
| 13306135 | October 24, 01:00:59 | October 24 | November 13, 12:00 | old |
| 13315332 | October 29, 02:31:25 | October 29 | November 9, 17:00 | old |
| 13278266 | October 9, 04:31:25 | October 9 | November 9, 09:00 | old |
| 13292869 | October 19, 02:00:57 | October 19 | November 9, 12:00 | old |
| 13300031 | October 21, 02:30:58 | October 21 | November 9, 09:00 | old |
| 13321123 | October 31, 02:31:19 | October 31 | November 23, 09:00 | old |
| 13321142 | October 31, 02:31:21 | October 31 | November 23, 09:00 | old |

The latest visible discovery is reference 13320869, November 2 at 01:31:09 PH (November 1 at 17:31:09 UTC). Its persisted status is new, demonstrating why a stored status alone cannot implement an expiring badge.

## Causes and changes

- Every named record has an empty delivery_period. The scraper intentionally revisits such rows for detail backfill, but its logs and /check count called these new matching posts. Logs now call them candidates and the successful-save count distinguishes new references from refreshes.
- Dashboard counter and filtering used stored status; an alternate helper used publication date. Counter, filter, and badge now share the exact rule: 0 <= current UTC time minus discovery time < 24 hours.
- ProjectPost carries discovery time through copyWith. created_at is used because the existing insert/upsert path omits it on updates and the observed records retain their original October insertion dates. A preexisting first_seen_at is supported if present. No migration, timestamp backfill, or reset is performed.
- Publication and closing dates are unchanged. A recent discovery can still have a closed deadline badge. The details display publication and discovery separately.
- Dashboard loads every Supabase page, sorts by discovery time, refreshes on Realtime changes, every 60 seconds, and on app resume. Check Updates refetches this same complete source rather than replacing it with Railway's active-only response. Local decisions changed during an in-flight fetch are preserved.
- Backend database reads are paginated and abort on errors. Upserts preserve created_at, is_bidding_doc, is_done and done_at. New-notification eligibility uses the saved creation timestamp rather than publication date. Existing notification-log deduplication remains intact.

## Deployment and verification limits

The running Railway health endpoint does not expose its Supabase hostname. There is no local Railway credential/configuration proving its deployed environment points to the same project. The patch exposes only the hostname in health and /check responses; Flutter warns if /check reports a different project. Compare its value after deployment with sfgjpefqqqjgpwjvarru.supabase.co. API keys are never exposed.

Realtime depends on database replication being enabled for philgeps_posts. The 60-second refetch remains available if replication is disabled or the socket disconnects. RLS permits reading all eight records with the actual Flutter credential; privileged RLS definitions and triggers were not accessible. No live insert or push notification was sent for validation. Existing publication dates were not independently re-scraped in this scoped synchronization fix.

Deploy both the Flutter build and Railway backend for these local changes to affect production. Existing data will correctly continue to show zero NEW until a qualifying first discovery is stored; the eight October records must not be made new again.

## Modified files

- backend/server.js
- lib/main.dart (helper import only)
- lib/models/project_post.dart
- lib/screens/home_page.dart
- lib/widgets/home/dashboard_sections.dart
- lib/utils/post_dates.dart (new)
- backend/post-discovery.test.mjs (new)
- test/post_dates_test.dart (new)
- test/post_discovery_test.dart (new)
- test/dashboard_refresh_web_test.dart (new)
- docs/NEW_POSTS_AUDIT.md (this report)

## Validation

- Backend: six regression tests passed, covering pagination, failure handling, refresh-vs-new classification, immutable discovery timestamps, unchanged user decisions, late-discovery notifications, and the exact 24-hour boundary.
- Flutter native date tests: three passed, including all eight verified first-discovery timestamps.
- Flutter Chrome model tests: three passed.
- Flutter Chrome dashboard integration: passed, including 1,001 initial records, a newly discovered 1,002nd record, automatic periodic refetch, ordering, NEW filtering, expired deadlines, saved Bidding Documents, and concurrent-fetch coalescing. The WebSocket is intentionally unavailable at the mock hostname, exercising the polling fallback.
- Flutter analyze: no errors; 18 pre-existing warnings/info remain, including the missing flutter_lints include and PDF editor diagnostics.
- node --check backend/server.js and git diff --check passed.

On this Windows Flutter SDK, the browser test server returned 404 for /canvaskit/chromium/canvaskit.js and .wasm despite those files existing in the SDK. Chrome tests passed after a temporary browser route served the same unchanged SDK assets and reloaded the test iframe. No Flutter SDK or production app code was changed for that workaround.

Supabase's official [Flutter subscription documentation](https://supabase.com/docs/reference/dart/subscribe) notes that replication must be enabled for table change events; the periodic refetch does not depend on that setting.
