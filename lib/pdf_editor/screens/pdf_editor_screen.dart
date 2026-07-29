import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const PdfEditorScreen({
    super.key,
    required this.province,
    required this.municipality,
    required this.projectTitle,
    required this.referenceNumber,
    required this.date,
    required this.bidderName,
    required this.procuringEntity,
  });

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  static const List<String> submittedByNames = [
    'JHO ANN Q, CLEOPAS',
    'CARLOS RAFAEL A. JAMILO',
    'MARLJONE BLAIRE B. TINGTING',
  ];
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
  late final Map<String, TextEditingController> slccControllers;
  final List<_TechnicalSpecificationEntry> technicalSpecifications = [];
  final List<_PriceScheduleEntry> priceScheduleEntries = [];
  late final FocusNode submittedByFocusNode;
  Timer? slccSaveTimer;
  Timer? technicalSpecificationsSaveTimer;
  Timer? priceScheduleSaveTimer;
  bool isLoadingSlcc = true;
  bool isSavingSlcc = false;
  bool isLoadingTechnicalSpecifications = true;
  bool isSavingTechnicalSpecifications = false;
  bool isLoadingPriceSchedule = true;
  bool isSavingPriceSchedule = false;
  List<String> unitSuggestions = List.of(defaultUnitSuggestions);

  Uint8List? generatedPdf;
  bool isGenerating = false;
  String? errorMessage;

  String? previewViewType;
  String? previewBlobUrl;

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

    slccControllers = {
      'slccOwnerName': TextEditingController(),
      'slccAddressTelephone': TextEditingController(),
      'slccNumber': TextEditingController(),
      'slccNatureOfWork': TextEditingController(),
      'slccDescription': TextEditingController(),
      'slccPercent': TextEditingController(text: '100%'),
      'slccAmountOfAward': TextEditingController(),
      'slccCompletionDuration': TextEditingController(),
      'slccDateAwarded': TextEditingController(),
      'slccContractEffectivity': TextEditingController(),
      'slccDateCompleted': TextEditingController(),
    };
    for (final controller in slccControllers.values) {
      controller.addListener(_scheduleSlccSave);
    }
    _loadSlcc();
    _loadTechnicalSpecifications();
    _loadUnitSuggestions();
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
    String quantity = '',
    String unit = '',
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
    priceEntry.dispose();
    setState(() {});
    _scheduleTechnicalSpecificationsSave();
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
              quantity: (value['quantity'] ?? '').toString(),
              unit: (value['unit'] ?? '').toString(),
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
              {'totalPricePerUnit': entry.totalPricePerUnit.text.trim()},
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
          .select()
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      if (row != null) {
        for (final entry in slccControllers.entries) {
          if (entry.key == 'slccPercent') continue;
          entry.value.text = (row[_slccColumn(entry.key)] ?? '').toString();
        }
      }
      slccControllers['slccPercent']!.text = '100%';
    } catch (error) {
      debugPrint('SLCC load error: $error');
    } finally {
      if (mounted) setState(() => isLoadingSlcc = false);
    }
  }

  String _slccColumn(String key) => {
        'slccOwnerName': 'owner_name',
        'slccAddressTelephone': 'address_telephone',
        'slccNumber': 'contact_number',
        'slccNatureOfWork': 'nature_of_work',
        'slccDescription': 'role_description',
        'slccPercent': 'role_percent',
        'slccAmountOfAward': 'amount_of_award',
        'slccCompletionDuration': 'completion_duration',
        'slccDateAwarded': 'date_awarded',
        'slccContractEffectivity': 'contract_effectivity',
        'slccDateCompleted': 'date_completed',
      }[key]!;

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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      for (final entry in slccControllers.entries) {
        data[_slccColumn(entry.key)] = entry.value.text.trim();
      }
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

  Future<void> generatePdf() async {
    setState(() {
      isGenerating = true;
      errorMessage = null;
    });

    try {
      // Give the browser a frame to paint the loading overlay before the
      // CPU-heavy PDF work starts.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      slccSaveTimer?.cancel();
      technicalSpecificationsSaveTimer?.cancel();
      priceScheduleSaveTimer?.cancel();
      await _saveSlcc();
      await _saveTechnicalSpecifications();
      await _savePriceSchedule();
      final bytes = await PdfService.generateBidDocs(
        values: {
          'province': provinceController.text.trim(),
          'municipality': municipalityController.text.trim(),
          'projectTitle': projectTitleController.text.trim(),
          'referenceNumber': referenceNumberController.text.trim(),
          'date': dateController.text.trim(),
          'bidderName': bidderNameController.text.trim(),
          'procuringEntity': procuringEntityController.text.trim(),
          'submittedBy': submittedByController.text.trim(),
          for (final entry in slccControllers.entries)
            entry.key: entry.value.text.trim(),
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
              {'totalPricePerUnit': entry.totalPricePerUnit.text.trim()},
          ]),
        },
      );

      if (!mounted) return;

      if (previewBlobUrl != null) {
        html.Url.revokeObjectUrl(previewBlobUrl!);
      }

      final blob = html.Blob(
        <dynamic>[bytes],
        'application/pdf',
      );

      final blobUrl = html.Url.createObjectUrlFromBlob(blob);

      final viewType = 'generated-pdf-${DateTime.now().microsecondsSinceEpoch}';

      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int viewId) {
          return html.IFrameElement()
            ..src = blobUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..allowFullscreen = true;
        },
      );

      setState(() {
        generatedPdf = bytes;
        previewBlobUrl = blobUrl;
        previewViewType = viewType;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
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
          fillColor: readOnly
              ? const Color(0xFFF1F5F2)
              : Colors.white,
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
    const fields = <(String, String, int)>[
      ('slccOwnerName', "a. Owner's Name", 2),
      ('slccAddressTelephone', 'b. Address / Telephone', 3),
      ('slccNumber', 'c. Number', 1),
      ('slccNatureOfWork', 'Nature of Work', 2),
      ('slccDescription', "Bidder's Role - Description", 4),
      ('slccPercent', "Bidder's Role - %", 1),
      ('slccAmountOfAward', 'a. Amount of Award', 1),
      ('slccCompletionDuration', 'b. Completion Duration', 1),
      ('slccDateAwarded', 'a. Date Awarded', 1),
      ('slccContractEffectivity', 'b. Contract Effectivity', 1),
      ('slccDateCompleted', 'c. Date Completed', 1),
    ];
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
        for (final field in fields)
          formField(
            label: field.$2,
            controller: slccControllers[field.$1]!,
            maxLines: field.$3,
            readOnly: field.$1 == 'slccPercent',
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
                    maxLines: 2,
                  ),
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
                  formField(
                    label: 'Parameter',
                    controller: technicalSpecifications[index].parameter,
                    maxLines: 2,
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

  double _number(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? 0;

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
            final total = _number(price.totalPricePerUnit.text);
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

  @override
  void dispose() {
    if (previewBlobUrl != null) {
      html.Url.revokeObjectUrl(previewBlobUrl!);
    }

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
    for (final controller in slccControllers.values) {
      controller.removeListener(_scheduleSlccSave);
      controller.dispose();
    }
    for (final entry in technicalSpecifications) {
      for (final controller in entry.controllers) {
        controller.removeListener(_scheduleTechnicalSpecificationsSave);
      }
      entry.dispose();
    }
    for (final entry in priceScheduleEntries) {
      entry.totalPricePerUnit.removeListener(_schedulePriceScheduleSave);
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
          final isWide = constraints.maxWidth >= 900;

          final formPanel = Container(
            width: isWide ? 380 : double.infinity,
            color: const Color(0xFFF4F7F5),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
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
                slccFields(),
                const SizedBox(height: 12),
                technicalSpecificationsFields(),
                const SizedBox(height: 12),
                priceScheduleFields(),
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
            child: previewViewType == null
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
                : HtmlElementView(
                    key: ValueKey(previewViewType),
                    viewType: previewViewType!,
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

          return Column(
            children: [
              SizedBox(
                height: 420,
                child: formPanel,
              ),
              const Divider(height: 1),
              Expanded(child: previewPanel),
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

class _TechnicalSpecificationEntry {
  _TechnicalSpecificationEntry({
    String specification = '',
    String quantity = '',
    String unit = '',
    String parameter = '',
  })  : specification = TextEditingController(text: specification),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        parameter = TextEditingController(text: parameter);

  final TextEditingController specification;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController parameter;
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
  _PriceScheduleEntry({String totalPricePerUnit = ''})
      : totalPricePerUnit = TextEditingController(text: totalPricePerUnit);

  final TextEditingController totalPricePerUnit;

  void dispose() => totalPricePerUnit.dispose();
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
