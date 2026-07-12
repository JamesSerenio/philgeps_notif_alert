import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
  late final TextEditingController provinceController;
  late final TextEditingController municipalityController;
  late final TextEditingController projectTitleController;
  late final TextEditingController referenceNumberController;
  late final TextEditingController dateController;
  late final TextEditingController bidderNameController;
  late final TextEditingController procuringEntityController;

  Uint8List? generatedPdf;
  bool isGenerating = false;
  String? errorMessage;

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
        },
      );

      if (!mounted) return;

      setState(() {
        generatedPdf = bytes;
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

  @override
  void dispose() {
    provinceController.dispose();
    municipalityController.dispose();
    projectTitleController.dispose();
    referenceNumberController.dispose();
    procuringEntityController.dispose();
    dateController.dispose();
    bidderNameController.dispose();
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
            child: generatedPdf == null
                ? const Center(
                    child: Text(
                      'Fill up the form, then click Generate PDF.',
                    ),
                  )
                : SfPdfViewer.memory(
                    generatedPdf!,
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
