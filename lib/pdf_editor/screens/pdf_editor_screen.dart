import '../models/item_pricing.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/pdf_service.dart';
import '../../utils/supabase_client.dart';

part 'pdf_editor/editor_persistence.dart';
part 'pdf_editor/specification_editing.dart';
part 'pdf_editor/editor_preview.dart';
part '../widgets/sidebar/editor_fields.dart';
part '../widgets/sidebar/sidebar_design.dart';
part '../widgets/sidebar/sidebar_panel.dart';
part '../widgets/sidebar/omnibus_section.dart';
part '../widgets/sidebar/document_template_section.dart';
part '../widgets/sidebar/slcc_section.dart';
part '../widgets/sidebar/bid_security_section.dart';
part '../widgets/sidebar/technical_specs_section.dart';
part '../widgets/sidebar/price_schedule_section.dart';
part '../widgets/sidebar/schedule_requirements_section.dart';
part '../widgets/sidebar/certificate_sections.dart';
part '../widgets/editor_controls.dart';
part '../models/editor_entries.dart';
part '../formatters/editor_input_formatters.dart';

class PdfEditorScreen extends StatefulWidget {
  final String province;
  final String municipality;
  final String projectTitle;
  final String referenceNumber;
  final String date;
  final String bidderName;
  final String procuringEntity;
  final String deliveryPeriod;

  const PdfEditorScreen({
    super.key,
    required this.province,
    required this.municipality,
    required this.projectTitle,
    required this.referenceNumber,
    required this.date,
    required this.bidderName,
    required this.procuringEntity,
    required this.deliveryPeriod,
  });

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final sidebarScrollController = ScrollController();
  static const String specificationLineSeparator = '\u2029';
  static const List<String> submittedByNames = [
    'JHO ANN Q. CLEOPAS',
    'CARLOS RAFAEL A. JAMILO',
    'MARLJONE BLAIRE B. TINGTING',
  ];
  static const Map<String, ({String name, String civilStatus, String address})>
      submittedByProfiles = {
    'JHO ANN Q. CLEOPAS': (
      name: 'Jho Ann Q. Cleopas',
      civilStatus: 'married',
      address: 'Tankulan, Manolo Fortich, Bukidnon',
    ),
    'CARLOS RAFAEL A. JAMILO': (
      name: 'Carlos Rafael A. Jamilo',
      civilStatus: 'single',
      address: 'Camaman-an, Cagayan de Oro City, Misamis Oriental',
    ),
    'MARLJONE BLAIRE B. TINGTING': (
      name: 'Marljone Blaire B. Tingting',
      civilStatus: 'single',
      address: 'Tankulan, Manolo Fortich, Bukidnon',
    ),
  };
  static const List<String> defaultUnitSuggestions = [
    'pcs',
    'pc',
    'pack',
    'box',
    'box/pack',
    'set',
    'lot',
    'unit',
    'bag',
    'bags',
    'kg',
    'g',
    'mg',
    'ton',
    'lb',
    'mm',
    'cm',
    'm',
    'km',
    'm2',
    'm²',
    'sq.m',
    'm3',
    'm³',
    'cu.m',
    'lm',
    'l',
    'ml',
    'gal',
    'sheet',
    'roll',
    'pair',
    'bd.ft',
  ];

