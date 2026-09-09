Refactor and cleanup report

The public PdfService.generateBidDocs API and existing screen entry points are unchanged. Feature files use Dart library parts to retain private access without duplicating state, adding public helper APIs, or changing callback timing. Screen extensions delegate setState through a thin State-owned method.

| Entry file | Before | After | Responsibility retained |
|---|---:|---:|---|
| lib/pdf_editor/services/pdf_service.dart | 7460 | 393 | PDF orchestration and final bytes |
| lib/pdf_editor/screens/pdf_editor_screen.dart | 2826 | 530 | State ownership, lifecycle, and screen layout |
| lib/main.dart | 1374 | 83 | Application startup and app root |

Created files

- lib/models/project_post.dart
- lib/pdf_editor/formatters/editor_input_formatters.dart
- lib/pdf_editor/models/editor_entries.dart
- lib/pdf_editor/screens/pdf_editor/editor_persistence.dart
- lib/pdf_editor/screens/pdf_editor/editor_preview.dart
- lib/pdf_editor/screens/pdf_editor/specification_editing.dart
- lib/pdf_editor/services/pdf/pdf_bid_form_service.dart
- lib/pdf_editor/services/pdf/pdf_bid_price_summary_service.dart
- lib/pdf_editor/services/pdf/pdf_bid_security_legacy_service.dart
- lib/pdf_editor/services/pdf/pdf_bid_security_service.dart
- lib/pdf_editor/services/pdf/pdf_certificate_service.dart
- lib/pdf_editor/services/pdf/pdf_field_service.dart
- lib/pdf_editor/services/pdf/pdf_financial_service.dart
- lib/pdf_editor/services/pdf/pdf_jurat_service.dart
- lib/pdf_editor/services/pdf/pdf_omnibus_service.dart
- lib/pdf_editor/services/pdf/pdf_page_service.dart
- lib/pdf_editor/services/pdf/pdf_price_schedule_service.dart
- lib/pdf_editor/services/pdf/pdf_schedule_requirements_service.dart
- lib/pdf_editor/services/pdf/pdf_secretary_certificate_service.dart
- lib/pdf_editor/services/pdf/pdf_slcc_service.dart
- lib/pdf_editor/services/pdf/pdf_technical_specs_service.dart
- lib/pdf_editor/services/pdf/pdf_text_service.dart
- lib/pdf_editor/widgets/editor_controls.dart
- lib/pdf_editor/widgets/sidebar/bid_security_section.dart
- lib/pdf_editor/widgets/sidebar/certificate_sections.dart
- lib/pdf_editor/widgets/sidebar/editor_fields.dart
- lib/pdf_editor/widgets/sidebar/omnibus_section.dart
- lib/pdf_editor/widgets/sidebar/price_schedule_section.dart
- lib/pdf_editor/widgets/sidebar/schedule_requirements_section.dart
- lib/pdf_editor/widgets/sidebar/slcc_section.dart
- lib/pdf_editor/widgets/sidebar/technical_specs_section.dart
- lib/screens/home_page.dart
- lib/services/notification_service.dart
- lib/widgets/home/dashboard_sections.dart
- docs/refactor_cleanup.md (this report)

Modified existing files

- lib/pdf_editor/services/pdf_service.dart: rendering implementations moved by PDF feature; public generator retained.
- lib/pdf_editor/screens/pdf_editor_screen.dart: persistence, preview, sidebar builders, controls, entry models, and formatters moved without changing state ownership.
- lib/main.dart: notification service, project model, home screen, and dashboard builders extracted while retaining the same public library.
- lib/pdf_editor/data/page_mapping.dart: formatter-only change from the requested dart format lib run. The 88-line page_mapper.dart remains focused and unchanged.

Deleted files (audited before removal)

- lib/pdf_editor/widgets/editor_sidebar.dart: empty, no references.
- lib/pdf_editor/widgets/editor_toolbar.dart: empty, no references.
- lib/pdf_editor/widgets/pdf_canvas.dart: empty, no references.
- lib/pdf_editor/models/pdf_attachment.dart: no imports or references to PdfAttachment.
- lib/pdf_viewer_page.dart: no imports, routes, or references to PdfViewerPage.

The audit searched Dart sources, tests, asset declarations and dynamic paths, backend, scripts, platform/web configuration, and hidden project configuration. No standard project folders were deleted.

Removed dead methods

- _drawTechnicalSpecificationsSignature and _drawTechnicalSpecificationsCompliance: declarations had no callers.
- _downloadGeneratedPdf and _printGeneratedPdf: unused private editor helpers.
- The local replaceLine function in _drawBidForm: no calls in its scope.

Intentionally kept

- Every assets/pdf template, including TAX_template.pdf. Its intended future use is uncertain. All PDF hashes match their pre-refactor values.
- tmp-chromium-print.pdf, tmp-fit.png, tmp-page2.jpg, tmp-pdf.png: possible reference/debug artifacts; ownership or future use uncertain.
- Platform folders, backend, Supabase SQL, build, .dart_tool, web assets, scripts, and dependency configuration.
- Existing non-dead warnings and deprecations; no unrelated behavior fixes.

Preservation checks

- 49 retained PDF helper bodies compared mechanically with their originals; only extraction/formatting and the audited dead local function removal differ.
- Before/after PDF snapshots cover all three SLCC and Bid Securing Declaration options, both Omnibus variants, dynamic metadata, one technical-specification item, price calculations, and schedule totals. Snapshots compare page sizes, page order, text, font names/sizes, and word coordinates. Local snapshots live under .dart_tool/refactor_validation.
- Selection callbacks remain save-only. Generate PDF remains the sole normal full-generation trigger.

Validation results

- dart format lib: completed.
- flutter analyze: no errors; 16 existing warnings/informational notices remain (missing flutter_lints include, deprecations, and existing redundant checks/assertion).
- flutter build web --no-pub: succeeded. The existing dart:html dependency prevents the optional Wasm dry run; the JavaScript web build is successful.
- PDF snapshot comparisons: all three before/after scenarios passed exactly.
- Full tests plus snapshots: 15 passed, 1 failed. The failure is the pre-existing Omnibus address expectation in test/pdf_service_omnibus_test.dart; it also failed against the unchanged generator before this refactor and was deliberately left untouched.
- Browser smoke: compiled home screen and PDF editor opened using fixture data and intercepted Supabase requests. No real bid data was modified.
- git diff --check: passed.
