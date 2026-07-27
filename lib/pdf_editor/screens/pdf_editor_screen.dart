import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../services/pdf_service.dart';

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
  late final FocusNode submittedByFocusNode;

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
  }

  Future<void> generatePdf() async {
    setState(() {
      isGenerating = true;
      errorMessage = null;
    });

    try {
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
              suffixIcon: Icon(Icons.arrow_drop_down),
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