  late final TextEditingController provinceController;
  late final TextEditingController municipalityController;
  late final TextEditingController projectTitleController;
  late final TextEditingController referenceNumberController;
  late final TextEditingController dateController;
  late final TextEditingController bidderNameController;
  late final TextEditingController procuringEntityController;
  late final TextEditingController submittedByController;
  String selectedDocumentTemplate = 'old';
  late final Future<void> documentTemplateLoaded;
  bool isLoadingDocumentTemplate = true;
  bool isSavingDocumentTemplate = false;
  int documentTemplateRevision = 0;
  Future<void> documentTemplateSave = Future<void>.value();
  String? documentTemplateSaveError;
  bool get isInitaoDocument => selectedDocumentTemplate == 'initao';
  String get effectiveOmnibusTemplate =>
      isInitaoDocument ? 'initao_lgu' : 'old';
  String get effectiveBidSecurityTemplate => isInitaoDocument
      ? 'initao_lgu'
      : selectedBidSecurityTemplate == 'without_table'
          ? 'without_table'
          : 'old';
  String selectedSlccTemplate = 'cctv';
  String selectedOmnibusTemplate = 'old';
  late final Future<void> omnibusLoaded;
  bool isLoadingOmnibus = true;
  bool isSavingOmnibus = false;
  int omnibusSelectionRevision = 0;
  Future<void> omnibusSave = Future<void>.value();
  String? omnibusSaveError;
  late final TextEditingController deliveredWeeksMonthsController;
  late final TextEditingController afterSalesYearsController;
  late final TextEditingController warrantyYearsController;
  final List<_TechnicalSpecificationEntry> technicalSpecifications = [];
  final List<_PriceScheduleEntry> priceScheduleEntries = [];
  late final FocusNode submittedByFocusNode;
  Timer? slccSaveTimer;
  Timer? technicalSpecificationsSaveTimer;
  Timer? priceScheduleSaveTimer;
  Timer? scheduleRequirementsSaveTimer;
  Timer? afterSalesSaveTimer;
  bool isLoadingSlcc = true;
  bool isSavingSlcc = false;
  bool isLoadingTechnicalSpecifications = true;
  bool isSavingTechnicalSpecifications = false;
  bool isLoadingPriceSchedule = true;
  bool isSavingPriceSchedule = false;
  bool isLoadingScheduleRequirements = true;
  bool isSavingScheduleRequirements = false;
  bool hasPendingDeliveryPeriodOverride = false;
  bool includeTotalInScheduleRequirements = false;
  String selectedBidSecurityTemplate = 'old';
  late final Future<void> bidSecurityLoaded;
  bool isLoadingBidSecurity = true;
  bool isSavingBidSecurity = false;
  int bidSecuritySelectionRevision = 0;
  Future<void> bidSecuritySave = Future<void>.value();
  String? bidSecuritySaveError;
  bool isLoadingAfterSales = true;
  bool isSavingAfterSales = false;
  List<String> unitSuggestions = List.of(defaultUnitSuggestions);

  Uint8List? generatedPdf;
  String? generatedPdfFileName;
  String? previewBlobUrl;
  int contentRevision = 0;
  String? lastObservedContentSignature;
  final Map<TextEditingController, String> metadataTextSnapshots = {};
  bool isGenerating = false;
  String? errorMessage;
  String? previewViewType;
  bool showCompactPreview = false;

  // Extensions delegate updates here to keep State.setState inside State.
  void _updateState(VoidCallback update) => setState(update);

  @override
  void initState() {
    super.initState();

    provinceController = TextEditingController(
      text: widget.province,
    );

    municipalityController = TextEditingController(
      text: widget.municipality,
    );

    projectTitleController = TextEditingController(
      text: widget.projectTitle,
    );

    referenceNumberController = TextEditingController(
      text: widget.referenceNumber,
    );

    dateController = TextEditingController(
      text: widget.date,
    );

    bidderNameController = TextEditingController(
      text: widget.bidderName,
    );

    procuringEntityController = TextEditingController(
      text: widget.procuringEntity,
    );

    submittedByController = TextEditingController(
      text: submittedByNames.first,
    );
    submittedByFocusNode = FocusNode();

    selectedSlccTemplate = widget.projectTitle.toUpperCase().contains('STREET')
        ? 'streetlight'
        : 'cctv';
    deliveredWeeksMonthsController = TextEditingController(
      text: widget.deliveryPeriod.trim(),
    );
    deliveredWeeksMonthsController.addListener(_scheduleRequirementsSave);
    afterSalesYearsController = TextEditingController(text: '1');
    afterSalesYearsController.addListener(_scheduleAfterSalesSave);
    warrantyYearsController = TextEditingController(text: '2');
    warrantyYearsController.addListener(_scheduleAfterSalesSave);
    for (final controller in <TextEditingController>[
      provinceController,
      municipalityController,
      projectTitleController,
      referenceNumberController,
      dateController,
      bidderNameController,
      procuringEntityController,
      submittedByController,
    ]) {
      metadataTextSnapshots[controller] = controller.text;
      controller.addListener(_handleMetadataTextChanged);
    }
    documentTemplateLoaded = _loadDocumentTemplate();
    bidSecurityLoaded = _loadBidSecurity();
    omnibusLoaded = _loadOmnibus();
    _loadSlcc();
    _loadTechnicalSpecifications();
    _loadUnitSuggestions();
    _loadPhilgepsDeliveryPeriod();
    _loadAfterSalesSettings();
  }

