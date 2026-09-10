part of '../pdf_editor_screen.dart';

extension _EditorPreview on _PdfEditorScreenState {
  Future<Uint8List> _renderCompatiblePdf(Uint8List source) async {
    try {
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

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      throw Exception(
        'Clean PDF rewrite failed (${response.statusCode}). The original '
        'incremental PDF was not used because it can expose obsolete pages.',
      );
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('Clean PDF rewrite failed: $error');
    }
  }

  Future<void> generatePdf() async {
    await documentTemplateLoaded;
    await omnibusLoaded;
    await bidSecurityLoaded;
    if (!mounted) return;
    _updateState(() {
      isGenerating = true;
      errorMessage = null;
    });

    try {
      final submittedBy = submittedByController.text.trim();
      final submittedByProfile =
          _PdfEditorScreenState.submittedByProfiles[submittedBy.toUpperCase()];
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
      _calculatePriceBreakdowns();
      final rawBytes = await PdfService.generateBidDocs(
        values: {
          'documentTemplateMode': selectedDocumentTemplate,
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
          'omnibusTemplateType': effectiveOmnibusTemplate,
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
          'bidSecuringDeclarationTemplate': effectiveBidSecurityTemplate,
          'bidSecuringDeclarationWithTable':
              selectedBidSecurityTemplate == 'old' ? 'true' : 'false',
        },
      );

      final bytes = await _renderCompatiblePdf(rawBytes);
      if (!mounted) return;
      if (generatedRevision != contentRevision) {
        _updateState(() {
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

      _updateState(() {
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
      final stackLines =
          (appStackLines.isNotEmpty ? appStackLines : allStackLines.take(6))
              .join('\n');

      _updateState(() {
        errorMessage = '$error\n$stackLines';
      });
    } finally {
      if (mounted) {
        _updateState(() {
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
    generatedPriceBreakdowns.clear();
    if (generatedPdf == null || isGenerating || !mounted) return;
    final oldBlobUrl = previewBlobUrl;
    _updateState(() {
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
      'documentTemplateMode': selectedDocumentTemplate,
      'province': provinceController.text,
      'municipality': municipalityController.text,
      'projectTitle': projectTitleController.text,
      'referenceNumber': referenceNumberController.text,
      'date': dateController.text,
      'bidderName': bidderNameController.text,
      'procuringEntity': procuringEntityController.text,
      'submittedBy': submittedByController.text,
      'slccTemplate': selectedSlccTemplate,
      'omnibusTemplate': selectedOmnibusTemplate,
      'bidSecurityTemplate': selectedBidSecurityTemplate,
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
}
