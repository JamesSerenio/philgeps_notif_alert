# Shared BDocs project metadata repair

## Evidence and root cause

Both Flutter (`lib/utils/supabase_client.dart`) and React
(`C:/Projects/philgeps-editor/src/supabase.js`) point to Supabase project
`sfgjpefqqqjgpwjvarru`.

The shared row is `public.philgeps_posts`; editor sections are in
`public.bid_docs_editor_state`, linked by `project_id = philgeps_posts.id`.
Project IDs must remain unchanged. References are editable metadata, not IDs.

Reference **132124** is project `fc066763-84a8-4423-bbd8-eada9101c201`.
Its saved `bid_security.documentSetup` contains the title, reference, agency,
SUMILAO, BUKIDNON, document date 2026-11-16 and deadline 2026-11-19.
The corresponding shared columns were empty. A second manual project,
`f0c311c2-c46f-4299-9794-b7f635655fbc` (reference 131859), has the same problem.
Two older selected projects already have populated shared metadata.

The editor previously saved JSON through the persistence hook, but separately
scheduled an unverified post-row update. That request could affect zero rows,
and leaving the editor could cancel its timer. The JSON save alone displayed
Saved. A real recovery PATCH using the current public client returned HTTP 200
with zero affected rows for both projects. Public UPDATE policy/access therefore
remains a production dependency; an HTTP success alone does not prove a save.

## Canonical mapping

| Saved setup key | Shared column |
| --- | --- |
| projectTitle | title |
| referenceNumber | reference_number |
| procuringEntity | procuring_entity |
| municipality | lgu |
| province | area_of_delivery |
| closingDate, manual projects only | manual_deadline (date) |

`date` remains a document date in editor JSON. It never becomes `posting_date`.
Official imported `closing_date` stays separate from a manual deadline.
Company data, template settings, document sections, prices, decisions, and logs
retain their existing storage.

## Required production step

Run **supabase/project_metadata_sync.sql** as the database owner in the SQL
Editor for project **sfgjpefqqqjgpwjvarru**. The identical migration is included
in both repositories. It:

- Adds per-field manual-override markers without changing IDs.
- Recovers only missing shared metadata from existing saved JSON, retaining
  populated shared values and all editor JSON.
- Commits subsequent editor JSON and shared metadata in the same transaction.
- Uses database-generated revisions to reject stale autosave requests.
- Preserves manual/edited metadata against service-role scraper updates.
- Does not grant anonymous users general UPDATE access to posts.

The final SELECT prints the two affected stable IDs and recovered columns.
Expected reference 132124 values are the water-meter title, MUNICIPALITY OF
SUMILAO, BUKIDNON, SUMILAO, BUKIDNON, and manual_deadline 2026-11-19.
The document date remains only in saved editor setup.

Apply the migration before deploying the React save-service changes. Those
changes deliberately report an actionable error if shared persistence cannot be
verified; they retain the draft and its last known server revision.

Deploy the React editor build from `C:/Projects/philgeps-editor`, then the Flutter
web build. The Railway scraper preservation change is in `backend/server.js`;
the configured Railway service is `philgeps_notif_alert`, branch `main`, root
`/backend`. This task does not deploy or merge any branch, change refresh
schedules, or change notification deduplication.

## Read and refresh behavior

React list cards query the canonical row and prefer manual_deadline. Returning
from the editor waits for successful persistence. Focus and verified-save events
reload the list; request versions prevent older fetches replacing newer results.
Flutter's normal paginated post reload/reopen and realtime refresh read the same
columns. Both distinguish a missing ABC (Not available) from a stored zero.
Date-only deadlines display the selected Philippine calendar date, with countdown
through that day's end; official timestamp deadlines keep their actual time.

## Verification

- `node --experimental-vm-modules --test tool/test_project_metadata.mjs`: actual
  React save-service tests with fixture Supabase responses, canonical mapping,
  failed shared verification, retry, stale CAS, blank and older records.
- `node tool/test_metadata_sql.mjs`: PGlite executes the real migration; verifies
  recovery, preservation, permissions, transactional rollback, stale revisions,
  scraper protection, and migration rerun. Optional test dependency:
  `npm install --prefix tool/metadata-sql-test --no-save --package-lock=false @electric-sql/pglite`.
- `node tool/test_project_metadata_browser.cjs`: real Chrome/React UI with fixture
  REST responses; tests 132124 save/back/list, reload/reopen same ID, new blank
  project, older project, missing versus zero ABC, missing-trigger save error,
  and rejection of a stale recovered local draft.
  It never changes production records.
- Flutter metadata/model/date/dashboard/source tests: **9 passed**, including a
  real dashboard widget reloading the 132124 shared row from fixture responses.
- Backend tests: **34 passed**, including manual/edited metadata preservation.
- React lint: zero errors, one pre-existing PriceScheduleEditor cleanup warning.
  React production build and Flutter web build passed. Flutter analysis still
  reports the pre-existing missing flutter_lints include and deprecated anonKey.

Production recovery is **not yet verified**: owner database access was unavailable
and the attempted public update affected zero rows. After applying the migration,
open 132124, confirm Saved, return to the list, reload, reopen the original card,
then refresh Flutter. Verify both affected records with the migration's SELECT.
