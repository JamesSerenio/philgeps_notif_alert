import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/pdf_service.dart';

class PdfEditorScreen extends StatefulWidget {
  const PdfEditorScreen({super.key});

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final provinceController = TextEditingController(text: 'Bukidnon');
  final municipalityController = TextEditingController(text: 'Impasugong');
  final projectTitleController = TextEditingController();
  final referenceNumberController = TextEditingController();
  final dateController = TextEditingController();
  final bidderNameController = TextEditingController(
    text: 'MIKATA PRIME CORPORATION',
  );

  Uint8List? generatedPdf;
  bool isGenerating = false;
  String? errorMessage;

  Future<void> generatePdf() async {
    setState(() {
      isGenerating = true;
      errorMessage = null;
    });

    try {
      final bytes = await PdfService.generateBidDocs(
        values: {
          'province': provinceController.text,
          'municipality': municipalityController.text,
          'projectTitle': projectTitleController.text,
          'referenceNumber': referenceNumberController.text,
          'date': dateController.text,
          'bidderName': bidderNameController.text,
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
