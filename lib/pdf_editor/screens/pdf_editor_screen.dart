import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/pdf_service.dart';
import '../../utils/supabase_client.dart';

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
  static const String specificationLineSeparator = '\n\n';
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
  String selectedSlccTemplate = 'cctv';
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
  bool useBidSecuringDeclarationWithTable = true;
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
    _loadSlcc();
    _loadTechnicalSpecifications();
    _loadUnitSuggestions();
    _loadPhilgepsDeliveryPeriod();
    _loadAfterSalesSettings();
  }

  Future<void> _loadPhilgepsDeliveryPeriod() async {
    final referenceNumber = widget.referenceNumber.trim();
    if (referenceNumber.isEmpty) return;
    try {
      final row = await SupabaseConfig.client
          .from('philgeps_posts')
          .select('delivery_period')
          .eq('reference_number', referenceNumber)
          .maybeSingle();
      final deliveryPeriod = (row?['delivery_period'] ?? '').toString().trim();
      if (deliveryPeriod.isNotEmpty) {
        if (!mounted) return;
        setState(() => deliveredWeeksMonthsController.text = deliveryPeriod);
      } else {
        await _refreshPhilgepsDeliveryPeriod(referenceNumber);
      }
    } catch (error) {
      debugPrint('PhilGEPS delivery period load error: $error');
      await _refreshPhilgepsDeliveryPeriod(referenceNumber);
    } finally {
      await _loadManualDeliveryOverride(referenceNumber);
    }
  }

  Future<void> _loadManualDeliveryOverride(String referenceNumber) async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_schedule_requirements')
          // Keep this compatible with deployments created before the optional
          // is_manual_override migration was applied.
          .select('delivery_weeks_months')
          .eq('reference_number', referenceNumber)
          .maybeSingle();
      final saved = (row?['delivery_weeks_months'] ?? '').toString().trim();
      if (mounted && saved.isNotEmpty) {
        setState(() => deliveredWeeksMonthsController.text = saved);
      }
    } catch (error) {
      debugPrint('Delivery Period override load error: $error');
    } finally {
      isLoadingScheduleRequirements = false;
      if (mounted) setState(() {});
    }
  }

  void _scheduleRequirementsSave() {
    if (isLoadingScheduleRequirements) return;
    _invalidateGeneratedPdf();
    hasPendingDeliveryPeriodOverride = true;
    scheduleRequirementsSaveTimer?.cancel();
    scheduleRequirementsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveScheduleRequirements,
    );
  }

  Future<void> _saveScheduleRequirements() async {
    final referenceNumber = widget.referenceNumber.trim();
    if (referenceNumber.isEmpty) return;
    if (mounted) setState(() => isSavingScheduleRequirements = true);
    try {
      await SupabaseConfig.client.from('bid_schedule_requirements').upsert(
        {
          'reference_number': referenceNumber,
          'delivery_weeks_months': deliveredWeeksMonthsController.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
      hasPendingDeliveryPeriodOverride = false;
    } catch (error) {
      debugPrint('Delivery Period override save error: $error');
    } finally {
      if (mounted) setState(() => isSavingScheduleRequirements = false);
    }
  }

  Future<void> _refreshPhilgepsDeliveryPeriod(String referenceNumber) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://philgepsnotifalert-production.up.railway.app/'
              'refresh-delivery-period',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'referenceNumber': referenceNumber}),
          )
          .timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        debugPrint('Delivery Period refresh failed: ${response.body}');
        return;
      }
      final decoded = jsonDecode(response.body);
      final deliveryPeriod = decoded is Map
          ? (decoded['deliveryPeriod'] ?? '').toString().trim()
          : '';
      if (!mounted || deliveryPeriod.isEmpty) return;
      setState(() => deliveredWeeksMonthsController.text = deliveryPeriod);
    } catch (error) {
      debugPrint('Delivery Period refresh request error: $error');
    }
  }

  Future<void> _loadAfterSalesSettings() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_after_sales_settings')
          .select('service_years, warranty_years')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      afterSalesYearsController.text = (row?['service_years'] ?? 1).toString();
      warrantyYearsController.text = (row?['warranty_years'] ?? 2).toString();
    } catch (error) {
      debugPrint('After-sales settings load error: $error');
    } finally {
      if (mounted) setState(() => isLoadingAfterSales = false);
    }
  }

  void _scheduleAfterSalesSave() {
    if (isLoadingAfterSales) return;
    _invalidateGeneratedPdf();
    afterSalesSaveTimer?.cancel();
    afterSalesSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveAfterSalesSettings,
    );
  }

  Future<void> _saveAfterSalesSettings() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    final years = int.tryParse(afterSalesYearsController.text.trim());
    final warrantyYears = int.tryParse(warrantyYearsController.text.trim());
    if (years == null ||
        years < 1 ||
        warrantyYears == null ||
        warrantyYears < 1) {
      return;
    }
    if (mounted) setState(() => isSavingAfterSales = true);
    try {
      await SupabaseConfig.client.from('bid_after_sales_settings').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'service_years': years,
          'warranty_years': warrantyYears,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('After-sales settings save error: $error');
    } finally {
      if (mounted) setState(() => isSavingAfterSales = false);
    }
  }

  Future<void> _loadUnitSuggestions() async {
    try {
      final rows = await SupabaseConfig.client
          .from('technical_specification_units')
          .select('code')
          .order('sort_order');
      final loaded = rows
          .map((row) => (row['code'] ?? '').toString().trim())
          .where((unit) => unit.isNotEmpty)
          .toList();
      if (loaded.isNotEmpty && mounted) {
        setState(() => unitSuggestions = loaded);
      }
    } catch (error) {
      debugPrint('Unit suggestions load error: $error');
    }
  }

  void _addTechnicalSpecification({
    String specification = '',
    String quantity = '1',
    String unit = 'unit',
    String parameter = '',
    bool rebuild = true,
  }) {
    if (technicalSpecifications.length >= 72) return;
    final entry = _TechnicalSpecificationEntry(
      specification: specification,
      quantity: quantity,
      unit: unit,
      parameter: parameter,
    );
    for (final controller in entry.controllers) {
      controller.addListener(_scheduleTechnicalSpecificationsSave);
    }
    technicalSpecifications.add(entry);
    final priceEntry = _PriceScheduleEntry();
    priceEntry.totalPricePerUnit.addListener(_schedulePriceScheduleSave);
    priceEntry.deduction.addListener(_schedulePriceScheduleSave);
    priceScheduleEntries.add(priceEntry);
    if (rebuild && mounted) setState(() {});
  }

  void _removeTechnicalSpecification(int index) {
    final entry = technicalSpecifications.removeAt(index);
    for (final controller in entry.controllers) {
      controller.removeListener(_scheduleTechnicalSpecificationsSave);
    }
    entry.dispose();
    final priceEntry = priceScheduleEntries.removeAt(index);
    priceEntry.totalPricePerUnit.removeListener(_schedulePriceScheduleSave);
    priceEntry.deduction.removeListener(_schedulePriceScheduleSave);
    priceEntry.dispose();
    setState(() {});
    _scheduleTechnicalSpecificationsSave();
  }

  void _addTechnicalSpecificationParameter(int index) {
    setState(() => technicalSpecifications[index].hasParameter = true);
  }

  void _removeTechnicalSpecificationParameter(int index) {
    final entry = technicalSpecifications[index];
    entry.parameter.clear();
    setState(() => entry.hasParameter = false);
    _scheduleTechnicalSpecificationsSave();
  }

  void _applySpecificationMarker(
    _TechnicalSpecificationEntry entry,
    String marker,
  ) {
    final controller = entry.specification;
    final text = controller.text;
    final caret = controller.selection.isValid
        ? controller.selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
    final lineEndIndex = text.indexOf('\n', caret);
    final lineEnd = lineEndIndex < 0 ? text.length : lineEndIndex;
    final line = text.substring(lineStart, lineEnd);
    final markerMatch =
        _SpecificationListFormatter.markerPattern.firstMatch(line);
    final content =
        markerMatch == null ? line : line.substring(markerMatch.end);
    final replacement = marker.isEmpty ? content : '$marker $content';
    controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection.collapsed(
        offset: lineStart + replacement.length,
      ),
    );
  }

  void _removeSpecificationLine(
    _TechnicalSpecificationEntry entry,
    int lineIndex,
  ) {
    final lines = entry.specification.text
        .replaceAll('\u2029', specificationLineSeparator)
        .split(specificationLineSeparator);
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines.removeAt(lineIndex);
    entry.specification.text = lines.join(specificationLineSeparator);
    entry.specification.selection = TextSelection.collapsed(
      offset: entry.specification.text.length,
    );
  }

  Future<void> _loadTechnicalSpecifications() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_technical_specifications')
          .select('specifications')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      final savedSpecifications = row?['specifications'];
      if (savedSpecifications is List) {
        for (final value in savedSpecifications.take(72)) {
          if (value is Map) {
            _addTechnicalSpecification(
              specification: (value['specification'] ?? '').toString(),
              quantity: (value['quantity'] ?? '').toString().trim().isEmpty
                  ? '1'
                  : value['quantity'].toString(),
              unit: (value['unit'] ?? '').toString().trim().isEmpty
                  ? 'unit'
                  : value['unit'].toString(),
              parameter: (value['parameter'] ?? '').toString(),
              rebuild: false,
            );
          }
        }
      }
    } catch (error) {
      debugPrint('Technical specifications load error: $error');
    } finally {
      if (mounted) {
        setState(() => isLoadingTechnicalSpecifications = false);
      }
      await _loadPriceSchedule();
    }
  }

  Future<void> _loadPriceSchedule() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_price_schedules')
          .select('total_prices_per_unit')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      final savedPrices = row?['total_prices_per_unit'];
      if (savedPrices is List) {
        for (var index = 0;
            index < savedPrices.length && index < priceScheduleEntries.length;
            index++) {
          final value = savedPrices[index];
          final savedValue = value is Map
              ? (value['totalPricePerUnit'] ?? '').toString()
              : value.toString();
          priceScheduleEntries[index].totalPricePerUnit.text =
              const _ThousandsSeparatorInputFormatter()
                  .formatEditUpdate(
                    const TextEditingValue(),
                    TextEditingValue(text: savedValue),
                  )
                  .text;
          final deduction =
              value is Map ? (value['deduction'] ?? '').toString() : '';
          priceScheduleEntries[index].deduction.text =
              const _ThousandsSeparatorInputFormatter()
                  .formatEditUpdate(
                    const TextEditingValue(),
                    TextEditingValue(text: deduction),
                  )
                  .text;
        }
      }
    } catch (error) {
      debugPrint('Price schedule load error: $error');
    } finally {
      if (mounted) setState(() => isLoadingPriceSchedule = false);
    }
  }

  void _schedulePriceScheduleSave() {
    if (isLoadingPriceSchedule) return;
    _invalidateGeneratedPdf();
    priceScheduleSaveTimer?.cancel();
    priceScheduleSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _savePriceSchedule,
    );
    if (mounted) setState(() {});
  }

  Future<void> _savePriceSchedule() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) setState(() => isSavingPriceSchedule = true);
    try {
      await SupabaseConfig.client.from('bid_price_schedules').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'total_prices_per_unit': [
            for (final entry in priceScheduleEntries)
              {
                'totalPricePerUnit': entry.totalPricePerUnit.text.trim(),
                'deduction': entry.deduction.text.trim(),
              },
          ],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('Price schedule save error: $error');
    } finally {
      if (mounted) setState(() => isSavingPriceSchedule = false);
    }
  }

  void _scheduleTechnicalSpecificationsSave() {
    if (isLoadingTechnicalSpecifications) return;
    _invalidateGeneratedPdf();
    technicalSpecificationsSaveTimer?.cancel();
    technicalSpecificationsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveTechnicalSpecifications,
    );
    if (mounted) setState(() {});
  }

  Future<void> _saveTechnicalSpecifications() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) setState(() => isSavingTechnicalSpecifications = true);
    try {
      final specifications = [
        for (final entry in technicalSpecifications)
          {
            'specification': entry.specification.text.trim(),
            'quantity': entry.quantity.text.trim(),
            'unit': entry.unit.text.trim(),
            'parameter': entry.parameter.text.trim(),
          },
      ];
      await SupabaseConfig.client.from('bid_technical_specifications').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'specifications': specifications,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('Technical specifications save error: $error');
    } finally {
      if (mounted) setState(() => isSavingTechnicalSpecifications = false);
    }
  }

  Future<void> _loadSlcc() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_slcc_entries')
          .select('template_type')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      if (row != null) {
        final savedTemplate = (row['template_type'] ?? '').toString();
      if (savedTemplate == 'none' ||
          savedTemplate == 'cctv' ||
          savedTemplate == 'streetlight') {
        selectedSlccTemplate = savedTemplate;
      }
      }
    } catch (error) {
      debugPrint('SLCC load error: $error');
    } finally {
      if (mounted) setState(() => isLoadingSlcc = false);
    }
  }

  void _scheduleSlccSave() {
    if (isLoadingSlcc) return;
    slccSaveTimer?.cancel();
    slccSaveTimer = Timer(const Duration(milliseconds: 700), _saveSlcc);
  }

  Future<void> _saveSlcc() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) setState(() => isSavingSlcc = true);
    try {
      final data = <String, dynamic>{
        'reference_number': widget.referenceNumber.trim(),
        'template_type': selectedSlccTemplate,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await SupabaseConfig.client.from('bid_slcc_entries').upsert(
            data,
            onConflict: 'reference_number',
          );
    } catch (error) {
      debugPrint('SLCC save error: $error');
    } finally {
      if (mounted) setState(() => isSavingSlcc = false);
    }
  }

  Future<Uint8List> _renderCompatiblePdf(Uint8List source) async {
    final response = await http
        .post(
          Uri.parse(
            'https://philgepsnotifalert-production.up.railway.app/'
            'render-compatible-pdf',
          ),
          headers: const {'Content-Type': 'application/pdf'},
          body: source,
        )
        .timeout(const Duration(minutes: 8));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception(
        'Compatible PDF rendering failed (${response.statusCode}). '
        'Deploy the latest Railway backend and try again.',
      );
    }
    return response.bodyBytes;
  }

  Future<void> generatePdf() async {
    setState(() {
      isGenerating = true;
      errorMessage = null;
    });

    try {
      final submittedBy = submittedByController.text.trim();
      final submittedByProfile = submittedByProfiles[submittedBy.toUpperCase()];
      // Give the browser a frame to paint the loading overlay before the
      // CPU-heavy PDF work starts.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      slccSaveTimer?.cancel();
      technicalSpecificationsSaveTimer?.cancel();
      priceScheduleSaveTimer?.cancel();
      scheduleRequirementsSaveTimer?.cancel();
      afterSalesSaveTimer?.cancel();
      await _saveSlcc();
      await _saveTechnicalSpecifications();
      await _savePriceSchedule();
      if (hasPendingDeliveryPeriodOverride) {
        await _saveScheduleRequirements();
      }
      await _saveAfterSalesSettings();
      final generatedProjectTitle = projectTitleController.text.trim();
      final generatedReferenceNumber = referenceNumberController.text.trim();
      lastObservedContentSignature = _currentContentSignature();
      final generatedRevision = contentRevision;
      final rawBytes = await PdfService.generateBidDocs(
        values: {
          'province': provinceController.text.trim(),
          'municipality': municipalityController.text.trim(),
          'projectTitle': generatedProjectTitle,
          'referenceNumber': generatedReferenceNumber,
          'date': dateController.text.trim(),
          'bidderName': bidderNameController.text.trim(),
          'procuringEntity': procuringEntityController.text.trim(),
          'submittedBy': submittedBy,
          'submittedByFormalName': submittedByProfile?.name ?? submittedBy,
          'submittedByCivilStatus': submittedByProfile?.civilStatus ?? '',
          'submittedByAddress': submittedByProfile?.address ?? '',
          'slccTemplateType': selectedSlccTemplate,
          'technicalSpecifications': jsonEncode([
            for (final entry in technicalSpecifications)
              {
                'specification': entry.specification.text.trim(),
                'quantity': entry.quantity.text.trim(),
                'unit': entry.unit.text.trim(),
                'parameter': entry.parameter.text.trim(),
              },
          ]),
          'priceSchedule': jsonEncode([
            for (final entry in priceScheduleEntries)
              {
                'totalPricePerUnit': entry.totalPricePerUnit.text.trim(),
                'deduction': entry.deduction.text.trim(),
              },
          ]),
          'deliveredWeeksMonths': deliveredWeeksMonthsController.text.trim(),
          'includeScheduleTotal':
              includeTotalInScheduleRequirements ? 'true' : 'false',
          'afterSalesYears': afterSalesYearsController.text.trim(),
          'warrantyYears': warrantyYearsController.text.trim(),
          'bidSecuringDeclarationWithTable':
              useBidSecuringDeclarationWithTable ? 'true' : 'false',
        },
      );

      final bytes = await _renderCompatiblePdf(rawBytes);
      if (!mounted) return;
      if (generatedRevision != contentRevision) {
        setState(() {
          errorMessage =
              'The form changed while the PDF was being generated. Click Generate PDF again to download the latest data.';
        });
        return;
      }

      final fileName = _buildGeneratedPdfFileName(
        generatedProjectTitle,
        generatedReferenceNumber,
        DateTime.now(),
      );

      // Keep the original browser PDF viewer on desktop/laptop, where its
      // built-in download and print toolbar already works well.
      final previousBlobUrl = previewBlobUrl;
      final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      final viewType = 'generated-pdf-${DateTime.now().microsecondsSinceEpoch}';
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int viewId) => html.IFrameElement()
          ..src = blobUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true,
      );

      setState(() {
        generatedPdf = bytes;
        generatedPdfFileName = fileName;
        previewBlobUrl = blobUrl;
        previewViewType = viewType;
        showCompactPreview = true;
      });

      if (previousBlobUrl != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          html.Url.revokeObjectUrl(previousBlobUrl);
        });
      }
    } catch (error, stackTrace) {
      if (!mounted) return;

      // Include the first useful stack frame while diagnosing PDF font/data
      // failures. The exception text alone only reports a character code and
      // does not reveal which PDF section attempted to draw it.
      final allStackLines = stackTrace
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final appStackLines = allStackLines
          .where((line) =>
              line.contains('pdf_service.dart') ||
              line.contains('pdf_editor_screen.dart'))
          .take(4)
          .toList();
      final stackLines = (appStackLines.isNotEmpty
              ? appStackLines
              : allStackLines.take(6))
          .join('\n');

      setState(() {
        errorMessage = '$error\n$stackLines';
      });
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  String _buildGeneratedPdfFileName(
    String projectTitle,
    String referenceNumber,
    DateTime generatedAt,
  ) {
    String safePart(String value, int maximumLength) {
      final sanitized = value
          .replaceAll(RegExp(r'[^A-Za-z0-9 _()-]+'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      return sanitized.length <= maximumLength
          ? sanitized
          : sanitized.substring(0, maximumLength);
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final safeTitle = safePart(projectTitle, 80);
    final safeReference = safePart(referenceNumber, 40);
    final stamp = '${generatedAt.year}'
        '${twoDigits(generatedAt.month)}${twoDigits(generatedAt.day)}-'
        '${twoDigits(generatedAt.hour)}${twoDigits(generatedAt.minute)}'
        '${twoDigits(generatedAt.second)}';
    final identity = <String>[
      if (safeTitle.isNotEmpty) safeTitle,
      if (safeReference.isNotEmpty) safeReference,
      stamp,
    ].join('-');
    return '${identity.isEmpty ? 'bid-documents-$stamp' : identity}.pdf';
  }

  void _invalidateGeneratedPdf() {
    final currentSignature = _currentContentSignature();
    if (currentSignature == lastObservedContentSignature) return;
    lastObservedContentSignature = currentSignature;
    contentRevision++;
    if (generatedPdf == null || isGenerating || !mounted) return;
    final oldBlobUrl = previewBlobUrl;
    setState(() {
      generatedPdf = null;
      generatedPdfFileName = null;
      previewBlobUrl = null;
      previewViewType = null;
      showCompactPreview = false;
    });
    if (oldBlobUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        html.Url.revokeObjectUrl(oldBlobUrl);
      });
    }
  }

  String _currentContentSignature() {
    return jsonEncode({
      'province': provinceController.text,
      'municipality': municipalityController.text,
      'projectTitle': projectTitleController.text,
      'referenceNumber': referenceNumberController.text,
      'date': dateController.text,
      'bidderName': bidderNameController.text,
      'procuringEntity': procuringEntityController.text,
      'submittedBy': submittedByController.text,
      'slccTemplate': selectedSlccTemplate,
      'bidDeclarationWithTable': useBidSecuringDeclarationWithTable,
      'includeScheduleTotal': includeTotalInScheduleRequirements,
      'deliveryPeriod': deliveredWeeksMonthsController.text,
      'afterSalesYears': afterSalesYearsController.text,
      'warrantyYears': warrantyYearsController.text,
      'technicalSpecifications': [
        for (final entry in technicalSpecifications)
          [
            entry.specification.text,
            entry.quantity.text,
            entry.unit.text,
            entry.parameter.text,
          ],
      ],
      'priceSchedule': [
        for (final entry in priceScheduleEntries)
          [entry.totalPricePerUnit.text, entry.deduction.text],
      ],
    });
  }

  void _handleMetadataTextChanged() {
    var textChanged = false;
    for (final entry in metadataTextSnapshots.entries) {
      final currentText = entry.key.text;
      if (entry.value != currentText) {
        metadataTextSnapshots[entry.key] = currentText;
        textChanged = true;
      }
    }
    // TextEditingController listeners also fire for cursor movement and text
    // selection. Keep the generated PDF visible unless actual text changed.
    if (textChanged) _invalidateGeneratedPdf();
  }

  Future<void> _downloadGeneratedPdf() async {
    // Never reuse the bytes currently displayed in the preview. They may have
    // been produced by an older running build even when the form values have
    // not changed. Rebuild first so "Download Latest PDF" always means the
    // current generator and current editor data.
    await generatePdf();
    if (!mounted || isGenerating || errorMessage != null) return;
    final bytes = generatedPdf;
    if (bytes == null) return;
    final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = generatedPdfFileName ?? 'bid-documents.pdf'
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Timer(const Duration(seconds: 10), () => html.Url.revokeObjectUrl(url));
  }

  void _printGeneratedPdf() {
    final bytes = generatedPdf;
    if (bytes == null) return;

    final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    // Opening the PDF in a user-initiated tab works with mobile/tablet popup
    // rules and gives those browsers their native print/share destination UI.
    final printWindow = html.window.open(url, '_blank');
    if (printWindow.closed == true) {
      html.Url.revokeObjectUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please allow pop-ups to print the PDF.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Use Print or Share from the opened PDF menu.'),
      ),
    );
    Timer(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
  }

  Widget formField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    bool readOnly = false,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        readOnly: readOnly,
        inputFormatters: inputFormatters,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: readOnly ? const Color(0xFFF1F5F2) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF0B5D3B),
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget sectionHeading(IconData icon, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE4F1E9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: const Color(0xFF0B5D3B)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF153D2C),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .35,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7770),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget unitField(_TechnicalSpecificationEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<String>(
        textEditingController: entry.unit,
        focusNode: entry.unitFocusNode,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          final matches = unitSuggestions.where(
            (unit) => query.isEmpty || unit.toLowerCase().contains(query),
          );
          final sorted = matches.toList()
            ..sort((first, second) {
              final firstStarts = first.toLowerCase().startsWith(query);
              final secondStarts = second.toLowerCase().startsWith(query);
              if (firstStarts != secondStarts) return firstStarts ? -1 : 1;
              return first.compareTo(second);
            });
          return sorted;
        },
        onSelected: (unit) {
          entry.unit.text = unit;
          entry.unit.selection = TextSelection.collapsed(offset: unit.length);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Unit',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: PopupMenuButton<String>(
                tooltip: 'Select unit',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (unit) {
                  controller.text = unit;
                  controller.selection = TextSelection.collapsed(
                    offset: unit.length,
                  );
                },
                itemBuilder: (context) => [
                  for (final unit in unitSuggestions)
                    PopupMenuItem(value: unit, child: Text(unit)),
                ],
              ),
            ),
            onSubmitted: (_) => onSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240,
                  maxWidth: 260,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final unit = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(unit),
                      onTap: () => onSelected(unit),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget submittedByField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<String>(
        textEditingController: submittedByController,
        focusNode: submittedByFocusNode,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return submittedByNames;

          return submittedByNames.where(
            (name) => name.toLowerCase().contains(query),
          );
        },
        onSelected: (name) {
          submittedByController.text = name;
        },
        fieldViewBuilder: (
          context,
          controller,
          focusNode,
          onFieldSubmitted,
        ) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Submitted by',
              hintText: 'Type or select a name',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF0B5D3B),
                  width: 1.6,
                ),
              ),
              suffixIcon: const _SubmittedByMenuIcon(),
            ),
            onSubmitted: (_) => onFieldSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 328,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final name = options.elementAt(index);
                    return ListTile(
                      title: Text(name),
                      onTap: () => onSelected(name),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget slccFields() {
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(Icons.assignment_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'SLCC',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingSlcc
            ? 'Loading saved values...'
            : isSavingSlcc
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'none', label: Text('None')),
        ButtonSegment(value: 'cctv', label: Text('CCTV')),
              ButtonSegment(
                value: 'streetlight',
                label: Text('Street Lights'),
              ),
            ],
            selected: {selectedSlccTemplate},
            onSelectionChanged: (selection) {
              setState(() => selectedSlccTemplate = selection.first);
              _invalidateGeneratedPdf();
              _scheduleSlccSave();
            },
          ),
        ),
      ],
    );
  }

  Widget bidSecuringDeclarationFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(
        Icons.security_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'BID SECURING DECLARATION',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        useBidSecuringDeclarationWithTable ? 'With table' : 'Without table',
      ),
      children: [
        RadioListTile<bool>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('With table'),
          subtitle: const Text('Use the original declaration with table'),
          value: true,
          groupValue: useBidSecuringDeclarationWithTable,
          onChanged: (value) {
            if (value != null) {
              setState(() => useBidSecuringDeclarationWithTable = value);
              _invalidateGeneratedPdf();
            }
          },
        ),
        RadioListTile<bool>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Without table'),
          subtitle: const Text('Use the new declaration without table'),
          value: false,
          groupValue: useBidSecuringDeclarationWithTable,
          onChanged: (value) {
            if (value != null) {
              setState(() => useBidSecuringDeclarationWithTable = value);
              _invalidateGeneratedPdf();
            }
          },
        ),
      ],
    );
  }

  Widget technicalSpecificationsFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(Icons.fact_check_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'TECHNICAL SPECIFICATIONS',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingTechnicalSpecifications
            ? 'Loading saved values...'
            : isSavingTechnicalSpecifications
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        for (var index = 0; index < technicalSpecifications.length; index++)
          Card(
            elevation: 0,
            color: const Color(0xFFF7FAF8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFDCE5DF)),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 17,
                              color: Color(0xFF0B5D3B),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Item ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF234B38),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove specification',
                        onPressed: () => _removeTechnicalSpecification(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  formField(
                    label: 'Specification',
                    controller: technicalSpecifications[index].specification,
                    maxLines: 5,
                    inputFormatters: const <TextInputFormatter>[
                      _SpecificationListFormatter(),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final entry = technicalSpecifications[index];
                        final current = entry.specification.text;
                        entry.specification.text = current.trim().isEmpty
                            ? '✓ '
                            : '${current.trimRight()}$specificationLineSeparator✓ ';
                        entry.specification.selection = TextSelection.collapsed(
                          offset: entry.specification.text.length,
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add line'),
                    ),
                  ),
                  if (technicalSpecifications[index]
                      .specification
                      .text
                      .trim()
                      .isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDCE5DF)),
                      ),
                      child: Column(
                        children: [
                          for (final line in technicalSpecifications[index]
                              .specification
                              .text
                              .replaceAll(
                                '\u2029',
                                specificationLineSeparator,
                              )
                              .split(specificationLineSeparator)
                              .asMap()
                              .entries)
                            if (line.value.trim().isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Line ${line.key + 1}: ${line.value}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete this line',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => _removeSpecificationLine(
                                      technicalSpecifications[index],
                                      line.key,
                                    ),
                                  ),
                                ],
                              ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final option in const <(String, String)>[
                        ('', 'None'),
                        ('•', '•'),
                        ('○', '○'),
                        ('■', '■'),
                        ('➢', '➢'),
                        ('✓', '✓'),
                      ])
                        OutlinedButton(
                          onPressed: () => _applySpecificationMarker(
                            technicalSpecifications[index],
                            option.$1,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(38, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            foregroundColor: const Color(0xFF0B5D3B),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(option.$2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: formField(
                          label: 'Qty',
                          controller: technicalSpecifications[index].quantity,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: unitField(technicalSpecifications[index]),
                      ),
                    ],
                  ),
                  if (technicalSpecifications[index].hasParameter) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: formField(
                            label: 'Parameter',
                            controller:
                                technicalSpecifications[index].parameter,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Remove parameter',
                          onPressed: () =>
                              _removeTechnicalSpecificationParameter(index),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            _addTechnicalSpecificationParameter(index),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add parameter'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0B5D3B),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F2E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '✓  COMPLY',
                        style: TextStyle(
                          color: Color(0xFF0B5D3B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: technicalSpecifications.length >= 72
              ? null
              : _addTechnicalSpecification,
          icon: const Icon(Icons.add),
          label: Text(
            technicalSpecifications.length >= 72
                ? 'Maximum of 72 specifications'
                : 'Add Specification',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0B5D3B),
            side: const BorderSide(color: Color(0xFF0B5D3B)),
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  double _number(String value) {
    final normalized = value.replaceAll(',', '').trim();
    final direct = double.tryParse(normalized);
    if (direct != null) return direct;
    final match =
        RegExp(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)').firstMatch(normalized);
    return double.tryParse(match?.group(0) ?? '') ?? 0;
  }

  String _money(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  Widget priceScheduleFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(Icons.payments_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'PRICE SCHEDULE FOR GOODS',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingPriceSchedule
            ? 'Loading saved values...'
            : isSavingPriceSchedule
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        if (technicalSpecifications.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Add items under TECHNICAL SPECIFICATIONS first.'),
          ),
        for (var index = 0; index < technicalSpecifications.length; index++)
          Builder(builder: (context) {
            final specification = technicalSpecifications[index];
            final price = priceScheduleEntries[index];
            final enteredTotal = _number(price.totalPricePerUnit.text);
            final deduction = _number(price.deduction.text);
            final total =
                (enteredTotal - deduction).clamp(0, double.infinity).toDouble();
            final quantity = _number(specification.quantity.text);
            Widget priceRow(String label, String value) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFD7E3DC)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B5D3B),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ITEM ${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${specification.quantity.text} ${specification.unit.text}',
                          style: const TextStyle(
                            color: Color(0xFF526159),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      specification.specification.text.isEmpty
                          ? 'No specification entered'
                          : specification.specification.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: price.totalPricePerUnit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Price per Unit',
                        prefixText: '₱ ',
                        helperText: 'Enter the 100% unit price',
                        filled: true,
                        fillColor: const Color(0xFFF5FAF7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: price.deduction,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Deduction',
                        prefixText: '− ₱ ',
                        helperText: 'Optional amount deducted from unit price',
                        filled: true,
                        fillColor: const Color(0xFFFFF7F2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    priceRow('Adjusted Total Price per Unit', _money(total)),
                    priceRow('Unit Price/Item (50%)', _money(total * .50)),
                    priceRow(
                      'Transportation & Insurance (20%)',
                      _money(total * .20),
                    ),
                    priceRow(
                      'Sales & Other Taxes (30%)',
                      _money(total * .30),
                    ),
                    const Divider(height: 20),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4ED),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TOTAL DELIVERED PRICE',
                            style: TextStyle(
                              color: Color(0xFF38634D),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: .4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '₱ ${_money((quantity * total).roundToDouble())}',
                            style: const TextStyle(
                              color: Color(0xFF0B5D3B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget scheduleRequirementsFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(
        Icons.local_shipping_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'Schedule of Requirements',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingScheduleRequirements
            ? 'Loading from PhilGEPS...'
            : isSavingScheduleRequirements
                ? 'Saving manual correction...'
                : deliveredWeeksMonthsController.text.trim().isEmpty
                    ? 'No Delivery Period found in PhilGEPS'
                    : 'Auto-filled from PhilGEPS • Editable',
      ),
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: const Color(0xFF0B5D3B),
          value: includeTotalInScheduleRequirements,
          title: const Text(
            'Include Total column',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Merge Qty and Unit, then show Total Price Delivered Final Destination.',
            style: TextStyle(fontSize: 11.5),
          ),
          onChanged: (value) {
            setState(() {
              includeTotalInScheduleRequirements = value ?? false;
            });
            _invalidateGeneratedPdf();
          },
        ),
        formField(
          label: 'Delivery Period (PhilGEPS)',
          controller: deliveredWeeksMonthsController,
          maxLines: 2,
        ),
        const Text(
          'This delivery schedule applies to all Technical Specification items.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }

  Widget afterSalesServiceFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(
        Icons.handyman_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'AFTER-SALES SERVICE CERTIFICATE',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        isLoadingAfterSales
            ? 'Loading saved value...'
            : isSavingAfterSales
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        formField(
          label: 'Number of Years',
          controller: afterSalesYearsController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const Text(
          'Example: 3 becomes “three (3) years” in the PDF.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }

  Widget productWarrantyFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(
        Icons.verified_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'CERTIFICATE OF PRODUCT WARRANTY',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        isLoadingAfterSales
            ? 'Loading saved value...'
            : isSavingAfterSales
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        formField(
          label: 'Number of Years',
          controller: warrantyYearsController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const Text(
          'Example: 3 becomes “three (3) years” in the PDF.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }

  @override
  void dispose() {
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
                final compactHorizontalPadding =
                    constraints.maxWidth < 480 ? 10.0 : 16.0;

                final formPanel = Container(
                  width: isWide ? 380 : double.infinity,
                  color: const Color(0xFFF4F7F5),
                  padding: EdgeInsets.fromLTRB(
                    compactHorizontalPadding,
                    14,
                    compactHorizontalPadding,
                    18,
                  ),
                  child: ListView(
                    children: [
                      sectionHeading(
                        Icons.business_center_outlined,
                        'PROJECT INFORMATION',
                        subtitle: 'Bid and procuring entity details',
                      ),
                      formField(
                        label: 'Province',
                        controller: provinceController,
                      ),
                      formField(
                        label: 'Municipality',
                        controller: municipalityController,
                      ),
                      formField(
                        label: 'Project Title',
                        controller: projectTitleController,
                        maxLines: 3,
                      ),
                      formField(
                        label: 'Reference Number',
                        controller: referenceNumberController,
                      ),
                      formField(
                        label: 'Procuring Entity',
                        controller: procuringEntityController,
                        maxLines: 2,
                      ),
                      formField(
                        label: 'Date',
                        controller: dateController,
                      ),
                      formField(
                        label: 'Bidder Name',
                        controller: bidderNameController,
                      ),
                      submittedByField(),
                      const SizedBox(height: 4),
                      bidSecuringDeclarationFields(),
                      const SizedBox(height: 12),
                      slccFields(),
                      const SizedBox(height: 12),
                      technicalSpecificationsFields(),
                      const SizedBox(height: 12),
                      priceScheduleFields(),
                      const SizedBox(height: 12),
                      scheduleRequirementsFields(),
                      const SizedBox(height: 12),
                      afterSalesServiceFields(),
                      const SizedBox(height: 12),
                      productWarrantyFields(),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: isGenerating ? null : generatePdf,
                        icon: isGenerating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(
                          isGenerating ? 'Generating...' : 'Generate PDF',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B5D3B),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                );

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

class _CompactPanelButton extends StatelessWidget {
  const _CompactPanelButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF0B5D3B);
    return Material(
      color: selected ? const Color(0xFF0B5D3B) : const Color(0xFFEAF3EE),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfGenerationOverlay extends StatefulWidget {
  const _PdfGenerationOverlay();

  @override
  State<_PdfGenerationOverlay> createState() => _PdfGenerationOverlayState();
}

class _PdfGenerationOverlayState extends State<_PdfGenerationOverlay> {
  static const messages = <String>[
    'Saving your latest information...',
    'Preparing technical specifications...',
    'Calculating the price schedule...',
    'Building and arranging PDF pages...',
    'Finalizing your bid document...',
  ];

  Timer? messageTimer;
  int messageIndex = 0;

  @override
  void initState() {
    super.initState();
    messageTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) {
        setState(() => messageIndex = (messageIndex + 1) % messages.length);
      }
    });
  }

  @override
  void dispose() {
    messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.38),
      child: Center(
        child: Container(
          width: 360,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 82,
                      height: 82,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Color(0xFF0B5D3B),
                        backgroundColor: Color(0xFFE1EEE7),
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F4EC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 31,
                        color: Color(0xFF0B5D3B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Generating Bid Document',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF173D2C),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 22,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    messages[messageIndex],
                    key: ValueKey(messageIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF66736C),
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  color: Color(0xFF0B5D3B),
                  backgroundColor: Color(0xFFE2ECE6),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please keep this window open.',
                style: TextStyle(
                  color: Color(0xFF87918B),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmittedByMenuIcon extends StatelessWidget {
  const _SubmittedByMenuIcon();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_PdfEditorScreenState>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.arrow_drop_down),
      tooltip: 'Select submitted by',
      onSelected: (name) {
        state?.submittedByController.text = name;
        state?.submittedByController.selection = TextSelection.collapsed(
          offset: name.length,
        );
      },
      itemBuilder: (context) {
        return _PdfEditorScreenState.submittedByNames
            .map(
              (name) => PopupMenuItem<String>(
                value: name,
                child: Text(name),
              ),
            )
            .toList();
      },
    );
  }
}

class _SpecificationListFormatter extends TextInputFormatter {
  const _SpecificationListFormatter();

  static final RegExp markerPattern = RegExp(
    r'^\s*(?:✓|•|○|■|➢|-|\[x\])\s*',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.selection.isValid ||
        newValue.text.length != oldValue.text.length + 1) {
      return newValue;
    }
    final insertedAt = newValue.selection.baseOffset - 1;
    if (insertedAt < 0 || newValue.text[insertedAt] != '\n') return newValue;

    final previousLineStart =
        newValue.text.lastIndexOf('\n', insertedAt - 1) + 1;
    final previousLine = newValue.text.substring(previousLineStart, insertedAt);
    final match = markerPattern.firstMatch(previousLine);
    if (match == null) return newValue;

    final markerText = match.group(0)!.trim();
    final previousContent = previousLine.substring(match.end).trim();
    if (previousContent.isEmpty) {
      final cleaned = newValue.text.replaceRange(
        previousLineStart,
        insertedAt,
        '',
      );
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: previousLineStart + 1),
      );
    }

    final continuation = '$markerText ';
    final continuedText = newValue.text.replaceRange(
      insertedAt + 1,
      insertedAt + 1,
      continuation,
    );
    return TextEditingValue(
      text: continuedText,
      selection: TextSelection.collapsed(
        offset: insertedAt + 1 + continuation.length,
      ),
    );
  }
}

class _TechnicalSpecificationEntry {
  _TechnicalSpecificationEntry({
    String specification = '',
    String quantity = '',
    String unit = '',
    String parameter = '',
  })  : specification = TextEditingController(text: specification),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        parameter = TextEditingController(text: parameter),
        hasParameter = parameter.trim().isNotEmpty;

  final TextEditingController specification;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController parameter;
  bool hasParameter;
  final FocusNode unitFocusNode = FocusNode();

  List<TextEditingController> get controllers =>
      [specification, quantity, unit, parameter];

  void dispose() {
    specification.dispose();
    quantity.dispose();
    unit.dispose();
    parameter.dispose();
    unitFocusNode.dispose();
  }
}

class _PriceScheduleEntry {
  _PriceScheduleEntry({String totalPricePerUnit = '', String deduction = ''})
      : totalPricePerUnit = TextEditingController(text: totalPricePerUnit),
        deduction = TextEditingController(text: deduction);

  final TextEditingController totalPricePerUnit;
  final TextEditingController deduction;

  void dispose() {
    totalPricePerUnit.dispose();
    deduction.dispose();
  }
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const _ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(raw)) return oldValue;

    final parts = raw.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length == 2 ? '$grouped.${parts[1]}' : grouped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
