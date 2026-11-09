# PDF Editor removal inventory

The discontinued editor was removed from Flutter. Bidding Documents and Done retain their existing dashboard logic and Supabase fields. No remote data or saved preferences were deleted.

## Deleted files

- `lib/pdf_editor/data/page_mapping.dart`
- `lib/pdf_editor/formatters/editor_input_formatters.dart`
- `lib/pdf_editor/models/editor_entries.dart`
- `lib/pdf_editor/models/item_pricing.dart`
- `lib/pdf_editor/models/pdf_field.dart`
- `lib/pdf_editor/screens/pdf_editor_screen.dart`
- `lib/pdf_editor/screens/pdf_editor/editor_persistence.dart`
- `lib/pdf_editor/screens/pdf_editor/editor_preview.dart`
- `lib/pdf_editor/screens/pdf_editor/specification_editing.dart`
- `lib/pdf_editor/services/initao_omnibus_numbering.dart`
- `lib/pdf_editor/services/page_mapper.dart`
- `lib/pdf_editor/services/pdf_service.dart`
- `lib/pdf_editor/services/pdf/pdf_bid_form_service.dart`
- `lib/pdf_editor/services/pdf/pdf_bid_price_summary_service.dart`
- `lib/pdf_editor/services/pdf/pdf_bid_security_legacy_service.dart`
- `lib/pdf_editor/services/pdf/pdf_bid_security_service.dart`
- `lib/pdf_editor/services/pdf/pdf_certificate_service.dart`
- `lib/pdf_editor/services/pdf/pdf_document_template_service.dart`
- `lib/pdf_editor/services/pdf/pdf_field_service.dart`
- `lib/pdf_editor/services/pdf/pdf_financial_service.dart`
- `lib/pdf_editor/services/pdf/pdf_image_finalizer_service.dart`
- `lib/pdf_editor/services/pdf/pdf_jurat_service.dart`
- `lib/pdf_editor/services/pdf/pdf_omnibus_service.dart`
- `lib/pdf_editor/services/pdf/pdf_page_service.dart`
- `lib/pdf_editor/services/pdf/pdf_price_schedule_service.dart`
- `lib/pdf_editor/services/pdf/pdf_schedule_requirements_service.dart`
- `lib/pdf_editor/services/pdf/pdf_secretary_certificate_service.dart`
- `lib/pdf_editor/services/pdf/pdf_slcc_service.dart`
- `lib/pdf_editor/services/pdf/pdf_technical_specs_service.dart`
- `lib/pdf_editor/services/pdf/pdf_text_service.dart`
- `lib/pdf_editor/widgets/editor_controls.dart`
- `lib/pdf_editor/widgets/sidebar/bid_security_section.dart`
- `lib/pdf_editor/widgets/sidebar/certificate_sections.dart`
- `lib/pdf_editor/widgets/sidebar/document_template_section.dart`
- `lib/pdf_editor/widgets/sidebar/editor_fields.dart`
- `lib/pdf_editor/widgets/sidebar/omnibus_section.dart`
- `lib/pdf_editor/widgets/sidebar/price_schedule_section.dart`
- `lib/pdf_editor/widgets/sidebar/schedule_requirements_section.dart`
- `lib/pdf_editor/widgets/sidebar/sidebar_design.dart`
- `lib/pdf_editor/widgets/sidebar/sidebar_panel.dart`
- `lib/pdf_editor/widgets/sidebar/slcc_section.dart`
- `lib/pdf_editor/widgets/sidebar/technical_specs_section.dart`
- `assets/pdf/AFS_template.pdf`
- `assets/pdf/BID SECURING DECLARATION_impasugong_template.pdf`
- `assets/pdf/BID SECURING DECLARATION_initao_template.pdf`
- `assets/pdf/bidocs_template.pdf`
- `assets/pdf/certificate_template.pdf`
- `assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf`
- `assets/pdf/NFCC_Template.pdf`
- `assets/pdf/SLCC_CCTV_template.pdf`
- `assets/pdf/SLCC_Streetlight_template.pdf`
- `assets/pdf/SLCC_table_cctv.pdf`
- `assets/pdf/SLCC_table_streetlight.pdf`
- `assets/pdf/TAX_template.pdf`
- `test/bid_security_asset_loading_test.dart`
- `test/document_template_selector_test.dart`
- `test/item_pricing_test.dart`
- `test/item_pricing_web_test.dart`
- `test/nfcc_bounds_test.dart`
- `test/pdf_document_mode_test.dart`
- `test/pdf_marker_rendering_test.dart`
- `test/pdf_service_initao_bid_security_test.dart`
- `test/pdf_service_initao_omnibus_test.dart`
- `test/pdf_service_omnibus_test.dart`
- `test/pdf_service_section_order_test.dart`
- `assets/fonts/seguisym.ttf`
- `web/pdf_download_flatten.js`

## Retained code

- Shared http, intl, shared_preferences, Supabase, Firebase, url_launcher, and dashboard helpers remain in use.
- Railway server, PDF endpoints and pdf-lib dependency, Dockerfile, scraper, and Supabase SQL remain unchanged under the requested backend restriction.
- Root tmp PDF/image artifacts remain because ownership is uncertain.

## Dependencies

Removed syncfusion_flutter_pdfviewer and the PDF and symbol-font asset declarations. See pubspec.lock for removed transitive dependencies.

## Validation

- flutter pub get: passed.
- flutter analyze: no errors; exit 1 for two pre-existing diagnostics (missing flutter_lints include and deprecated Supabase anonKey).
- flutter test: 4 passed. Browser-only tests require the separate Chrome run below.
- flutter build web: passed; Wasm dry run also succeeded.
- node --test backend/post-discovery.test.mjs: 6 passed.
- Source scan: no editor entry points, imports, navigation, Syncfusion usage, or PDF asset references remain in lib, test, web, or pubspec.yaml.
- No backend, Supabase SQL, notification service, dashboard state, post model, or date-helper changes. Live production data and push delivery were not exercised.


## Modified files

- `docs/NEW_POSTS_AUDIT.md`
- `docs/refactor_cleanup.md`
- `lib/main.dart`
- `lib/widgets/home/dashboard_components.dart`
- `lib/widgets/home/dashboard_sections.dart`
- `linux/flutter/generated_plugin_registrant.cc`
- `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `pubspec.lock`
- `pubspec.yaml`
- `web/index.html`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugins.cmake`

## Removed transitive dependencies

device_info_plus, device_info_plus_platform_interface, ffi_leak_tracker, fixnum, petitparser, syncfusion_flutter_core, syncfusion_flutter_pdf, syncfusion_flutter_signaturepad, syncfusion_pdfviewer_linux, syncfusion_pdfviewer_macos, syncfusion_pdfviewer_platform_interface, syncfusion_pdfviewer_web, syncfusion_pdfviewer_windows, uuid, win32, win32_registry, xml.

## Additional browser validation

The Chrome run of post_discovery_test.dart and dashboard_refresh_web_test.dart stalled while loading and was interrupted. Browser interaction checks remain unverified. The required VM test suite and web production build passed. Bidding Documents, Done, thumbs-up/down, copy, and View PhilGEPS retain their existing code; this change only removes the preceding editor action. Live notification delivery was not tested. git diff --check passed.

