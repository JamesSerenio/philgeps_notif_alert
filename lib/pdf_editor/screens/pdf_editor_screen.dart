import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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
  late final FocusNode submittedByFocusNode;
  Timer? slccSaveTimer;
  Timer? technicalSpecificationsSaveTimer;
  bool isLoadingSlcc = true;
  bool isSavingSlcc = false;
  bool isLoadingTechnicalSpecifications = true;
  bool isSavingTechnicalSpecifications = false;

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
      'slccPercent': TextEditingController(),
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
    if (rebuild && mounted) setState(() {});
  }

  void _removeTechnicalSpecification(int index) {
    final entry = technicalSpecifications.removeAt(index);
    for (final controller in entry.controllers) {
      controller.removeListener(_scheduleTechnicalSpecificationsSave);
    }
    entry.dispose();
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
    }
  }

  void _scheduleTechnicalSpecificationsSave() {
    if (isLoadingTechnicalSpecifications) return;
    technicalSpecificationsSaveTimer?.cancel();
    technicalSpecificationsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveTechnicalSpecifications,
    );
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
          entry.value.text = (row[_slccColumn(entry.key)] ?? '').toString();
        }
      }
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
      slccSaveTimer?.cancel();
      technicalSpecificationsSaveTimer?.cancel();
      await _saveSlcc();
      await _saveTechnicalSpecifications();
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
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
            decoration: const InputDecoration(
              labelText: 'Submitted by',
              hintText: 'Type or select a name',
              border: OutlineInputBorder(),
              suffixIcon: _SubmittedByMenuIcon(),
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
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'SLCC (Page 21)',
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
          ),
      ],
    );
  }

  Widget technicalSpecificationsFields() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'TECHNICAL SPECIFICATIONS (Pages 47-49)',
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
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Item ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                        child: formField(
                          label: 'Unit',
                          controller: technicalSpecifications[index].unit,
                        ),
                      ),
                    ],
                  ),
                  formField(
                    label: 'Parameter',
                    controller: technicalSpecifications[index].parameter,
                    maxLines: 2,
                  ),
                  const Text('Statement of Compliance: COMPLY'),
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
        ),
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

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bid Docs PDF Editor'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          final formPanel = Container(
            width: isWide ? 360 : double.infinity,
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
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
                slccFields(),
                technicalSpecificationsFields(),
                const SizedBox(height: 8),
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

  List<TextEditingController> get controllers =>
      [specification, quantity, unit, parameter];

  void dispose() {
    specification.dispose();
    quantity.dispose();
    unit.dispose();
    parameter.dispose();
  }
}