  @override
  void dispose() {
    sidebarScrollController.dispose();
    for (final controller in <TextEditingController>[
      provinceController,
      municipalityController,
      projectTitleController,
      referenceNumberController,
      dateController,
      bidderNameController,
      procuringEntityController,
      submittedByController,
    ]) {
      controller.removeListener(_handleMetadataTextChanged);
    }
    metadataTextSnapshots.clear();
    final oldBlobUrl = previewBlobUrl;
    if (oldBlobUrl != null) html.Url.revokeObjectUrl(oldBlobUrl);
    provinceController.dispose();
    municipalityController.dispose();
    projectTitleController.dispose();
    referenceNumberController.dispose();
    procuringEntityController.dispose();
    dateController.dispose();
    bidderNameController.dispose();
    submittedByController.dispose();
    submittedByFocusNode.dispose();
    slccSaveTimer?.cancel();
    technicalSpecificationsSaveTimer?.cancel();
    priceScheduleSaveTimer?.cancel();
    scheduleRequirementsSaveTimer?.cancel();
    afterSalesSaveTimer?.cancel();
    deliveredWeeksMonthsController.removeListener(_scheduleRequirementsSave);
    deliveredWeeksMonthsController.dispose();
    afterSalesYearsController.removeListener(_scheduleAfterSalesSave);
    afterSalesYearsController.dispose();
    warrantyYearsController.removeListener(_scheduleAfterSalesSave);
    warrantyYearsController.dispose();
    for (final entry in technicalSpecifications) {
      for (final controller in entry.controllers) {
        controller.removeListener(_scheduleTechnicalSpecificationsSave);
      }
      entry.dispose();
    }
    for (final entry in priceScheduleEntries) {
      entry.totalPricePerUnit.removeListener(_schedulePriceScheduleSave);
      entry.deduction.removeListener(_schedulePriceScheduleSave);
      entry.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bid Docs PDF Editor'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1000;
                final isMobileOrTabletWeb = kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.android ||
                        defaultTargetPlatform == TargetPlatform.iOS);
                final useDesktopBrowserPdfViewer =
                    isWide && !isMobileOrTabletWeb;
                final formPanel = buildSidebar(isWide);

                final previewPanel = Container(
                  color: const Color(0xFFF2F2F2),
                  child: generatedPdf == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 54,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Fill up the form, then click Generate PDF.',
                              ),
                            ],
                          ),
                        )
                      : useDesktopBrowserPdfViewer && previewViewType != null
                          ? HtmlElementView(
                              key: ValueKey(previewViewType),
                              viewType: previewViewType!,
                            )
                          : SfPdfViewer.memory(
                              generatedPdf!,
                              key: ValueKey(generatedPdf),
                              canShowScrollHead: true,
                              canShowScrollStatus: true,
                              initialZoomLevel: 1,
                              maxZoomLevel: 3,
                            ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      formPanel,
                      const VerticalDivider(width: 1),
                      Expanded(child: previewPanel),
                    ],
                  );
                }

                final compactSwitcher = Material(
                  color: Colors.white,
                  elevation: 1,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _CompactPanelButton(
                              icon: Icons.edit_document,
                              label: 'Form',
                              selected: !showCompactPreview,
                              onPressed: () =>
                                  setState(() => showCompactPreview = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CompactPanelButton(
                              icon: Icons.picture_as_pdf_outlined,
                              label: generatedPdf == null
                                  ? 'PDF Preview'
                                  : 'View PDF',
                              selected: showCompactPreview,
                              onPressed: () =>
                                  setState(() => showCompactPreview = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                return Column(
                  children: [
                    compactSwitcher,
                    const Divider(height: 1),
                    Expanded(
                      child: showCompactPreview ? previewPanel : formPanel,
                    ),
                  ],
                );
              },
            ),
          ),
          if (isGenerating)
            const Positioned.fill(
              child: _PdfGenerationOverlay(),
            ),
        ],
      ),
    );
  }
}
