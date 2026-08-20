import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'page_mapper.dart';

class PdfService {
  const PdfService._();

  static const String _permanentBusinessAddress =
      'SITIO PULI, CARMEN, CAGAYAN DE ORO CITY, MISAMIS ORIENTAL, 9000';

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
    values = values.map(
      (key, value) => MapEntry(key, _pdfSafeText(value)),
    );
    final ByteData templateData = await rootBundle.load(
      'assets/pdf/bidocs_template.pdf',
    );

    final Uint8List templateBytes = templateData.buffer.asUint8List();

    final PdfDocument document = PdfDocument(
      inputBytes: templateBytes,
    );

    // PDF work on Flutter Web shares the UI thread. Yield between the major
    // stages so loading indicators can continue receiving animation frames.
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Clean replacement for Page 1.
    if (document.pages.count > 0) {
      _drawPageOne(
        document.pages[0],
        values,
      );
    }

    // Page 20 contains the ongoing contracts form.
    if (document.pages.count > 19) {
      _drawContractStatementPage(
        document.pages[19],
        values,
        signatureTop: 428,
        signatureClearTop: 410,
        businessAddressClearTop: 210,
        businessAddressTop: 212,
      );
    }

    // Page 21 uses the same editable header and signatory fields. Its table
    // is taller, so the signature block stays below the supporting notes.
    if (document.pages.count > 20) {
      _drawContractStatementPage(
        document.pages[20],
        values,
        signatureTop: 485,
        signatureClearTop: 478,
        businessAddressClearTop: 174,
        businessAddressTop: 176,
      );
      _drawSlccPrivateRow(document.pages[20], values);
    }

    // Page 47 technical specifications header follows the current bid data.
    if (document.pages.count > 46) {
      _drawTechnicalSpecificationsHeader(document.pages[46], values);
    }

    var technicalSpecificationPageCount = 3;
    if (document.pages.count > 48) {
      technicalSpecificationPageCount =
          _drawTechnicalSpecifications(document, values);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Find the actual Price Schedule section in the source instead of relying
    // on a fixed page number. Some template revisions have blank/form pages
    // immediately before it.
    final priceScheduleStartPage = _findPriceScheduleStartPage(document);
    var priceSchedulePageCount = 1;
    if (priceScheduleStartPage >= 0) {
      priceSchedulePageCount = _drawPriceSchedule(
        document,
        values,
        priceScheduleStartPage,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    final bidPriceSummaryStartPage = _findBidPriceSummaryStartPage(document);
    var bidPriceSummaryPageCount = 1;
    if (bidPriceSummaryStartPage >= 0) {
      bidPriceSummaryPageCount = _drawBidPriceSummary(
        document,
        values,
        bidPriceSummaryStartPage,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    final scheduleRequirementsStartPage =
        _findScheduleRequirementsStartPage(document);
    var scheduleRequirementsPageCount = 1;
    if (scheduleRequirementsStartPage >= 0) {
      scheduleRequirementsPageCount = _drawScheduleRequirements(
        document,
        values,
        scheduleRequirementsStartPage,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Other mapped pages, excluding Page 1.
    final mappedFields = PageMapper.mapValuesToPages(values);

    for (final pageEntry in mappedFields.entries) {
      final int pageIndex = pageEntry.key;

      // Page 1 is already handled above.
      if (pageIndex == 0) continue;

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        continue;
      }

      final PdfPage page = document.pages[pageIndex];

      for (final mappedField in pageEntry.value) {
        final Rect bounds = mappedField.position.bounds;

        page.graphics.drawRectangle(
          brush: PdfSolidBrush(
            PdfColor(255, 255, 255),
          ),
          bounds: Rect.fromLTWH(
            bounds.left - 3,
            bounds.top - 2,
            bounds.width + 6,
            bounds.height + 4,
          ),
        );

        final PdfFont font = PdfStandardFont(
          PdfFontFamily.timesRoman,
          mappedField.field.fontSize,
          style: mappedField.field.isBold
              ? PdfFontStyle.bold
              : PdfFontStyle.regular,
        );

        page.graphics.drawString(
          mappedField.value,
          font,
          bounds: bounds,
          format: PdfStringFormat(
            alignment: PdfTextAlignment.left,
            lineAlignment: PdfVerticalAlignment.top,
            wordWrap: PdfWordWrapType.word,
          ),
        );
      }
    }

    // Remove unused continuation templates only after all original page-index
    // mappings have been applied.
    if (scheduleRequirementsStartPage >= 0) {
      for (var pageIndex = (scheduleRequirementsStartPage + 2)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >=
              scheduleRequirementsStartPage + scheduleRequirementsPageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
    }
    if (bidPriceSummaryStartPage >= 0) {
      for (var pageIndex = (bidPriceSummaryStartPage + 2)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >= bidPriceSummaryStartPage + bidPriceSummaryPageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
    }
    if (priceScheduleStartPage >= 0) {
      for (var pageIndex = (priceScheduleStartPage + 7)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >= priceScheduleStartPage + priceSchedulePageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
      // Keep the two Bid Securing Declaration sheets immediately before the
      // Price Schedule. They are required document pages, not unused
      // Technical Specification continuations.
    }
    if (technicalSpecificationPageCount < 3) {
      document.pages.removeAt(48);
    }
    if (technicalSpecificationPageCount < 2) {
      document.pages.removeAt(47);
    }

    final useDeclarationWithTable =
        values['bidSecuringDeclarationWithTable'] != 'false';
    if (useDeclarationWithTable) {
      // Locate the original form by its actual text after optional technical
      // pages have been removed, since its final page index can change.
      _drawBidSecuringDeclarationDetails(document, values);
    } else {
      await _replaceBidSecuringDeclarationWithoutTable(document, values);
    }

    await Future<void>.delayed(const Duration(milliseconds: 1));

    // The scanned official receipt is only a sample attachment in the source
    // template and is not required in the generated bid documents.
    if (document.pages.count > 45) {
      document.pages.removeAt(45);
    }

    // Optional generated pages shift the forms that follow them. Locate the
    // Omnibus form by its own title instead of relying on a fixed page index.
    final omnibusPageIndex = _findOmnibusSwornStatementPage(document);
    if (omnibusPageIndex >= 0) {
      _drawOmnibusSwornStatementIdentity(
        document,
        values,
        pageIndex: omnibusPageIndex,
      );
      _drawOmnibusSwornStatementLastPage(
        document,
        values,
        pageIndex: omnibusPageIndex + 1,
      );
    }
    // Run this after mapped fields and optional-page removals so the old
    // signature block cannot be drawn back over the cleaned manpower page.
    _drawManpowerSignature(document, values);
    _drawAfterSalesServiceCertificate(document, values);
    _drawProductWarrantyCertificate(document, values);
    _drawJuratPlaceholders(document, values);
    _drawBidForm(document, values);
    _drawSecretaryCertificate(document, values);

    // Replace the two legacy editable SLCC sheets only after every original
    // page mapping is complete. This keeps all following section indexes
    // stable while the document is being prepared.
    await _replaceSlccSection(document, values);
    await _replaceAfsSection(document);

    // Reverse final PDF pages 29-43 while preserving every page exactly.
    // Export them as templates first, remove the original range, then insert
    // them back in reverse order at the same position.
    if (document.pages.count >= 43) {
      const reverseStartIndex = 28;
      const reversePageCount = 15;
      // Templates created directly from `document` become invalid as soon as
      // their source pages are removed. Reopen a snapshot and keep it alive
      // until all reversed pages have been drawn.
      final snapshotBytes = await document.save();
      final snapshotDocument = PdfDocument(inputBytes: snapshotBytes);
      final reversedTemplates = <({PdfTemplate template, Size size})>[
        for (var index = reverseStartIndex + reversePageCount - 1;
            index >= reverseStartIndex;
            index--)
          (
            template: snapshotDocument.pages[index].createTemplate(),
            size: snapshotDocument.pages[index].size,
          ),
      ];
      for (var page = 0; page < reversePageCount; page++) {
        document.pages.removeAt(reverseStartIndex);
      }
      for (var index = 0; index < reversedTemplates.length; index++) {
        final source = reversedTemplates[index];
        final target = document.pages.insert(
          reverseStartIndex + index,
          source.size,
          PdfMargins()..all = 0,
        );
        target.graphics.drawPdfTemplate(
          source.template,
          Offset.zero,
          source.size,
        );
      }
      snapshotDocument.dispose();
    }

    // These two attachment sheets are intentionally excluded from the final
    // bid document. Remove the higher page first so PDF page 44 does not shift
    // before it is deleted (PDF page numbers are one-based).
    if (document.pages.count >= 45) document.pages.removeAt(44);
    if (document.pages.count >= 44) document.pages.removeAt(43);

    // Replace NFCC only after all page moves/removals. Otherwise the newly
    // inserted template can itself be moved or removed by the operations
    // above, leaving the legacy NFCC page in the final document.
    await _replaceNfccPage(document, values);

    if (values['slccTemplateType']?.trim().toLowerCase() == 'none') {
      _removeSlccSection(document);
    }

    final List<int> outputBytes = await document.save();
    document.dispose();

    return Uint8List.fromList(outputBytes);
  }

  static Future<void> _replaceSlccSection(
    PdfDocument document,
    Map<String, String> values,
  ) async {
    final requestedTemplate =
        values['slccTemplateType']?.trim().toLowerCase() ?? 'cctv';
    // Keep the legacy placeholder pages until all fixed-index replacements
    // finish. They are removed near the end when SLCC is disabled.
    if (requestedTemplate == 'none') return;
    final templateType =
        requestedTemplate == 'streetlight' ? 'streetlight' : 'cctv';
    final assetPath = templateType == 'streetlight'
        ? 'assets/pdf/SLCC_Streetlight_template.pdf'
        : 'assets/pdf/SLCC_CCTV_template.pdf';

    // The source bid document keeps the replaceable SLCC sheets specifically
    // on PDF pages 21-23. Keep page 20 untouched.
    const slccPageIndex = 20;
    if (slccPageIndex >= document.pages.count) return;

    final data = await rootBundle.load(assetPath);
    final sourceDocument = PdfDocument(
      inputBytes: data.buffer.asUint8List(),
    );

    // The legacy SLCC occupies PDF pages 21-23 (three consecutive pages).
    // Remove only those sheets and insert the selected replacement at the
    // exact same location.
    for (var page = 0;
        page < 3 && slccPageIndex < document.pages.count;
        page++) {
      document.pages.removeAt(slccPageIndex);
    }

    const a4Size = Size(595.28, 841.89);
    for (var index = 0; index < sourceDocument.pages.count; index++) {
      final sourcePage = sourceDocument.pages[index];
      final sourceSize = sourcePage.size;
      final scale = (a4Size.width / sourceSize.width)
          .clamp(0.0, a4Size.height / sourceSize.height)
          .toDouble();
      final fittedSize = Size(
        sourceSize.width * scale,
        sourceSize.height * scale,
      );
      final offset = Offset(
        (a4Size.width - fittedSize.width) / 2,
        (a4Size.height - fittedSize.height) / 2,
      );
      final targetPage = document.pages.insert(
        slccPageIndex + index,
        a4Size,
        PdfMargins()..all = 0,
      );
      targetPage.graphics.drawPdfTemplate(
        sourcePage.createTemplate(),
        offset,
        fittedSize,
      );
    }
    sourceDocument.dispose();
  }

  static Future<void> _replaceAfsSection(PdfDocument document) async {
    // After the selected SLCC template has been inserted, the legacy Audited
    // Financial Statements occupy PDF pages 29-46 inclusive.
    const afsPageIndex = 28;
    const legacyAfsPageCount = 18;
    if (afsPageIndex >= document.pages.count) return;

    final data = await rootBundle.load('assets/pdf/AFS_template.pdf');
    final sourceDocument = PdfDocument(
      inputBytes: data.buffer.asUint8List(),
    );

    for (var page = 0;
        page < legacyAfsPageCount && afsPageIndex < document.pages.count;
        page++) {
      document.pages.removeAt(afsPageIndex);
    }

    const a4Size = Size(595.28, 841.89);
    for (var index = 0; index < sourceDocument.pages.count; index++) {
      final sourcePage = sourceDocument.pages[index];
      final sourceSize = sourcePage.size;
      final scale = (a4Size.width / sourceSize.width)
          .clamp(0.0, a4Size.height / sourceSize.height)
          .toDouble();
      final fittedSize = Size(
        sourceSize.width * scale,
        sourceSize.height * scale,
      );
      final targetPage = document.pages.insert(
        afsPageIndex + index,
        a4Size,
        PdfMargins()..all = 0,
      );
      targetPage.graphics.drawPdfTemplate(
        sourcePage.createTemplate(),
        Offset(
          (a4Size.width - fittedSize.width) / 2,
          (a4Size.height - fittedSize.height) / 2,
        ),
        fittedSize,
      );
    }
    sourceDocument.dispose();
  }

  static Future<void> _replaceNfccPage(
    PdfDocument document,
    Map<String, String> values,
  ) async {
    // The legacy NFCC is commonly a flattened scan, so its own title cannot
    // always be extracted. Anchor it to the document structure instead: NFCC
    // is the page immediately before the generated Technical Specifications
    // section. This remains correct when earlier sections gain extra pages.
    int? nfccPageIndex;
    final documentLines = PdfTextExtractor(document).extractTextLines();
    int? technicalSpecificationsPageIndex;
    for (final line in documentLines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (line.pageIndex >= 20 && text.trim() == 'TECHNICAL SPECIFICATIONS') {
        technicalSpecificationsPageIndex ??= line.pageIndex;
      }
      if (line.pageIndex >= 20 &&
          text.contains('NET FINANCIAL CONTRACTING CAPACITY') &&
          text.contains('NFCC') &&
          text.length < 100) {
        nfccPageIndex = line.pageIndex;
      }
    }
    if (technicalSpecificationsPageIndex != null &&
        technicalSpecificationsPageIndex > 0) {
      nfccPageIndex = technicalSpecificationsPageIndex - 1;
    }
    if (nfccPageIndex == null) return;

    final data = await rootBundle.load('assets/pdf/NFCC_Template.pdf');
    final sourceDocument = PdfDocument(inputBytes: data.buffer.asUint8List());
    if (sourceDocument.pages.count == 0) {
      sourceDocument.dispose();
      return;
    }

    final sourcePage = sourceDocument.pages[0];
    final graphics = sourcePage.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.helvetica, 12);
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final italic = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.italic,
    );
    final headerLabelFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final headerValueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.bold,
    );
    final red = PdfSolidBrush(PdfColor(210, 0, 0));
    final procuringEntity = (values['procuringEntity'] ?? '').trim();
    final referenceNumber = (values['referenceNumber'] ?? '').trim();
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final submittedBy = (values['submittedBy'] ?? '').trim();
    final date = DateFormat('MMMM d, yyyy').format(DateTime.now());
    const address =
        'SITIO PULI, CARMEN, CAGAYAN DE ORO CITY, MISAMIS ORIENTAL, 9000';

    // Values in the supplied NFCC file are sometimes encoded together in a
    // single text object. Clear the complete variable header instead of
    // trying to replace individual extracted lines.
    graphics.drawRectangle(
      brush: white,
      // Cover only the legacy header. Keep a clear gap before the first body
      // line, which starts at about y=178 in the supplied template.
      bounds: Rect.fromLTWH(18, 58, sourcePage.size.width - 36, 110),
    );
    void drawHeader(
      String label,
      String value,
      double top, {
      double valueHeight = 18,
    }) {
      graphics.drawString(
        label,
        headerLabelFont,
        brush: black,
        bounds: Rect.fromLTWH(20, top, 174, 18),
      );
      graphics.drawString(
        ':',
        headerLabelFont,
        brush: black,
        bounds: Rect.fromLTWH(196, top, 10, 18),
      );
      graphics.drawString(
        value,
        headerValueFont,
        brush: red,
        bounds: Rect.fromLTWH(
          212,
          top,
          sourcePage.size.width - 232,
          valueHeight,
        ),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
    }

    drawHeader(
      'NAME OF THE PROCURING ENTITY',
      procuringEntity.toUpperCase(),
      61,
    );
    drawHeader('PROJECT TITLE', projectTitle.toUpperCase(), 76,
        valueHeight: 30);
    drawHeader('REFERENCE NUMBER', referenceNumber, 108);
    drawHeader(
      'CONTRACTOR',
      (values['bidderName'] ?? '').trim().toUpperCase(),
      123,
    );
    drawHeader('ADDRESS', address, 138, valueHeight: 27);

    // Replace the complete signatory block and always stamp today's date.
    // The original signatory block starts well above the bottom margin.
    // Clear from there through the bottom so both the old and any previously
    // generated values are removed before drawing the single final block.
    // Begin below the NFCC computation table. This is high enough to remove
    // the legacy MARLJONE block but does not cover the Computed NFCC row.
    final footerTop = sourcePage.size.height - 235;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        18,
        footerTop - 12,
        sourcePage.size.width - 36,
        247,
      ),
    );
    graphics.drawString(
      'Submitted',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(20, footerTop, 105, 18),
    );
    graphics.drawString(
      submittedBy.toUpperCase(),
      bold,
      brush: black,
      bounds: Rect.fromLTWH(125, footerTop, 330, 18),
    );
    final submittedWidth = bold.measureString(submittedBy.toUpperCase()).width;
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: 0.7),
      Offset(125, footerTop + 14),
      Offset(125 + submittedWidth, footerTop + 14),
    );
    graphics.drawString(
      'Designation',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(20, footerTop + 18, 105, 18),
    );
    graphics.drawString(
      ':    Authorized Representative',
      italic,
      brush: black,
      bounds: Rect.fromLTWH(125, footerTop + 18, 330, 18),
    );
    graphics.drawString(
      'Date',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(20, footerTop + 36, 105, 18),
    );
    graphics.drawString(
      ':    $date',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(125, footerTop + 36, 280, 18),
    );

    // Save and reopen the edited NFCC template before importing it. Creating a
    // template directly from sourcePage can copy the original imported page
    // and omit the replacement graphics drawn above.
    final modifiedSourceBytes = await sourceDocument.save();
    sourceDocument.dispose();
    final flattenedSourceDocument = PdfDocument(
      inputBytes: modifiedSourceBytes,
    );
    final flattenedSourcePage = flattenedSourceDocument.pages[0];

    document.pages.removeAt(nfccPageIndex);
    const a4Size = Size(595.28, 841.89);
    final sourceSize = flattenedSourcePage.size;
    final scale = (a4Size.width / sourceSize.width)
        .clamp(0.0, a4Size.height / sourceSize.height)
        .toDouble();
    final fittedSize =
        Size(sourceSize.width * scale, sourceSize.height * scale);
    final targetPage = document.pages.insert(
      nfccPageIndex,
      a4Size,
      PdfMargins()..all = 0,
    );
    targetPage.graphics.drawPdfTemplate(
      flattenedSourcePage.createTemplate(),
      Offset(
        (a4Size.width - fittedSize.width) / 2,
        (a4Size.height - fittedSize.height) / 2,
      ),
      fittedSize,
    );
    flattenedSourceDocument.dispose();
  }

  /// Standard PDF fonts do not contain Unicode checkmark glyphs. Normalize
  /// common pasted checkmarks before any page is drawn so one specification
  /// cannot abort the entire document with "character 9971".
  static String _pdfSafeText(String value) => value
      .replaceAll('\u2714', '\u2713')
      .replaceAll('\u221A', '\u2713')
      // This function also receives JSON-encoded form values. Use escaped
      // newline sequences so replacing a legacy separator cannot insert a
      // raw control character inside a JSON string literal.
      .replaceAll('\u2029', r'\n\n');

  static void _drawMarkedSpecificationText(
    PdfGraphics graphics,
    String text,
    PdfFont font,
    PdfBrush brush,
    Rect bounds,
  ) {
    final markerPattern = RegExp(r'^\s*(✓|•|○|■|➢)\s*');
    final entries = <({String? marker, String content, double height})>[];
    for (final sourceLine in text.split(RegExp(r'\r?\n'))) {
      final match = markerPattern.firstMatch(sourceLine);
      final marker = match?.group(1);
      final content =
          match == null ? sourceLine : sourceLine.substring(match.end);
      final contentWidth = bounds.width - (marker == null ? 0 : 14);
      final measured = font.measureString(
        content.isEmpty ? ' ' : content,
        layoutArea: Size(contentWidth, bounds.height),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
      entries.add((
        marker: marker,
        content: content,
        height: measured.height.clamp(font.size + 2, bounds.height).toDouble(),
      ));
    }
    final totalHeight = entries.fold<double>(0, (sum, row) => sum + row.height);
    var top = bounds.top +
        ((bounds.height - totalHeight) / 2).clamp(0, bounds.height).toDouble();
    final markerPen = PdfPen(PdfColor(0, 0, 0), width: 1.15);
    final markerBrush = PdfSolidBrush(PdfColor(0, 0, 0));

    for (final entry in entries) {
      final marker = entry.marker;
      var textLeft = bounds.left;
      if (marker != null) {
        final markerTop = top + (entry.height - 9) / 2;
        switch (marker) {
          case '✓':
            graphics.drawLine(
              markerPen,
              Offset(bounds.left + 1, markerTop + 5),
              Offset(bounds.left + 4, markerTop + 8),
            );
            graphics.drawLine(
              markerPen,
              Offset(bounds.left + 4, markerTop + 8),
              Offset(bounds.left + 10, markerTop + 1),
            );
            break;
          case '•':
            graphics.drawEllipse(
              Rect.fromLTWH(bounds.left + 3, markerTop + 3, 5, 5),
              brush: markerBrush,
            );
            break;
          case '○':
            graphics.drawEllipse(
              Rect.fromLTWH(bounds.left + 2, markerTop + 2, 7, 7),
              pen: markerPen,
            );
            break;
          case '■':
            graphics.drawRectangle(
              brush: markerBrush,
              bounds: Rect.fromLTWH(bounds.left + 2, markerTop + 2, 7, 7),
            );
            break;
          case '➢':
            graphics.drawLine(
              markerPen,
              Offset(bounds.left + 1, markerTop + 1),
              Offset(bounds.left + 10, markerTop + 5),
            );
            graphics.drawLine(
              markerPen,
              Offset(bounds.left + 10, markerTop + 5),
              Offset(bounds.left + 1, markerTop + 9),
            );
            break;
        }
        textLeft += 14;
      }
      graphics.drawString(
        entry.content,
        font,
        brush: brush,
        bounds: Rect.fromLTWH(
          textLeft,
          top,
          bounds.right - textLeft,
          entry.height,
        ),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
      top += entry.height;
    }
  }

  static void _drawPageOne(
    PdfPage page,
    Map<String, String> values,
  ) {
    final String province = (values['province'] ?? '').trim().toUpperCase();

    final String municipality = (values['municipality'] ?? '').trim();

    final String projectTitle = (values['projectTitle'] ?? '').trim();

    final String date = (values['date'] ?? '').trim();

    final String bidderName = (values['bidderName'] ?? '').trim();

    final PdfGraphics graphics = page.graphics;

    final PdfBrush whiteBrush = PdfSolidBrush(
      PdfColor(255, 255, 255),
    );

    final PdfBrush blackBrush = PdfSolidBrush(
      PdfColor(0, 0, 0),
    );

    /*
     * Cover the complete original header.
     * Includes:
     * Republic of the Philippines
     * Province
     * Municipality
     */
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(
        90,
        24,
        415,
        56,
      ),
    );

    /*
     * Cover the complete original project information.
     * Includes old Project, Date and Bidder values.
     */
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(
        30,
        118,
        535,
        112,
      ),
    );

    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(
        75,
        82,
        445,
        30,
      ),
    );

    final PdfFont republicFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.regular,
    );

    final PdfFont headerFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.regular,
    );

    final PdfFont municipalityFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.regular,
    );

    final PdfFont checklistFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.regular,
    );

    final PdfFont labelFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
    );

    final PdfFont valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );

    final PdfStringFormat centerFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );

    /*
     * Redraw the header.
     */
    graphics.drawString(
      'Republic of the Philippines',
      republicFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        28,
        395,
        18,
      ),
      format: centerFormat,
    );

    graphics.drawString(
      'CHECKLIST OF ELIGIBILITY REQUIREMENTS FOR GOODS',
      checklistFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        75,
        87,
        445,
        22,
      ),
      format: centerFormat,
    );

    graphics.drawString(
      'PROVINCE OF $province',
      headerFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        43,
        395,
        18,
      ),
      format: centerFormat,
    );

    graphics.drawString(
      'Municipality of $municipality',
      municipalityFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        58,
        395,
        18,
      ),
      format: centerFormat,
    );

    // Keep every row on the same label / colon / value grid used by the
    // source bid document. The project value may occupy two lines; the
    // following rows start below that reserved area.
    void drawInformationRow({
      required String label,
      required String value,
      required double top,
      required double valueHeight,
    }) {
      graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(36, top, 100, 18),
      );
      graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(145, top, 12, 18),
      );
      graphics.drawString(
        value,
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(180, top, 360, valueHeight),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.left,
          lineAlignment: PdfVerticalAlignment.top,
          wordWrap: PdfWordWrapType.word,
        ),
      );
    }

    int wrappedLineCount(
      String text,
      PdfFont font,
      double maximumWidth,
    ) {
      if (text.isEmpty) return 1;

      var lineCount = 1;
      var currentLine = '';

      for (final word in text.split(RegExp(r'\s+'))) {
        final candidate = currentLine.isEmpty ? word : '$currentLine $word';

        if (currentLine.isNotEmpty &&
            font.measureString(candidate).width > maximumWidth) {
          lineCount++;
          currentLine = word;
        } else {
          currentLine = candidate;
        }
      }

      return lineCount;
    }

    const double projectTop = 132;
    const double valueWidth = 360;
    final double lineHeight = valueFont.measureString('Ag').height;
    final int projectLineCount = wrappedLineCount(
      projectTitle,
      valueFont,
      valueWidth,
    );
    final double projectHeight = projectLineCount * lineHeight;
    final double dateTop = projectTop + projectHeight + 4;
    final double bidderTop = dateTop + lineHeight + 3;

    drawInformationRow(
      label: 'Project',
      value: projectTitle,
      top: projectTop,
      valueHeight: projectHeight + 2,
    );
    drawInformationRow(
      label: 'Date',
      value: date,
      top: dateTop,
      valueHeight: lineHeight + 2,
    );
    drawInformationRow(
      label: 'Name of Bidder',
      value: bidderName,
      top: bidderTop,
      valueHeight: lineHeight + 2,
    );
  }

  static void _drawContractStatementPage(
    PdfPage page,
    Map<String, String> values, {
    required double signatureTop,
    required double signatureClearTop,
    required double businessAddressClearTop,
    required double businessAddressTop,
  }) {
    final procuringEntity = (values['procuringEntity'] ?? '').trim();
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final referenceNumber = (values['referenceNumber'] ?? '').trim();
    final submittedBy = (values['submittedBy'] ?? '').trim();
    final bidderName = (values['bidderName'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final signatureFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final captionFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final valueFormat = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.top,
      wordWrap: PdfWordWrapType.word,
    );

    // Remove the old fixed header values and redraw the complete block so
    // wrapped project titles can move the reference-number row downward.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(20, 20, 802, 92),
    );

    void drawHeaderRow(
      String label,
      String value,
      double top,
      double height,
    ) {
      graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(36, top, 205, 18),
      );
      graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(252, top, 10, 18),
      );
      graphics.drawString(
        value.toUpperCase(),
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(288, top, 520, height),
        format: valueFormat,
      );
    }

    String wrapProjectTitle(String text) {
      const maximumCharactersPerLine = 60;
      final lines = <String>[];
      var currentLine = '';

      for (final word in text.trim().split(RegExp(r'\s+'))) {
        final candidate = currentLine.isEmpty ? word : '$currentLine $word';
        if (currentLine.isNotEmpty &&
            candidate.length > maximumCharactersPerLine) {
          lines.add(currentLine);
          currentLine = word;
        } else {
          currentLine = candidate;
        }
      }

      if (currentLine.isNotEmpty) lines.add(currentLine);
      return lines.isEmpty ? '' : lines.join('\n');
    }

    const projectTop = 52.0;
    final lineHeight = valueFont.measureString('Ag').height;
    final wrappedProjectTitle = wrapProjectTitle(projectTitle.toUpperCase());
    final projectLineCount = wrappedProjectTitle.isEmpty
        ? 1
        : wrappedProjectTitle.split('\n').length;
    final projectHeight = projectLineCount * lineHeight;
    final referenceTop = projectTop + projectHeight + 3;

    drawHeaderRow('NAME OF THE PROCURING ENTITY', procuringEntity, 38, 18);
    drawHeaderRow(
      'PROJECT TITLE',
      wrappedProjectTitle,
      projectTop,
      projectHeight + 1,
    );
    drawHeaderRow(
      'REFERENCE NUMBER',
      referenceNumber,
      referenceTop,
      18,
    );

    // The source template contains the company's former address as fixed
    // text. Replace it on both contract-statement pages with the permanent
    // business address used throughout the generated bid documents.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(390, businessAddressClearTop, 427, 34),
    );
    graphics.drawString(
      _permanentBusinessAddress.toUpperCase(),
      valueFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(396, businessAddressTop, 419, 30),
      format: valueFormat,
    );

    // Replace the complete old signatory block and position it below the
    // table, matching the source document's label / colon / value columns.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(20, signatureClearTop, 520, 112),
    );

    void drawSignatureRow(String label, String value, double top) {
      graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(36, top, 68, 18),
      );
      graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(112, top, 10, 18),
      );
      graphics.drawString(
        value,
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(150, top, 375, 18),
      );
    }

    drawSignatureRow(
      'Submitted by',
      submittedBy.toUpperCase(),
      signatureTop,
    );
    graphics.drawString(
      '(Printed Name & Signature)',
      captionFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(150, signatureTop + 15, 210, 14),
    );
    final signatureWidth = signatureFont
        .measureString(submittedBy.toUpperCase())
        .width
        .clamp(0, 375)
        .toDouble();
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: 0.5),
      Offset(150, signatureTop + 14),
      Offset(150 + signatureWidth, signatureTop + 14),
    );
    drawSignatureRow(
      'Designation',
      'Authorized Representative',
      signatureTop + 31,
    );
    drawSignatureRow(
      'Name of Firm',
      bidderName.toUpperCase(),
      signatureTop + 48,
    );
    drawSignatureRow('Date', date, signatureTop + 65);
  }

  static void _drawSlccPrivateRow(
    PdfPage page,
    Map<String, String> values,
  ) {
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));

    String value(String key) => (values[key] ?? '').trim();
    String labeled(String label, String key) {
      final text = value(key);
      return text.isEmpty ? '$label NONE' : '$label $text';
    }

    String labeledUpper(String label, String key) {
      final text = value(key);
      return text.isEmpty ? '$label NONE' : '$label ${text.toUpperCase()}';
    }

    final percent = value('slccPercent');
    const rowTop = 285.0;
    const rowBottom = 410.0;
    const columns = <double>[37, 148, 283, 369, 482, 575, 691, 821];

    // Preserve the original template grid. Clear only the inside of each
    // PRIVATE data cell, leaving enough inset to keep every original border.
    for (var index = 1; index < columns.length - 1; index++) {
      final left = columns[index];
      final right = columns[index + 1];
      graphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(
          left + 3,
          rowTop + 2,
          right - left - 6,
          rowBottom - rowTop - 4,
        ),
      );
    }

    // Only this separator needs to be restored after clearing the editable
    // cells. Keep the template's other rules untouched so no doubled grid is
    // introduced by tiny coordinate differences in the source PDF.
    final tableBorderPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
    graphics.drawLine(
      tableBorderPen,
      const Offset(479.5, 235),
      const Offset(479.5, rowBottom),
    );

    final cells = <({Rect bounds, String text, bool bold, bool centered})>[
      (
        bounds: const Rect.fromLTWH(153, 290, 125, 115),
        text: [
          labeledUpper('a.', 'slccOwnerName'),
          labeledUpper('b.', 'slccAddressTelephone'),
          labeledUpper('c.', 'slccNumber'),
        ].join('\n'),
        bold: false,
        centered: false,
      ),
      (
        bounds: const Rect.fromLTWH(287, 290, 78, 115),
        text: value('slccNatureOfWork').toUpperCase(),
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(373, 290, 105, 115),
        text: value('slccDescription').toUpperCase(),
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(486, 290, 85, 115),
        text: percent.isEmpty
            ? ''
            : percent.endsWith('%')
                ? percent
                : '$percent%',
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(579, 290, 108, 115),
        text: [
          labeled('a.', 'slccAmountOfAward'),
          labeled('b.', 'slccCompletionDuration'),
        ].join('\n'),
        bold: false,
        centered: false,
      ),
      (
        bounds: const Rect.fromLTWH(695, 290, 122, 115),
        text: [
          labeled('a.', 'slccDateAwarded'),
          labeled('b.', 'slccContractEffectivity'),
          labeled('c.', 'slccDateCompleted'),
        ].join('\n'),
        bold: false,
        centered: false,
      ),
    ];

    for (final cell in cells) {
      if (cell.text.isEmpty) continue;

      final font = PdfStandardFont(
        PdfFontFamily.timesRoman,
        12,
        style: cell.bold ? PdfFontStyle.bold : PdfFontStyle.regular,
      );
      graphics.drawString(
        cell.text,
        font,
        brush: blackBrush,
        bounds: cell.bounds,
        format: PdfStringFormat(
          alignment:
              cell.centered ? PdfTextAlignment.center : PdfTextAlignment.left,
          lineAlignment: PdfVerticalAlignment.middle,
          wordWrap: PdfWordWrapType.word,
        ),
      );
    }
  }

  static void _drawTechnicalSpecificationsHeader(
    PdfPage page,
    Map<String, String> values,
  ) {
    final procuringEntity =
        (values['procuringEntity'] ?? '').trim().toUpperCase();
    final projectTitle = (values['projectTitle'] ?? '').trim().toUpperCase();
    final referenceNumber = (values['referenceNumber'] ?? '').trim();

    String wrapText(String text, int maximumCharactersPerLine) {
      final lines = <String>[];
      var currentLine = '';
      for (final word in text.split(RegExp(r'\s+'))) {
        final candidate = currentLine.isEmpty ? word : '$currentLine $word';
        if (currentLine.isNotEmpty &&
            candidate.length > maximumCharactersPerLine) {
          lines.add(currentLine);
          currentLine = word;
        } else {
          currentLine = candidate;
        }
      }
      if (currentLine.isNotEmpty) lines.add(currentLine);
      return lines.join('\n');
    }

    final wrappedTitle = wrapText(projectTitle, 42);
    final titleLineCount =
        wrappedTitle.isEmpty ? 1 : wrappedTitle.split('\n').length;
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.bold,
    );
    final lineHeight = valueFont.measureString('Ag').height;
    final titleHeight = titleLineCount * lineHeight;
    const projectTop = 88.0;
    final referenceTop = projectTop + titleHeight + 4;
    final format = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.top,
      wordWrap: PdfWordWrapType.word,
    );

    // Redraw the complete block so old Sumilao values cannot remain visible.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(30, 68, 545, 98),
    );

    void drawRow(
      String label,
      String value,
      double top,
      double height,
    ) {
      graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(36, top, 195, 16),
      );
      graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(245, top, 10, 16),
      );
      graphics.drawString(
        value,
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(280, top, 285, height),
        format: format,
      );
    }

    drawRow('NAME OF THE PROCURING ENTITY', procuringEntity, 74, 16);
    drawRow('PROJECT TITLE', wrappedTitle, projectTop, titleHeight + 1);
    drawRow('REFERENCE NUMBER', referenceNumber, referenceTop, 16);
  }

  static void _drawBidSecuringDeclarationDetails(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final extractor = PdfTextExtractor(document);
    final allLines = extractor.extractTextLines();
    int? declarationPageIndex;
    for (final line in allLines) {
      if (line.text.toUpperCase().contains('BID SECURING DECLARATION')) {
        declarationPageIndex = line.pageIndex;
        break;
      }
    }
    if (declarationPageIndex == null) return;

    // Rebuild the signature/Jurat sheet on a fresh page. Syncfusion can append
    // edits behind the existing content streams of a loaded PDF page, and
    // Chrome then keeps showing the hardcoded template values. Drawing the
    // original sheet first on a new page guarantees all corrections that
    // follow are visually on top.
    final signatureSheetIndex = declarationPageIndex + 1;
    if (signatureSheetIndex < document.pages.count) {
      final originalSignaturePage = document.pages[signatureSheetIndex];
      final signatureSize = originalSignaturePage.size;
      document.pages.removeAt(signatureSheetIndex);
      final zeroMargins = PdfMargins()..all = 0;
      document.pages.insert(
        signatureSheetIndex,
        signatureSize,
        zeroMargins,
      );
    }

    final page = document.pages[declarationPageIndex];
    final pageLines = allLines
        .where((line) => line.pageIndex == declarationPageIndex)
        .toList();
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final textFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final boldTextFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.italic,
    );
    final recipientFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      11,
      style: PdfFontStyle.italic,
    );
    final linePen = PdfPen(PdfColor(0, 0, 0), width: 0.7);
    final procuringEntityValue = (values['procuringEntity'] ?? '').trim();
    final entityParts = procuringEntityValue
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final entityMunicipality = entityParts.isEmpty
        ? ''
        : entityParts.first
            .replaceFirst(
              RegExp(r'^MUNICIPALITY\s+OF\s+', caseSensitive: false),
              '',
            )
            .trim();
    final entityProvince = entityParts.length > 1 ? entityParts.last : '';
    // The witness venue follows the Procuring Entity. Sidebar municipality
    // and province values are only fallbacks for older records.
    final municipalityValue = entityMunicipality.isNotEmpty
        ? entityMunicipality
        : (values['municipality'] ?? '').trim();
    final provinceValue = entityProvince.isNotEmpty
        ? entityProvince
        : (values['province'] ?? '').trim();
    final municipality = municipalityValue.toUpperCase();
    final province = provinceValue.toUpperCase();
    String titleCase(String value) => value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) =>
            '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
    final venue = 'Municipality of ${titleCase(municipalityValue)}'
        '${provinceValue.isEmpty ? '' : ', ${titleCase(provinceValue)}'}';
    final dateParts = (values['date'] ?? '').trim().split(RegExp(r'\s+'));
    final year = dateParts.isEmpty ? '' : dateParts.last;
    final recipient = 'MUNICIPALITY OF $municipality, $province';

    var recipientTop = 181.0;
    var witnessTop = 936.0;
    for (final line in pageLines) {
      final text = line.text.toUpperCase();
      if (text.contains('MUNICIPALITY OF SUMILAO') && text.contains('TO:')) {
        recipientTop = line.bounds.top;
      }
      if (text.contains('IN WITNESS WHEREOF')) {
        witnessTop = line.bounds.top;
      }
    }

    // Replace the fixed SUMILAO, BUKIDNON recipient with the municipality and
    // province selected in the editor. The extracted Y position keeps this
    // correct even if the form moves to a different page index.
    graphics.drawRectangle(
      brush: whiteBrush,
      // Keep the original "To:" so its font and spacing remain untouched.
      bounds: Rect.fromLTWH(55, recipientTop - 2, 397, 18),
    );
    graphics.drawString(
      recipient,
      recipientFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(57, recipientTop - 1.5, 390, 16),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.none,
      ),
    );
    // Standard PDF fonts expose bold and italic separately. A tiny second
    // italic pass recreates the heavier bold-italic appearance of the source.
    graphics.drawString(
      recipient,
      recipientFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(57.18, recipientTop - 1.5, 390, 16),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.none,
      ),
    );
    graphics.drawString(
      recipient,
      recipientFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(57.36, recipientTop - 1.5, 390, 16),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.none,
      ),
    );
    graphics.drawString(
      recipient,
      recipientFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(57.18, recipientTop - 1.38, 390, 16),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.none,
      ),
    );

    // Erase the legacy witness sentence from the declaration page itself.
    // It is redrawn only once on the following signature page.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(
        30,
        witnessTop - 4,
        page.getClientSize().width - 60,
        48,
      ),
    );

    // Use a scratch canvas only until the destination signature page is
    // resolved; no visible witness text is drawn back on the first page.
    final witnessScratch = PdfTemplate(600, 100);
    final scratchGraphics = witnessScratch.graphics!;
    scratchGraphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(33, witnessTop - 2, 545, 42),
    );

    // Move the witness statement to the signature page, directly above the
    // "Duly authorized" caption.
    var witnessGraphics = scratchGraphics;
    double? dulyTop;
    int? signaturePageIndex;
    for (final line in allLines) {
      if (line.text.toUpperCase().contains('DULY AUTHORIZED TO SIGN THE BID')) {
        signaturePageIndex = line.pageIndex;
        dulyTop = line.bounds.top;
        break;
      }
    }
    if (signaturePageIndex != null && dulyTop != null) {
      witnessTop = dulyTop - 44;
      witnessGraphics = document.pages[signaturePageIndex].graphics;
      witnessGraphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(33, witnessTop - 2, 545, 40),
      );
    }

    const firstLine =
        'IN WITNESS WHEREOF, I/We have hereunto set my/our hand/s this';
    witnessGraphics.drawString(
      firstLine,
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36, witnessTop, 400, 15),
    );

    // Place the first writing line immediately after "this" instead of using
    // a fixed X coordinate that can leave a conspicuous gap.
    final firstLineWidth = textFont.measureString(firstLine).width;
    final dayLineLeft = 36 + firstLineWidth + 3;
    const dayLineWidth = 28.0;
    witnessGraphics.drawLine(
      linePen,
      Offset(dayLineLeft, witnessTop + 12),
      Offset(dayLineLeft + dayLineWidth, witnessTop + 12),
    );
    final dayOfLeft = dayLineLeft + dayLineWidth + 4;
    witnessGraphics.drawString(
      'day of',
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(dayOfLeft, witnessTop, 34, 15),
    );
    final dayOfWidth = textFont.measureString('day of').width;
    final monthLineLeft = dayOfLeft + dayOfWidth + 4;
    const monthLineWidth = 44.0;
    witnessGraphics.drawLine(
      linePen,
      Offset(monthLineLeft, witnessTop + 12),
      Offset(monthLineLeft + monthLineWidth, witnessTop + 12),
    );
    final yearLeft = monthLineLeft + monthLineWidth + 4;
    final venueWords = venue.split(RegExp(r'\s+'));
    final venueLead = venueWords.isEmpty ? '' : venueWords.first;
    final venueRemainder =
        venueWords.length <= 1 ? '' : venueWords.skip(1).join(' ');
    witnessGraphics.drawString(
      '$year at $venueLead',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(yearLeft, witnessTop, 150, 15),
    );
    witnessGraphics.drawString(
      '$year at $venueLead',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(yearLeft + 0.18, witnessTop, 150, 15),
    );
    witnessGraphics.drawString(
      '$year at $venueLead',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(yearLeft + 0.36, witnessTop, 150, 15),
    );
    witnessGraphics.drawString(
      '$year at $venueLead',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(yearLeft + 0.18, witnessTop + 0.12, 150, 15),
    );

    // Use the municipality and province selected in the editor.
    witnessGraphics.drawString(
      '$venueRemainder.',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36, witnessTop + 20, 500, 15),
    );
    witnessGraphics.drawString(
      '$venueRemainder.',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36.18, witnessTop + 20, 500, 15),
    );
    witnessGraphics.drawString(
      '$venueRemainder.',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36.36, witnessTop + 20, 500, 15),
    );
    witnessGraphics.drawString(
      '$venueRemainder.',
      boldTextFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36.18, witnessTop + 20.12, 500, 15),
    );

    if (signaturePageIndex != null && dulyTop != null) {
      final signatureGraphics = document.pages[signaturePageIndex].graphics;
      final bidderName = (values['bidderName'] ?? '').trim();
      final submittedBy =
          (values['submittedByFormalName'] ?? values['submittedBy'] ?? '')
              .trim();
      final date = (values['date'] ?? '').trim();
      final signatureFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        10,
        style: PdfFontStyle.italic,
      );

      // Replace the template's fixed company, representative and date while
      // redrawing the unchanged designation between them.
      signatureGraphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(
          0,
          dulyTop + 10,
          document.pages[signaturePageIndex].getClientSize().width,
          140,
        ),
      );
      void drawSignatureValue(String text, double top, {bool heavy = true}) {
        signatureGraphics.drawString(
          text,
          signatureFont,
          brush: blackBrush,
          bounds: Rect.fromLTWH(36, top, 300, 15),
        );
        if (heavy) {
          signatureGraphics.drawString(
            text,
            signatureFont,
            brush: blackBrush,
            bounds: Rect.fromLTWH(36.18, top, 300, 15),
          );
        }
      }

      drawSignatureValue(bidderName, dulyTop + 31);
      drawSignatureValue(submittedBy, dulyTop + 79);
      drawSignatureValue(
        'Authorized Representative',
        dulyTop + 96,
        heavy: false,
      );
      drawSignatureValue(date, dulyTop + 113);
    }

    // Replace the fixed values that are baked into the original declaration
    // page. Using each extracted line's own bounds is more reliable than one
    // large signature rectangle because this template has a shifted crop box.
    final formalRepresentative =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
    final selectedDate = (values['date'] ?? '').trim();
    final selectedMunicipality = (values['municipality'] ?? '').trim();
    final selectedProvince = (values['province'] ?? '').trim();
    final selectedPlace =
        'Municipality of $selectedMunicipality, $selectedProvince';
    final correctionFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.italic,
    );

    void replaceExtractedLine(dynamic line, String replacement,
        {double? height}) {
      final correctionGraphics = document.pages[line.pageIndex].graphics;
      final bounds = line.bounds;
      final isMunicipalityHeading = line.pageIndex == declarationPageIndex &&
          line.text.trim().toUpperCase().startsWith('MUNICIPALITY OF');
      correctionGraphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(
          bounds.left - 2,
          bounds.top - 2,
          isMunicipalityHeading
              ? 260
              : document.pages[line.pageIndex].getClientSize().width -
                  bounds.left -
                  18,
          height ?? bounds.height + 5,
        ),
      );
      correctionGraphics.drawString(
        replacement,
        correctionFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          bounds.left,
          bounds.top,
          document.pages[line.pageIndex].getClientSize().width -
              bounds.left -
              20,
          height ?? bounds.height + 7,
        ),
      );
    }

    for (final line in allLines) {
      if (line.pageIndex < declarationPageIndex ||
          line.pageIndex > declarationPageIndex + 1) {
        continue;
      }
      final text = line.text.trim();
      final upper = text.toUpperCase();
      if (selectedMunicipality.isNotEmpty &&
          upper.contains('MUNICIPALITY OF IMPASUGONG')) {
        replaceExtractedLine(
          line,
          text.replaceAll(
            RegExp('Municipality of Impasugong', caseSensitive: false),
            selectedPlace,
          ),
          height: upper.startsWith('SUBSCRIBED AND SWORN') ? 30 : null,
        );
      } else if (upper.contains('JHO ANN Q. CLEOPAS')) {
        replaceExtractedLine(line, formalRepresentative);
      } else if (upper == 'AUTHORIZED REPRESENTATIVE') {
        replaceExtractedLine(line, 'Authorized Representative');
      } else if (selectedDate.isNotEmpty && upper == 'JULY 20, 2026') {
        replaceExtractedLine(line, selectedDate);
      }
    }

    if (declarationPageIndex + 1 < document.pages.count) {
      _drawBidSecuringDeclarationFixedLastPage(
        document.pages[declarationPageIndex + 1],
        values,
      );
    }
  }

  static void _drawBidSecuringDeclarationFixedLastPage(
    PdfPage page,
    Map<String, String> values,
  ) {
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final italicFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.italic,
    );
    final representative =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final municipality = (values['municipality'] ?? '').trim();
    final bidderName = (values['bidderName'] ?? '').trim();

    // Syncfusion's standard fonts do not expose a combined bold-italic style.
    // Repeating the italic glyphs with tiny offsets matches the emphasized,
    // slanted values in the source declaration.
    void drawBoldItalic(
      String text,
      Rect bounds, {
      PdfTextAlignment alignment = PdfTextAlignment.left,
    }) {
      final format = PdfStringFormat(alignment: alignment);
      for (final offset in const <Offset>[
        Offset.zero,
        Offset(0.18, 0),
        Offset(0.36, 0),
        Offset(0.18, 0.12),
      ]) {
        graphics.drawString(
          text,
          italicFont,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            bounds.left + offset.dx,
            bounds.top + offset.dy,
            bounds.width,
            bounds.height,
          ),
          format: format,
        );
      }
    }

    // Rebuild this page completely so none of the hardcoded Word-template
    // values can survive in a separate content stream.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(
        0,
        0,
        page.getClientSize().width,
        page.getClientSize().height,
      ),
    );

    final boldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );
    graphics.drawString(
      'IN WITNESS WHEREOF, I/We have hereunto set my/our hand/s this ____ '
      'day of ________ 2026 at',
      boldFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(36, 28, 540, 16),
    );

    if (municipality.isNotEmpty) {
      graphics.drawRectangle(
        brush: whiteBrush,
        bounds: const Rect.fromLTWH(25, 40, 360, 24),
      );
      drawBoldItalic(
        'Municipality of $municipality.',
        const Rect.fromLTWH(36, 44, 340, 16),
      );
    }

    graphics.drawString(
      'Duly authorized to sign the Bid for and behalf of:',
      italicFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(36, 78, 360, 16),
    );
    drawBoldItalic(
      bidderName,
      const Rect.fromLTWH(36, 94, 360, 16),
    );

    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(25, 120, 370, 65),
    );
    drawBoldItalic(
      representative,
      const Rect.fromLTWH(36, 126, 350, 15),
    );
    graphics.drawString(
      'Authorized Representative',
      italicFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(36, 141, 350, 15),
    );
    drawBoldItalic(
      date,
      const Rect.fromLTWH(36, 156, 350, 15),
    );
  }

  static int _findBidSecuringDeclarationPage(PdfDocument document) {
    for (final line in PdfTextExtractor(document).extractTextLines()) {
      if (line.text.toUpperCase().contains('BID SECURING DECLARATION')) {
        return line.pageIndex;
      }
    }
    return -1;
  }

  static Future<void> _replaceBidSecuringDeclarationWithoutTable(
    PdfDocument document,
    Map<String, String> values,
  ) async {
    final declarationIndex = _findBidSecuringDeclarationPage(document);
    if (declarationIndex < 0) return;

    final templateData = await rootBundle.load(
      'assets/pdf/BID SECURING DECLARATION_impasugong_template.pdf',
    );
    final templateDocument = PdfDocument(
      inputBytes: templateData.buffer.asUint8List(),
    );
    // Extract placeholder positions before importing. Imported PDF pages are
    // drawn as templates, so their original text is not discoverable from the
    // destination document until after saving and reopening it.
    final List<dynamic> templateLines =
        PdfTextExtractor(templateDocument).extractTextLines();
    // This declaration uses only its first two sheets. The third sheet in the
    // supplied file is blank and must not be inserted into the bid documents.
    final declarationPageCount = templateDocument.pages.count.clamp(0, 2);

    // Replace placeholders on the source pages before turning them into PDF
    // templates. This keeps the extractor coordinates and the drawn content
    // in the same crop box, preventing duplicated/misaligned overlay text.
    _drawBidSecuringDeclarationTableDetails(
      templateDocument,
      values,
      startPageIndex: 0,
      pageCount: declarationPageCount,
      templateLines: templateLines,
    );

    // The original declaration occupies two sheets. Replace those sheets at
    // the same location so the remaining bid-document order is unchanged.
    document.pages.removeAt(declarationIndex);
    if (declarationIndex < document.pages.count) {
      document.pages.removeAt(declarationIndex);
    }

    for (var templateIndex = 0;
        templateIndex < declarationPageCount;
        templateIndex++) {
      final sourcePage = templateDocument.pages[templateIndex];
      final margins = PdfMargins()..all = 0;
      final targetPage = document.pages.insert(
        declarationIndex + templateIndex,
        sourcePage.size,
        margins,
      );
      if (templateIndex == 1) {
        // Keep the compact generated layout used by the no-table signature
        // sheet; only its selective emphasis follows the source template.
        _drawBidSecuringDeclarationWithoutTableLastPage(targetPage, values);
      } else {
        targetPage.graphics.drawPdfTemplate(
          sourcePage.createTemplate(),
          Offset.zero,
          sourcePage.size,
        );
      }
    }

    templateDocument.dispose();
  }

  static void _drawBidSecuringDeclarationWithoutTableLastPage(
    PdfPage page,
    Map<String, String> values,
  ) {
    final graphics = page.graphics;
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final bold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.bold,
    );
    final italic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.italic,
    );
    final municipality = (values['municipality'] ?? '').trim();
    final bidder = (values['bidderName'] ?? '').trim();
    final representative =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final yearParts = date.split(RegExp(r'\s+'));
    final year = yearParts.isEmpty ? '' : yearParts.last;

    void emphasized(String text, Rect bounds) {
      for (final offset in const <Offset>[
        Offset.zero,
        Offset(0.18, 0),
        Offset(0.36, 0),
        Offset(0.18, 0.12),
      ]) {
        graphics.drawString(
          text,
          italic,
          brush: black,
          bounds: Rect.fromLTWH(
            bounds.left + offset.dx,
            bounds.top + offset.dy,
            bounds.width,
            bounds.height,
          ),
        );
      }
    }

    double drawRuns(double left, double top, List<(String, PdfFont)> runs) {
      var currentLeft = left;
      const wordGap = 4.0;
      for (final run in runs) {
        final width = run.$2.measureString(run.$1).width;
        graphics.drawString(
          run.$1,
          run.$2,
          brush: black,
          bounds: Rect.fromLTWH(currentLeft, top, width + 2, 16),
        );
        // A standalone space can measure as zero in Syncfusion standard PDF
        // fonts. Use an explicit gap between differently styled word runs.
        currentLeft += width + wordGap;
      }
      return currentLeft;
    }

    graphics.drawString(
      'IN WITNESS WHEREOF, I/We have hereunto set my/our hand/s this ____ '
      'day of ________ $year at',
      bold,
      brush: black,
      bounds: const Rect.fromLTWH(55, 45, 500, 16),
    );
    emphasized(
      'Municipality of $municipality.',
      const Rect.fromLTWH(55, 61, 350, 16),
    );
    graphics.drawString(
      'Duly authorized to sign the Bid for and behalf of:',
      italic,
      brush: black,
      bounds: const Rect.fromLTWH(55, 105, 360, 16),
    );
    emphasized(bidder, const Rect.fromLTWH(55, 121, 360, 16));
    emphasized(representative, const Rect.fromLTWH(55, 169, 350, 16));
    graphics.drawString(
      'Authorized Representative',
      italic,
      brush: black,
      bounds: const Rect.fromLTWH(55, 185, 350, 16),
    );
    emphasized(date, const Rect.fromLTWH(55, 201, 350, 16));

    graphics.drawString(
      'JURAT',
      bold,
      brush: black,
      bounds: const Rect.fromLTWH(250, 245, 100, 18),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    final juratLeft = drawRuns(55, 292, <(String, PdfFont)>[
      ('SUBSCRIBED AND SWORN', regular),
      ('to before me this ____', regular),
      ('day of', bold),
      ('____', regular),
      (year, bold),
      ('at', regular),
    ]);
    emphasized(
      'Municipality of $municipality,',
      Rect.fromLTWH(juratLeft, 292, 555 - juratLeft, 16),
    );
    graphics.drawString(
      'Philippines. Affiant/s is/are personally known to me and was/were '
      'identified by me through competent',
      regular,
      brush: black,
      bounds: const Rect.fromLTWH(55, 308, 500, 16),
    );
    drawRuns(55, 324, <(String, PdfFont)>[
      ('evidence of identity', regular),
      ('as defined', regular),
      (
        'in the 2004 Rules on Notarial Practice (A.M. No. 02-8-13-SC). Affiant/s',
        regular
      ),
    ]);
    final nationalIdLeft = drawRuns(55, 340, <(String, PdfFont)>[
      ('exhibited to me his/her', regular),
    ]);
    emphasized(
      'National ID',
      Rect.fromLTWH(nationalIdLeft, 340, 70, 16),
    );
    drawRuns(nationalIdLeft + bold.measureString('National ID').width + 4,
        340, <(String, PdfFont)>[
      (
        'with his/her photograph and signature appearing thereon, with',
        regular,
      ),
    ]);
    graphics.drawString(
      'no. ________________________________.',
      regular,
      brush: black,
      bounds: const Rect.fromLTWH(55, 365, 350, 16),
    );
    graphics.drawString(
      'WITNESS MY HAND AND SEAL this ____ day of ________ $year.',
      bold,
      brush: black,
      bounds: const Rect.fromLTWH(55, 413, 430, 16),
    );

    const notaryTop = 500.0;
    final notaryBold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );
    for (final entry in <(String, double)>[
      ('NAME OF NOTARY PUBLIC', notaryTop),
      ('Notarial Commission No. __________', notaryTop + 24),
      ('Notary Public for ______ until ______', notaryTop + 48),
      ('Roll of Attorneys No. ______', notaryTop + 72),
      ('PTR No. ___,', notaryTop + 96),
      ('IBP No. ___,', notaryTop + 120),
    ]) {
      graphics.drawString(
        entry.$1,
        entry.$2 == notaryTop ? bold : notaryBold,
        brush: black,
        bounds: Rect.fromLTWH(385, entry.$2, 190, 15),
      );
    }
    for (final entry in <(String, double)>[
      ('Doc. No. ________', notaryTop + 118),
      ('Page No. ________', notaryTop + 142),
      ('Book No. ________', notaryTop + 166),
      ('Series of ________', notaryTop + 190),
    ]) {
      graphics.drawString(
        entry.$1,
        notaryBold,
        brush: black,
        bounds: Rect.fromLTWH(55, entry.$2, 180, 15),
      );
    }
  }

  static void _drawBidSecuringDeclarationTableDetails(
    PdfDocument document,
    Map<String, String> values, {
    required int startPageIndex,
    required int pageCount,
    required List<dynamic> templateLines,
  }) {
    final lines = templateLines
        .where((line) => line.pageIndex >= 0 && line.pageIndex < pageCount)
        .toList();
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final italicFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.italic,
    );
    final boldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.bold,
    );
    final referenceNumber = (values['referenceNumber'] ?? '').trim();
    final procuringEntity = (values['procuringEntity'] ?? '').trim();
    final municipality = (values['municipality'] ?? '').trim();
    final bidderName = (values['bidderName'] ?? '').trim();
    final representative =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final executionPlace = 'Municipality of $municipality';

    void drawEmphasized(PdfPage page, String text, Rect bounds) {
      for (final offset in const <Offset>[
        Offset.zero,
        Offset(0.18, 0),
        Offset(0.36, 0),
        Offset(0.18, 0.12),
      ]) {
        page.graphics.drawString(
          text,
          italicFont,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            bounds.left + offset.dx,
            bounds.top + offset.dy,
            bounds.width,
            bounds.height,
          ),
        );
      }
    }

    void replaceLine(
      dynamic line,
      String replacement, {
      PdfFont? font,
      double extraWidth = 8,
      double? coverHeight,
      double? drawHeight,
      double? coverWidth,
      bool emphasized = false,
    }) {
      final page = document.pages[startPageIndex + line.pageIndex as int];
      final bounds = line.bounds;
      final correctedTop = bounds.top;
      page.graphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(
          bounds.left - 2,
          correctedTop - 2,
          coverWidth ??
              (page.getClientSize().width - bounds.left - 20)
                  .clamp(bounds.width + extraWidth, 560)
                  .toDouble(),
          coverHeight ?? bounds.height + 5,
        ),
      );
      final drawBounds = Rect.fromLTWH(
        bounds.left,
        correctedTop,
        page.getClientSize().width - bounds.left - 20,
        drawHeight ?? bounds.height + 7,
      );
      if (emphasized) {
        drawEmphasized(page, replacement, drawBounds);
      } else {
        page.graphics.drawString(
          replacement,
          font ?? regularFont,
          brush: blackBrush,
          bounds: drawBounds,
        );
      }
    }

    for (final line in lines) {
      final text = line.text.trim();
      final upper = text.toUpperCase();
      if (upper.contains('MUNICIPALITY OF IMPASUGONG') &&
          upper.startsWith('MUNICIPALITY')) {
        // The municipality appears both in the page heading and on the line
        // immediately following "To:". Keep the heading as a place name,
        // while the recipient line must use the complete procuring entity.
        final isHeading = line.pageIndex == 0 && line.bounds.top < 130;
        final replacement = isHeading
            ? executionPlace.toUpperCase()
            : line.pageIndex == 0
                ? procuringEntity
                : executionPlace;
        replaceLine(
          line,
          replacement,
          font: boldFont,
          emphasized: !isHeading && line.pageIndex == 1,
          // Do not cover the closing parenthesis and "S.S." at the right of
          // the municipality heading.
          coverWidth: isHeading ? 260 : null,
        );
      } else if (upper.contains('PROJECT IDENTIFICATION NO')) {
        replaceLine(
          line,
          'Project Identification No.: $referenceNumber',
          font: italicFont,
        );
      } else if (upper.startsWith('TO:') &&
          upper.contains('MUNICIPALITY OF IMPASUGONG')) {
        replaceLine(line, 'To: $procuringEntity', font: boldFont);
      } else if (upper.startsWith('IN WITNESS WHEREOF')) {
        // Preserve the original witness sentence and writing lines. Its
        // municipality is a separate extracted line and is handled above.
        continue;
      } else if (upper.startsWith('SUBSCRIBED AND SWORN') &&
          upper.contains('MUNICIPALITY OF IMPASUGONG')) {
        // Preserve every original font run on the jurat sentence. Cover and
        // replace only its municipality, which is the sole variable phrase.
        final match = RegExp(
          'Municipality of Impasugong',
          caseSensitive: false,
        ).firstMatch(text)!;
        final page = document.pages[startPageIndex + line.pageIndex as int];
        final oldPlace = text.substring(match.start, match.end);
        final oldWidth = italicFont.measureString(oldPlace).width;
        // The municipality is the last phrase before the comma on this line;
        // anchor from the extracted right edge so earlier mixed bold runs do
        // not introduce horizontal measurement drift.
        final placeLeft =
            line.bounds.right - regularFont.measureString(',').width - oldWidth;
        page.graphics.drawRectangle(
          brush: whiteBrush,
          bounds: Rect.fromLTWH(
            placeLeft - 1,
            line.bounds.top - 2,
            oldWidth + 5,
            line.bounds.height + 5,
          ),
        );
        drawEmphasized(
          page,
          executionPlace,
          Rect.fromLTWH(
            placeLeft,
            line.bounds.top,
            page.getClientSize().width - placeLeft - 20,
            line.bounds.height + 7,
          ),
        );
      }
    }

    dynamic dulyLine;
    for (final line in lines) {
      if (line.text.toUpperCase().contains('DULY AUTHORIZED TO SIGN THE BID')) {
        dulyLine = line;
        break;
      }
    }
    if (dulyLine != null) {
      final page = document.pages[startPageIndex + dulyLine.pageIndex as int];
      final top = dulyLine.bounds.top + 24;
      page.graphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(45, top - 12, 360, 125),
      );
      drawEmphasized(page, bidderName, Rect.fromLTWH(55, top, 330, 17));
      drawEmphasized(
        page,
        representative,
        Rect.fromLTWH(55, top + 50, 330, 17),
      );
      page.graphics.drawString(
        'Authorized Representative',
        italicFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(55, top + 67, 330, 17),
      );
      drawEmphasized(page, date, Rect.fromLTWH(55, top + 84, 330, 17));
    }
  }

  static void _drawTechnicalSpecificationsSignature(
    PdfPage page,
    Map<String, String> values,
  ) {
    final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
    final date = (values['date'] ?? '').trim();
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final captionFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);

    // Replace only the old values, keeping the template's labels, colons,
    // designation and firm rows intact.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(175, 516, 300, 36),
    );
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(175, 582, 220, 22),
    );
    graphics.drawString(
      submittedBy,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(180, 520, 285, 18),
    );
    final nameWidth =
        valueFont.measureString(submittedBy).width.clamp(0, 285).toDouble();
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: 0.5),
      const Offset(180, 535),
      Offset(180 + nameWidth, 535),
    );
    graphics.drawString(
      '(Printed Name & Signature)',
      captionFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(180, 537, 210, 14),
    );
    graphics.drawString(
      date,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(180, 586, 180, 18),
    );
  }

  static int _drawTechnicalSpecifications(
    PdfDocument document,
    Map<String, String> values,
  ) {
    List<dynamic> specifications = const [];
    final encodedSpecifications = values['technicalSpecifications'] ?? '';
    if (encodedSpecifications.isNotEmpty) {
      final decoded = jsonDecode(encodedSpecifications);
      if (decoded is List) specifications = decoded.take(72).toList();
    }

    // A single equipment item may contain many newline-separated details.
    // Split it into continuation rows so readable text can flow to the next
    // Technical Specifications page instead of being shrunk or clipped.
    final renderRows = <Map<String, dynamic>>[];
    for (var sourceIndex = 0;
        sourceIndex < specifications.length;
        sourceIndex++) {
      final source = specifications[sourceIndex] is Map
          ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
          : <String, dynamic>{};
      final addedLines = (source['specification'] ?? '')
          .toString()
          .replaceAll('\u2029', '\n\n')
          .split(RegExp(r'\r?\n\s*\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final chunks = addedLines.isEmpty
          ? <List<String>>[
              <String>[''],
            ]
          : <List<String>>[
              for (final line in addedLines) <String>[line],
            ];
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        renderRows.add(<String, dynamic>{
          ...source,
          'specification': chunks[chunkIndex].join('\n'),
          '_itemNumber': sourceIndex + 1,
          '_continuation': chunkIndex > 0,
          if (chunkIndex > 0) 'quantity': '',
          if (chunkIndex > 0) 'unit': '',
          if (chunkIndex > 0) 'parameter': '',
        });
      }
    }

    final hasAnyParameter = renderRows.any(
      (row) => (row['parameter'] ?? '').toString().trim().isNotEmpty,
    );
    // When no item has an optional parameter, remove that column completely
    // and share its width between Specification and Statement of Compliance.
    final columns = hasAnyParameter
        ? <double>[36, 94, 270, 335, 400, 490, 576]
        : <double>[36, 94, 325, 390, 455, 576];
    final projectTitle = (values['projectTitle'] ?? '').trim().toUpperCase();
    var currentTitleLine = '';
    var titleLineCount = 0;
    for (final word in projectTitle.split(RegExp(r'\s+'))) {
      final candidate =
          currentTitleLine.isEmpty ? word : '$currentTitleLine $word';
      if (currentTitleLine.isNotEmpty && candidate.length > 42) {
        titleLineCount++;
        currentTitleLine = word;
      } else {
        currentTitleLine = candidate;
      }
    }
    if (currentTitleLine.isNotEmpty) titleLineCount++;
    if (titleLineCount == 0) titleLineCount = 1;
    final technicalHeaderFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final technicalHeaderLineHeight =
        technicalHeaderFont.measureString('Ag').height;
    final referenceTop = 88 + titleLineCount * technicalHeaderLineHeight + 4;
    final statementTop = (referenceTop + 30).clamp(125.0, 180.0).toDouble();
    const statementTitleHeight = 24.0;
    const statementBodyHeight = 165.0;
    final firstTableTop =
        statementTop + statementTitleHeight + statementBodyHeight;
    const headerHeight = 50.0;
    const minimumRowHeight = 18.0;
    const signatureSpace = 125.0;
    final firstPage = document.pages[46];
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
    // Match the clearly readable body-text size used by the source template.
    // The compliance value keeps its existing bold styling and size below.
    final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final boldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final statementTitleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final statementBodyFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final statementEmphasisFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final specificationFormat = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.word,
    );
    final specificationWidth = columns[2] - columns[1] - 6;
    final parameterWidth = hasAnyParameter ? columns[5] - columns[4] - 6 : 0.0;
    final rowHeights = <double>[
      for (final value in renderRows)
        (() {
          final specification =
              value is Map ? (value['specification'] ?? '').toString() : '';
          final parameter =
              value is Map ? (value['parameter'] ?? '').toString() : '';
          final measuredSpecification = regularFont.measureString(
            specification.replaceAll(
              RegExp(r'^\s*[✓•○■➢]\s*', multiLine: true),
              '  ',
            ),
            layoutArea: Size(specificationWidth, 500),
            format: specificationFormat,
          );
          final measuredParameter = hasAnyParameter
              ? regularFont.measureString(
                  parameter,
                  layoutArea: Size(parameterWidth, 500),
                  format: specificationFormat,
                )
              : Size.zero;
          final contentHeight =
              measuredSpecification.height > measuredParameter.height
                  ? measuredSpecification.height
                  : measuredParameter.height;
          return (contentHeight + 8).clamp(minimumRowHeight, 245).toDouble();
        })(),
    ];
    final pageRowCounts = <int>[];
    var rowsOnCurrentPage = 0;
    var usedHeight = 0.0;
    var technicalPageForLayout = 0;
    for (var rowIndex = 0; rowIndex < rowHeights.length; rowIndex++) {
      final height = rowHeights[rowIndex];
      final page = document.pages[46 + technicalPageForLayout];
      final tableTop = technicalPageForLayout == 0 ? firstTableTop : 36.0;
      final availableHeight = page.getClientSize().height -
          tableTop -
          headerHeight -
          signatureSpace;
      if (rowsOnCurrentPage > 0 &&
          usedHeight + height > availableHeight &&
          technicalPageForLayout < 2) {
        pageRowCounts.add(rowsOnCurrentPage);
        technicalPageForLayout++;
        rowsOnCurrentPage = 0;
        usedHeight = 0;
      }
      rowsOnCurrentPage++;
      usedHeight += height;
    }
    pageRowCounts.add(rowsOnCurrentPage);
    final pageCount = pageRowCounts.length;
    var itemIndex = 0;

    const statementText =
        'Bidders must state here either “Comply” or “Not Comply” against each '
        'of the individual parameters of each Specification stating the '
        'corresponding performance parameter of the equipment offered. '
        'Statements of “Comply” or “Not Comply” must be supported by evidence '
        'in a Bidders Bid and cross-referenced to that evidence. Evidence shall '
        'be in the form of manufacturers’ un-amended sales literature, '
        'unconditional statements of specification and compliance issued by '
        'the manufacturer, samples, independent test data etc. as appropriate. '
        'A statement that is not supported by evidence or is subsequently '
        'found to be contradicted by the evidence presented will render the Bid '
        'under evaluation liable for rejection. A statement either in the '
        'Bidders statement of compliance or the supporting evidence that is '
        'found to be false either during Bid evaluation, post qualification or '
        'the execution of the Contract may be regarded as fraudulent and render '
        'the Bidder or supplier liable for prosecution subject to the provisions of';
    const statementBoldItb = 'ITB';
    const statementRegularClause = 'Clause';
    const statementFirstBoldText = 'Error! Reference source not found';
    const statementRegularConnector = 'and/or GCC Clause';
    const statementSecondBoldText = 'Error! Reference source not found.';

    // Rebuild the statement and table as one shared bordered structure.
    firstPage.graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(
        columns.first - 2,
        statementTop - 2,
        columns.last - columns.first + 4,
        firstPage.getClientSize().height - statementTop + 2,
      ),
    );
    firstPage.graphics.drawRectangle(
      pen: gridPen,
      bounds: Rect.fromLTWH(
        columns.first,
        statementTop,
        columns.last - columns.first,
        statementTitleHeight + statementBodyHeight,
      ),
    );
    firstPage.graphics.drawLine(
      gridPen,
      Offset(columns.first, statementTop + statementTitleHeight),
      Offset(columns.last, statementTop + statementTitleHeight),
    );
    firstPage.graphics.drawString(
      'Statement of Compliance',
      statementTitleFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(
        columns.first + 6,
        statementTop + 4,
        columns.last - columns.first - 12,
        statementTitleHeight - 8,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.middle,
      ),
    );
    // Lay out the regular paragraph and bold clause as one continuous flow.
    // Separate drawString boxes introduce a visible gap and can split the GCC
    // phrase, so words are wrapped together while retaining their own fonts.
    final statementWords = <({String text, PdfFont font})>[
      for (final word in statementText.split(RegExp(r'\s+')))
        (text: word, font: statementBodyFont),
      for (final word in statementBoldItb.split(RegExp(r'\s+')))
        (text: word, font: statementEmphasisFont),
      for (final word in statementRegularClause.split(RegExp(r'\s+')))
        (text: word, font: statementBodyFont),
      for (final word in statementFirstBoldText.split(RegExp(r'\s+')))
        (text: word, font: statementEmphasisFont),
      for (final word in statementRegularConnector.split(RegExp(r'\s+')))
        (text: word, font: statementBodyFont),
      for (final word in statementSecondBoldText.split(RegExp(r'\s+')))
        (text: word, font: statementEmphasisFont),
    ];
    final statementLines = <List<({String text, PdfFont font})>>[];
    var currentLine = <({String text, PdfFont font})>[];
    var currentWidth = 0.0;
    final statementLeft = columns.first + 6;
    final statementWidth = columns.last - columns.first - 12;
    // Syncfusion's standard-font measurement can report a zero-width string
    // for a standalone space. Use the Times Roman 12pt visual space width so
    // individually rendered words never touch each other.
    const spaceWidth = 3.4;

    for (final word in statementWords) {
      final wordWidth = word.font.measureString(word.text).width;
      final candidateWidth =
          currentWidth + (currentLine.isEmpty ? 0 : spaceWidth) + wordWidth;
      if (currentLine.isNotEmpty && candidateWidth > statementWidth) {
        statementLines.add(currentLine);
        currentLine = <({String text, PdfFont font})>[word];
        currentWidth = wordWidth;
      } else {
        currentLine.add(word);
        currentWidth = candidateWidth;
      }
    }
    if (currentLine.isNotEmpty) statementLines.add(currentLine);

    final lineHeight = statementBodyFont.measureString('Ag').height + 0.6;
    var statementY = statementTop + statementTitleHeight + 7;
    for (var lineIndex = 0; lineIndex < statementLines.length; lineIndex++) {
      final line = statementLines[lineIndex];
      final wordsWidth = line.fold<double>(
        0,
        (total, word) => total + word.font.measureString(word.text).width,
      );
      final isLastLine = lineIndex == statementLines.length - 1;
      final calculatedGap = line.length <= 1
          ? 0.0
          : isLastLine
              ? spaceWidth
              : (statementWidth - wordsWidth) / (line.length - 1);
      final gapWidth = line.length <= 1
          ? 0.0
          : calculatedGap.clamp(spaceWidth, spaceWidth * 2.5).toDouble();
      var statementX = statementLeft;
      for (var wordIndex = 0; wordIndex < line.length; wordIndex++) {
        final word = line[wordIndex];
        final wordWidth = word.font.measureString(word.text).width;
        firstPage.graphics.drawString(
          word.text,
          word.font,
          brush: blackBrush,
          bounds:
              Rect.fromLTWH(statementX, statementY, wordWidth + 4, lineHeight),
        );
        statementX += wordWidth;
        if (wordIndex < line.length - 1) statementX += gapWidth;
      }
      statementY += lineHeight;
    }

    for (var technicalPage = 0; technicalPage < pageCount; technicalPage++) {
      final page = document.pages[46 + technicalPage];
      final pageSize = page.getClientSize();
      final tableTop = technicalPage == 0 ? firstTableTop : 36.0;
      final rowsOnPage = pageRowCounts[technicalPage];
      final pageStartItemIndex = itemIndex;
      final tableRowsHeight = rowHeights
          .skip(pageStartItemIndex)
          .take(rowsOnPage)
          .fold<double>(0, (total, height) => total + height);
      final tableBottom = tableTop + headerHeight + tableRowsHeight;

      // Remove the fixed template rows and its old signature block.
      page.graphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(
          28,
          tableTop,
          pageSize.width - 56,
          pageSize.height - tableTop,
        ),
      );

      for (final x in columns) {
        page.graphics.drawLine(
          gridPen,
          Offset(x, tableTop),
          Offset(x, tableBottom),
        );
      }
      var horizontalY = tableTop;
      page.graphics.drawLine(
        gridPen,
        Offset(columns.first, horizontalY),
        Offset(columns.last, horizontalY),
      );
      horizontalY += headerHeight;
      page.graphics.drawLine(
        gridPen,
        Offset(columns.first, horizontalY),
        Offset(columns.last, horizontalY),
      );
      for (var row = 0; row < rowsOnPage; row++) {
        horizontalY += rowHeights[pageStartItemIndex + row];
        final currentIndex = pageStartItemIndex + row;
        final currentItem = '${renderRows[currentIndex]['_itemNumber']}';
        final nextItem = currentIndex + 1 < renderRows.length
            ? '${renderRows[currentIndex + 1]['_itemNumber']}'
            : null;
        final isInternalItemLine = currentItem == nextItem;
        if (isInternalItemLine) {
          // Keep Item No., Qty, and Unit visually merged for all lines under
          // one item. Only Specification (and optional Parameter) plus
          // Compliance receive a separator for every added line.
          page.graphics.drawLine(
            gridPen,
            Offset(columns[1], horizontalY),
            Offset(columns[2], horizontalY),
          );
          if (hasAnyParameter) {
            page.graphics.drawLine(
              gridPen,
              Offset(columns[4], horizontalY),
              Offset(columns[5], horizontalY),
            );
          }
          page.graphics.drawLine(
            gridPen,
            Offset(columns[columns.length - 2], horizontalY),
            Offset(columns.last, horizontalY),
          );
        } else {
          page.graphics.drawLine(
            gridPen,
            Offset(columns.first, horizontalY),
            Offset(columns.last, horizontalY),
          );
        }
      }

      final headers = <String>[
        'Item\nNo.',
        'Specification/s',
        'Qty',
        'Unit',
        if (hasAnyParameter) 'Parameter',
        'Statement\nof\nCompliance',
      ];
      for (var column = 0; column < headers.length; column++) {
        page.graphics.drawString(
          headers[column],
          boldFont,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            columns[column] + 3,
            tableTop + 2,
            columns[column + 1] - columns[column] - 6,
            headerHeight - 4,
          ),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
            wordWrap: PdfWordWrapType.word,
          ),
        );
      }

      var rowTop = tableTop + headerHeight;
      for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
        final specification = renderRows[itemIndex];
        final isContinuation = specification['_continuation'] == true;
        final itemNumber = '${specification['_itemNumber']}';
        final previousItemNumber = itemIndex == 0
            ? null
            : '${renderRows[itemIndex - 1]['_itemNumber']}';
        final texts = <String>[
          isContinuation || itemNumber == previousItemNumber ? '' : itemNumber,
          (specification['specification'] ?? '').toString(),
          (specification['quantity'] ?? '').toString(),
          (specification['unit'] ?? '').toString(),
          if (hasAnyParameter) (specification['parameter'] ?? '').toString(),
          'COMPLY',
        ];
        final rowHeight = rowHeights[itemIndex];
        for (var column = 0; column < texts.length; column++) {
          final isMergedColumn = column == 0 || column == 2 || column == 3;
          if (isMergedColumn && itemNumber == previousItemNumber) continue;
          var cellHeight = rowHeight - 2;
          if (isMergedColumn) {
            for (var next = itemIndex + 1;
                next < pageStartItemIndex + rowsOnPage &&
                    '${renderRows[next]['_itemNumber']}' == itemNumber;
                next++) {
              cellHeight += rowHeights[next];
            }
          }
          final cellBounds = Rect.fromLTWH(
            columns[column] + 3,
            rowTop + 1,
            columns[column + 1] - columns[column] - 6,
            cellHeight,
          );
          if (column == 1) {
            _drawMarkedSpecificationText(
              page.graphics,
              texts[column],
              regularFont,
              blackBrush,
              cellBounds,
            );
          } else {
            page.graphics.drawString(
              texts[column],
              column == texts.length - 1 ? boldFont : regularFont,
              brush: blackBrush,
              bounds: cellBounds,
              format: PdfStringFormat(
                alignment: PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle,
                wordWrap: PdfWordWrapType.word,
              ),
            );
          }
        }
        rowTop += rowHeight;
      }

      if (technicalPage == pageCount - 1) {
        _drawTechnicalSpecificationsSignatureAt(
          page,
          values,
          tableBottom + 22,
        );
      }
    }

    return pageCount;
  }

  static void _drawTechnicalSpecificationsSignatureAt(
    PdfPage page,
    Map<String, String> values,
    double top,
  ) {
    final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
    final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
    final date = (values['date'] ?? '').trim();
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 14);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.bold,
    );
    final captionFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    // Match the formal signature grid used by the contract-statement pages.
    const labelLeft = 36.0;
    const colonLeft = 130.0;
    const valueLeft = 165.0;

    void drawRow(String label, String value, double y) {
      page.graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(labelLeft, y, 90, 22),
      );
      page.graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(colonLeft, y, 10, 22),
      );
      page.graphics.drawString(
        value,
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(valueLeft, y, 360, 22),
      );
    }

    drawRow('Submitted by', submittedBy, top);
    final nameWidth =
        valueFont.measureString(submittedBy).width.clamp(0, 360).toDouble();
    page.graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: 0.5),
      Offset(valueLeft, top + 18),
      Offset(valueLeft + nameWidth, top + 18),
    );
    page.graphics.drawString(
      '(Printed Name & Signature)',
      captionFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(valueLeft, top + 22, 230, 17),
    );
    drawRow('Designation', 'Authorized Representative', top + 45);
    drawRow('Name of Firm', bidderName, top + 70);
    drawRow('Date', date, top + 95);
  }

  static int _drawPriceSchedule(
    PdfDocument document,
    Map<String, String> values,
    int startPageIndex,
  ) {
    List<dynamic> specifications = const [];
    List<dynamic> savedPrices = const [];
    final encodedSpecifications = values['technicalSpecifications'] ?? '';
    final encodedPrices = values['priceSchedule'] ?? '';
    if (encodedSpecifications.isNotEmpty) {
      final decoded = jsonDecode(encodedSpecifications);
      if (decoded is List) specifications = decoded.take(72).toList();
    }
    if (encodedPrices.isNotEmpty) {
      final decoded = jsonDecode(encodedPrices);
      if (decoded is List) savedPrices = decoded.take(72).toList();
    }

    double number(dynamic value) =>
        double.tryParse((value ?? '').toString().replaceAll(',', '').trim()) ??
        0;
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      final grouped = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return '$grouped.${parts.last}';
    }

    List<String> priceSpecificationLines(dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return <String>[''];
      final result = text
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      return result.isEmpty ? <String>[''] : result;
    }

    final priceRows = <Map<String, dynamic>>[];
    for (var sourceIndex = 0;
        sourceIndex < specifications.length;
        sourceIndex++) {
      final source = specifications[sourceIndex] is Map
          ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
          : <String, dynamic>{};
      final lines = priceSpecificationLines(source['specification']);
      for (var start = 0; start < lines.length; start += 14) {
        final continuation = start > 0;
        priceRows.add(<String, dynamic>{
          ...source,
          '_sourceIndex': sourceIndex,
          '_itemNumber': sourceIndex + 1,
          '_continuation': continuation,
          '_descriptionLines': lines.skip(start).take(14).toList(),
          if (continuation) 'quantity': '',
          if (continuation) 'unit': '',
        });
      }
    }

    final itemHeights = <double>[
      for (final row in priceRows)
        ((row['_descriptionLines'] as List).length * 17.0 + 8.0)
            .clamp(34.0, 260.0)
            .toDouble(),
    ];
    final pageRowCounts = <int>[];
    var nextItem = 0;
    while (nextItem < priceRows.length) {
      var usedHeight = 0.0;
      var count = 0;
      while (nextItem + count < priceRows.length) {
        final height = itemHeights[nextItem + count];
        if (count > 0 && usedHeight + height > 260) break;
        usedHeight += height;
        count++;
      }
      pageRowCounts.add(count);
      nextItem += count;
    }
    if (pageRowCounts.isEmpty) pageRowCounts.add(0);
    final pageCount = pageRowCounts.length;

    // The source document provides eight Price Schedule sheets. When the
    // entered specifications need more than those templates, insert clean
    // continuation pages immediately after them instead of clipping rows or
    // drawing over the total/signature block.
    const bundledPriceSchedulePages = 8;
    if (pageCount > bundledPriceSchedulePages) {
      final sourceSize = document.pages[startPageIndex].size;
      for (var extraPage = bundledPriceSchedulePages;
          extraPage < pageCount;
          extraPage++) {
        document.pages.insert(
          startPageIndex + extraPage,
          sourceSize,
          PdfMargins()..all = 0,
        );
      }
    }
    const baseColumns = <double>[
      24,
      52,
      158,
      195,
      226,
      258,
      306,
      365,
      422,
      470,
      526,
      582
    ];
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final red = PdfSolidBrush(PdfColor(220, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final priceDescriptionFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final priceBold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final detailFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final detailBoldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final titleFont =
        PdfStandardFont(PdfFontFamily.timesRoman, 13, style: PdfFontStyle.bold);
    var itemIndex = 0;
    var grandTotal = 0.0;

    for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final page = document.pages[startPageIndex + pageNumber];
      final size = page.getClientSize();
      const horizontalMargin = 36.0;
      final tableWidth = size.width - horizontalMargin * 2;
      final baseWidth = baseColumns.last - baseColumns.first;
      final columns = <double>[
        for (final baseX in baseColumns)
          horizontalMargin +
              ((baseX - baseColumns.first) / baseWidth) * tableWidth,
      ];
      page.graphics.drawRectangle(
          brush: white, bounds: Rect.fromLTWH(0, 0, size.width, size.height));
      var tableTop = 35.0;
      if (pageNumber == 0) {
        page.graphics.drawString('PRICE SCHEDULE FOR GOODS', titleFont,
            brush: black,
            bounds: Rect.fromLTWH(
              horizontalMargin,
              25,
              tableWidth,
              22,
            ),
            format: PdfStringFormat(alignment: PdfTextAlignment.center));
        page.graphics.drawLine(
          PdfPen(PdfColor(0, 0, 0), width: .7),
          const Offset(horizontalMargin, 50),
          Offset(size.width - horizontalMargin, 50),
        );
        final bidder = (values['bidderName'] ?? '').trim().toUpperCase();
        final reference = (values['referenceNumber'] ?? '').trim();
        const bidderLabel = 'Name of Bidder:';
        final bidderValueLeft =
            horizontalMargin + detailFont.measureString(bidderLabel).width + 3;
        page.graphics.drawString(
          bidderLabel,
          detailFont,
          brush: black,
          bounds: Rect.fromLTWH(horizontalMargin, 58, 120, 17),
        );
        page.graphics.drawString(
          bidder,
          detailBoldFont,
          brush: black,
          bounds: Rect.fromLTWH(bidderValueLeft, 58, tableWidth * .35, 17),
        );
        final bidderWidth =
            detailBoldFont.measureString(bidder).width.clamp(0, 220).toDouble();
        page.graphics.drawLine(
          PdfPen(PdfColor(0, 0, 0), width: 0.5),
          Offset(bidderValueLeft, 73),
          Offset(bidderValueLeft + bidderWidth, 73),
        );

        final projectLabelLeft = horizontalMargin + tableWidth * .53;
        const projectLabel = 'Project ID No.:';
        final projectValueLeft =
            projectLabelLeft + detailFont.measureString(projectLabel).width + 3;
        page.graphics.drawString(
          projectLabel,
          detailFont,
          brush: black,
          bounds: Rect.fromLTWH(projectLabelLeft, 58, 120, 17),
        );
        page.graphics.drawString(
          reference,
          detailBoldFont,
          brush: black,
          bounds: Rect.fromLTWH(projectValueLeft, 58, 100, 17),
        );
        final referenceWidth = detailBoldFont
            .measureString(reference)
            .width
            .clamp(0, 100)
            .toDouble();
        page.graphics.drawLine(
          PdfPen(PdfColor(0, 0, 0), width: 0.5),
          Offset(projectValueLeft, 73),
          Offset(projectValueLeft + referenceWidth, 73),
        );
        page.graphics.drawString(
            'Pricing Details for Goods Offered from Within the Philippines',
            detailFont,
            brush: black,
            bounds: Rect.fromLTWH(
              horizontalMargin,
              77,
              tableWidth * .70,
              17,
            ));
        tableTop = 96;
      }
      const headerHeight = 92.0;
      final rowCount = pageRowCounts[pageNumber];
      final pageStartItem = itemIndex;
      final contentHeight = rowCount == 0
          ? 30.0
          : itemHeights
              .skip(pageStartItem)
              .take(rowCount)
              .fold<double>(0, (sum, height) => sum + height);
      final tableBottom = tableTop + headerHeight + contentHeight;
      for (final x in columns) {
        page.graphics
            .drawLine(gridPen, Offset(x, tableTop), Offset(x, tableBottom));
      }
      page.graphics.drawLine(gridPen, Offset(columns.first, tableTop),
          Offset(columns.last, tableTop));
      page.graphics.drawLine(
          gridPen,
          Offset(columns.first, tableTop + headerHeight),
          Offset(columns.last, tableTop + headerHeight));
      const headers = <String>[
        'Item\nNo.',
        'Specification/s',
        'Country\nof Origin',
        'Qty',
        'Unit',
        'Unit\nPrice/Item',
        'Transportation &\nInsurance and All Other\nCosts Incidental to\ndelivery per Item',
        'Sales & Other\nTaxes Payable if\nContract is Awarded\nper Item',
        'Cost of Incidental\nServices, if applicable,\nper Item',
        'Total Price per Unit\n(columns 5+6+7+8)\n(100%)',
        'Total Price Delivered\nFinal Destination'
      ];
      for (var column = 0; column < headers.length; column++) {
        page.graphics.drawString(headers[column], bold,
            brush: black,
            bounds: Rect.fromLTWH(columns[column] + 2, tableTop + 2,
                columns[column + 1] - columns[column] - 4, headerHeight - 4),
            format: PdfStringFormat(
                alignment: PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle,
                wordWrap: PdfWordWrapType.word));
      }
      var y = tableTop + headerHeight;
      for (var row = 0; row < rowCount; row++, itemIndex++) {
        final rowHeight = itemHeights[itemIndex];
        final specification = priceRows[itemIndex];
        final sourceIndex = specification['_sourceIndex'] as int;
        final isContinuation = specification['_continuation'] == true;
        final saved =
            sourceIndex < savedPrices.length && savedPrices[sourceIndex] is Map
                ? savedPrices[sourceIndex] as Map
                : const {};
        final total =
            (number(saved['totalPricePerUnit']) - number(saved['deduction']))
                .clamp(0, double.infinity)
                .toDouble();
        final quantityText = isContinuation
            ? ''
            : (specification['quantity'] ?? '').toString().trim().isEmpty
                ? '1'
                : specification['quantity'].toString();
        final unitText = isContinuation
            ? ''
            : (specification['unit'] ?? '').toString().trim().isEmpty
                ? 'unit'
                : specification['unit'].toString();
        final quantity = number(quantityText);
        final delivered = (quantity * total).roundToDouble();
        if (!isContinuation) grandTotal += delivered;
        final texts = <String>[
          isContinuation ? '' : '${specification['_itemNumber']}',
          '',
          isContinuation ? '' : 'PHL',
          quantityText,
          unitText,
          isContinuation ? '' : money(total * .50),
          isContinuation ? '' : money(total * .20),
          isContinuation ? '' : money(total * .30),
          '',
          isContinuation ? '' : money(total),
          isContinuation ? '' : money(delivered),
        ];
        for (var column = 0; column < texts.length; column++) {
          if (column == 1) continue;
          final isPriceColumn = column >= 5;
          page.graphics.drawString(
              texts[column], isPriceColumn ? priceBold : regular,
              brush: column == 2 || column == 10 ? red : black,
              bounds: Rect.fromLTWH(columns[column] + 2, y + 1,
                  columns[column + 1] - columns[column] - 4, rowHeight - 2),
              format: PdfStringFormat(
                  alignment: column == 1
                      ? PdfTextAlignment.left
                      : PdfTextAlignment.center,
                  lineAlignment: PdfVerticalAlignment.middle,
                  wordWrap: PdfWordWrapType.word));
        }

        final descriptionLines =
            (specification['_descriptionLines'] as List).cast<String>();
        _drawMarkedSpecificationText(
          page.graphics,
          descriptionLines.join('\n'),
          priceDescriptionFont,
          black,
          Rect.fromLTWH(
            columns[1] + 3,
            y + 3,
            columns[2] - columns[1] - 6,
            rowHeight - 6,
          ),
        );
        y += rowHeight;
        page.graphics.drawLine(
            gridPen, Offset(columns.first, y), Offset(columns.last, y));
      }
      if (pageNumber == pageCount - 1) {
        const totalRowHeight = 18.0;
        final totalBottom = y + totalRowHeight;
        page.graphics.drawLine(
          gridPen,
          Offset(columns.first, totalBottom),
          Offset(columns.last, totalBottom),
        );
        for (final x in <double>[
          columns.first,
          columns[9],
          columns[10],
          columns.last
        ]) {
          page.graphics.drawLine(gridPen, Offset(x, y), Offset(x, totalBottom));
        }
        page.graphics.drawString(
          'TOTAL',
          bold,
          brush: black,
          bounds: Rect.fromLTWH(
            columns[9] + 2,
            y + 1,
            columns[10] - columns[9] - 4,
            totalRowHeight - 2,
          ),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );
        page.graphics.drawString(
          money(grandTotal),
          bold,
          brush: red,
          bounds: Rect.fromLTWH(
            columns[10] + 2,
            y + 1,
            columns[11] - columns[10] - 4,
            totalRowHeight - 2,
          ),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );
        _drawTechnicalSpecificationsSignatureAt(
          page,
          values,
          totalBottom + 28,
        );
      }
    }
    return pageCount;
  }

  static int _findPriceScheduleStartPage(PdfDocument document) {
    final lines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: 46,
      endPageIndex: 61.clamp(0, document.pages.count - 1).toInt(),
    );
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('PRICE SCHEDULE FOR GOODS') ||
          text.contains('PAGE 1 OF 8')) {
        return line.pageIndex;
      }
    }
    return document.pages.count > 49 ? 49 : -1;
  }

  static void _drawManpowerSignature(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final lines = PdfTextExtractor(document).extractTextLines();
    int? pageIndex;
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('LIST OF MANPOWER')) {
        pageIndex = line.pageIndex;
        break;
      }
    }
    if (pageIndex == null) return;

    final page = document.pages[pageIndex];
    final pageLines = lines
        .where((line) => line.pageIndex == pageIndex)
        .toList(growable: false);
    // Keep the List of Manpower letterhead consistent with the AFS and
    // Product Warranty pages.
    _replaceCertificateHeaderAddress(page, pageLines);
    TextLine? submittedLabel;
    for (final line in pageLines) {
      final text =
          line.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      // The source sometimes encodes the label, colon, and old value as one
      // text line, so matching the complete extracted string is unreliable.
      if (text.contains('SUBMITTED BY')) {
        submittedLabel = line;
        break;
      }
    }
    if (submittedLabel == null) return;

    final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
    final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
    final date = (values['date'] ?? '').trim();
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 14);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.bold,
    );
    final captionFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final top = submittedLabel.bounds.top - 2;
    final labelLeft = submittedLabel.bounds.left;
    final colonLeft = labelLeft + 108;
    final valueLeft = labelLeft + 145;
    final clearRight = page.getClientSize().width - 28;

    page.graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        labelLeft - 3,
        top - 2,
        clearRight - labelLeft + 3,
        132,
      ),
    );

    void drawRow(String label, String value, double y) {
      page.graphics.drawString(
        label,
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(labelLeft, y, 105, 22),
      );
      page.graphics.drawString(
        ':',
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(colonLeft, y, 10, 22),
      );
      page.graphics.drawString(
        value,
        valueFont,
        brush: black,
        bounds: Rect.fromLTWH(valueLeft, y, clearRight - valueLeft, 22),
      );
    }

    drawRow('Submitted by', submittedBy, top);
    final nameWidth = valueFont
        .measureString(submittedBy)
        .width
        .clamp(0, clearRight - valueLeft)
        .toDouble();
    page.graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: .5),
      Offset(valueLeft, top + 18),
      Offset(valueLeft + nameWidth, top + 18),
    );
    page.graphics.drawString(
      '(Printed Name & Signature)',
      captionFont,
      brush: black,
      bounds: Rect.fromLTWH(valueLeft, top + 22, 230, 17),
    );
    drawRow('Designation', 'Authorized Representative', top + 45);
    drawRow('Name of Firm', bidderName, top + 70);
    drawRow('Date', date, top + 95);
  }

  static int _findPageContaining(
    PdfDocument document,
    List<String> phrases,
  ) {
    final lines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: 0,
      endPageIndex: document.pages.count - 1,
    );
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (phrases.any((phrase) => text.contains(phrase))) {
        return line.pageIndex;
      }
    }
    return -1;
  }

  static int _findOmnibusSwornStatementPage(PdfDocument document) {
    final extractor = PdfTextExtractor(document);
    // The template has stale Omnibus text embedded on its cover page. The
    // actual legal form is in the latter half of the document.
    for (var pageIndex = document.pages.count ~/ 2;
        pageIndex < document.pages.count;
        pageIndex++) {
      final text = extractor
          .extractText(
            startPageIndex: pageIndex,
            endPageIndex: pageIndex,
          )
          .toUpperCase();
      // The source encodes the title as "O MNIBUS S WORN S TATEMENT".
      // Removing whitespace gives one stable, page-specific marker.
      final compactText = text.replaceAll(RegExp(r'\s+'), '');
      if (compactText.contains('OMNIBUSSWORNSTATEMENT')) {
        return pageIndex;
      }
    }
    return -1;
  }

  static void _drawOmnibusSwornStatementIdentity(
    PdfDocument document,
    Map<String, String> values, {
    required int pageIndex,
  }) {
    final selectedName = (values['submittedBy'] ?? '').trim().toUpperCase();
    var formalName = (values['submittedByFormalName'] ?? '').trim();
    var civilStatus =
        (values['submittedByCivilStatus'] ?? '').trim().toLowerCase();
    var address = (values['submittedByAddress'] ?? '').trim();
    if (selectedName.contains('CARLOS RAFAEL A. JAMILO')) {
      formalName = formalName.isEmpty ? 'Carlos Rafael A. Jamilo' : formalName;
      civilStatus = civilStatus.isEmpty ? 'single' : civilStatus;
      address = address.isEmpty
          ? 'Camaman-an, Cagayan de Oro City, Misamis Oriental'
          : address;
    } else if (selectedName.contains('MARLJONE BLAIRE B. TINGTING')) {
      formalName =
          formalName.isEmpty ? 'Marljone Blaire B. Tingting' : formalName;
      civilStatus = civilStatus.isEmpty ? 'single' : civilStatus;
      address =
          address.isEmpty ? 'Tankulan, Manolo Fortich, Bukidnon' : address;
    } else {
      formalName = formalName.isEmpty ? 'Jho Ann Q. Cleopas' : formalName;
      civilStatus = civilStatus.isEmpty ? 'married' : civilStatus;
      address =
          address.isEmpty ? 'Tankulan, Manolo Fortich, Bukidnon' : address;
    }

    // All optional template pages have already been removed at this point.
    // The Omnibus Sworn Statement is final page 53 (zero-based index 52).
    if (document.pages.count <= pageIndex) return;
    final page = document.pages[pageIndex];
    final pageWidth = page.getClientSize().width;
    final left = pageWidth * .115;
    // Match the original identity paragraph beneath the centered Omnibus
    // title. Keeping this band separate preserves the title above and clears
    // the complete old paragraph, including "depose and state that".
    const top = 140.0;
    final right = pageWidth - left;
    const originalHeight = 48.0;
    final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
    final emphasizedFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.italic,
    );

    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(
        left - 3,
        top - 2,
        right - left + 6,
        originalHeight + 6,
      ),
    );
    final parts = <(String, PdfFont)>[
      ('I, ', regularFont),
      (formalName, emphasizedFont),
      (', of legal age, ', regularFont),
      (civilStatus, emphasizedFont),
      (', ', regularFont),
      ('Filipino', emphasizedFont),
      (', and with residence at ', regularFont),
      (address, emphasizedFont),
      (
        ', after having been duly sworn in accordance with law, do hereby ',
        regularFont
      ),
      ('depose and state that:', regularFont),
    ];
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    // Align the first "I" of the editable first and third paragraphs with
    // the unchanged middle paragraph, matching the original three-paragraph
    // vertical rhythm.
    const firstLineIndent = 38.0;
    const lineHeight = 13.0;
    var y = top;
    var x = left + firstLineIndent;
    var lineRight = right;
    var pendingSpace = false;

    for (final part in parts) {
      final matches = RegExp(r'\S+').allMatches(part.$1);
      for (final match in matches) {
        final word = match.group(0)!;
        final hasLeadingSpace = pendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        pendingSpace = false;
        // PdfStandardFont reports a zero/near-zero width for an isolated
        // space. Use the Times Roman word-space width explicitly so styled
        // fragments do not run together.
        final spaceWidth = hasLeadingSpace ? 2.8 : 0.0;
        final width = part.$2.measureString(word).width;
        if (x + spaceWidth + width > lineRight && x > left) {
          y += lineHeight;
          x = left;
        }
        if (x > left) x += spaceWidth;
        page.graphics.drawString(
          word,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(x, y, width + 1, lineHeight),
        );
        if (identical(part.$2, emphasizedFont)) {
          // A subtle second pass gives the template's bold-italic appearance;
          // Syncfusion's standard font API only accepts one style at a time.
          page.graphics.drawString(
            word,
            part.$2,
            brush: black,
            bounds: Rect.fromLTWH(x + .22, y, width + 1, lineHeight),
          );
        }
        x += width;
      }
      pendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }

    // Replace the template's embedded company office address paragraph.
    const officeTop = 195.0;
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(left - 3, officeTop - 2, right - left + 6, 40),
    );
    final bidderName = (values['bidderName'] ?? '').trim();
    final officeParts = <(String, PdfFont)>[
      (
        'I am the duly authorized and designated representative of ',
        regularFont
      ),
      (bidderName, emphasizedFont),
      (' with office address at ', regularFont),
      (_permanentBusinessAddress, emphasizedFont),
      ('.', regularFont),
    ];
    var officeY = officeTop;
    var officeX = left + firstLineIndent;
    var officePendingSpace = false;
    for (final part in officeParts) {
      for (final match in RegExp(r'\S+').allMatches(part.$1)) {
        final word = match.group(0)!;
        final hasLeadingSpace = officePendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        officePendingSpace = false;
        final spaceWidth = hasLeadingSpace ? 2.8 : 0.0;
        final wordWidth = part.$2.measureString(word).width;
        if (officeX + spaceWidth + wordWidth > right && officeX > left) {
          officeY += lineHeight;
          officeX = left;
        }
        if (officeX > left) officeX += spaceWidth;
        page.graphics.drawString(
          word,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(officeX, officeY, wordWidth + 1, lineHeight),
        );
        if (identical(part.$2, emphasizedFont)) {
          page.graphics.drawString(
            word,
            part.$2,
            brush: black,
            bounds: Rect.fromLTWH(
                officeX + .22, officeY, wordWidth + 1, lineHeight),
          );
        }
        officeX += wordWidth;
      }
      officePendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }

    final projectTitle = (values['projectTitle'] ?? '').trim();
    final procuringEntity = (values['procuringEntity'] ?? '').trim();
    if (projectTitle.isEmpty || procuringEntity.isEmpty) {
      return;
    }

    const authorityTop = 237.0;
    const authorityHeight = 100.0;
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(
        left - 3,
        authorityTop - 2,
        right - left + 6,
        authorityHeight + 5,
      ),
    );
    final authorityParts = <(String, PdfFont)>[
      (
        'I am granted full power and authority to do, execute and perform any '
            'and all acts necessary to participate, submit the bid, and to sign '
            'and execute the ensuing contract for ',
        regularFont
      ),
      (projectTitle, emphasizedFont),
      (' of the ', regularFont),
      (procuringEntity, emphasizedFont),
      (
        ' as supported by the attached duly notarized Special Power of '
            'Attorney, Board/Partnership Resolution, or Secretary’s Certificate, '
            'whichever is applicable;',
        regularFont
      ),
    ];
    var authorityY = authorityTop;
    var authorityX = left + firstLineIndent;
    var authorityPendingSpace = false;
    for (final part in authorityParts) {
      final matches = RegExp(r'\S+').allMatches(part.$1);
      for (final match in matches) {
        final word = match.group(0)!;
        final hasLeadingSpace = authorityPendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        authorityPendingSpace = false;
        final spaceWidth = hasLeadingSpace ? 2.8 : 0.0;
        final width = part.$2.measureString(word).width;
        if (authorityX + spaceWidth + width > right && authorityX > left) {
          authorityY += lineHeight;
          authorityX = left;
        }
        if (authorityX > left) authorityX += spaceWidth;
        page.graphics.drawString(
          word,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(
            authorityX,
            authorityY,
            width + 1,
            lineHeight,
          ),
        );
        if (identical(part.$2, emphasizedFont)) {
          page.graphics.drawString(
            word,
            part.$2,
            brush: black,
            bounds: Rect.fromLTWH(
              authorityX + .22,
              authorityY,
              width + 1,
              lineHeight,
            ),
          );
        }
        authorityX += width;
      }
      authorityPendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }
  }

  static void _drawOmnibusSwornStatementLastPage(
    PdfDocument document,
    Map<String, String> values, {
    required int pageIndex,
  }) {
    if (document.pages.count <= pageIndex) return;
    final page = document.pages[pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final italic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.italic,
    );
    final boldItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.italic,
    );
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final bidderName = (values['bidderName'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final selectedName = (values['submittedBy'] ?? '').trim().toUpperCase();
    final formalName = selectedName.contains('CARLOS RAFAEL A. JAMILO')
        ? 'Carlos Rafael A. Jamilo'
        : selectedName.contains('MARLJONE BLAIRE B. TINGTING')
            ? 'Marljone Blaire B. Tingting'
            : 'Jho Ann Q. Cleopas';

    // Item 7(d): replace the sample Sumilao project with the current bid.
    if (projectTitle.isNotEmpty) {
      final pageLines = PdfTextExtractor(document).extractTextLines(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      TextLine? inquiryLine;
      for (final line in pageLines) {
        final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
        if (text.contains('INQUIRE OR SECURE SUPPLEMENTAL BID')) {
          inquiryLine = line;
          break;
        }
      }
      if (inquiryLine != null) {
        final itemRegular = PdfStandardFont(PdfFontFamily.timesRoman, 11);
        final itemItalic = PdfStandardFont(
          PdfFontFamily.timesRoman,
          11,
          style: PdfFontStyle.italic,
        );
        final normalizedProjectTitle = projectTitle.toUpperCase();
        final projectPrefixMatch = RegExp(
          r'^PROCUREMENT\s+OF\b',
          caseSensitive: false,
        ).firstMatch(normalizedProjectTitle);
        final projectPrefix = projectPrefixMatch?.group(0) ?? '';
        final itemProjectTitle = normalizedProjectTitle.replaceFirst(
          RegExp(r'^PROCUREMENT\s+OF\s+', caseSensitive: false),
          '',
        );
        final top = inquiryLine.bounds.top - 2;
        // Replace from the original d) marker itself. Starting the clear and
        // redraw at this exact bound avoids a leftover marker ("d)d)") and
        // preserves the source template's alignment with a), b), and c).
        final left = inquiryLine.bounds.left.clamp(60, 500).toDouble();
        final right = page.getClientSize().width - 55;
        graphics.drawRectangle(
          brush: white,
          // Clear only the original two-line 7(d) block. Extending this band
          // farther down clips the top of item 8 in the source template.
          bounds: Rect.fromLTWH(left - 3, top, right - left + 3, 34),
        );
        const itemTextLeftOffset = 27.0;
        const inquiryText =
            'Inquire or secure Supplemental Bid Bulletin(s) issued for the ';
        graphics.drawString(
          'd)',
          itemRegular,
          brush: black,
          bounds: Rect.fromLTWH(left, top + 1, itemTextLeftOffset, 16),
        );
        final itemTextLeft = left + itemTextLeftOffset;
        graphics.drawString(
          inquiryText,
          itemRegular,
          brush: black,
          bounds: Rect.fromLTWH(
            itemTextLeft,
            top + 1,
            right - itemTextLeft,
            16,
          ),
        );
        final procurementLeft = itemTextLeft +
            itemRegular.measureString(inquiryText.trimRight()).width +
            2.8;
        for (final offset in const <double>[0, .25, .5]) {
          graphics.drawString(
            projectPrefix,
            itemItalic,
            brush: black,
            bounds: Rect.fromLTWH(
              procurementLeft + offset,
              top + 1,
              right - procurementLeft,
              16,
            ),
          );
        }
        graphics.drawString(
          itemProjectTitle,
          itemItalic,
          brush: black,
          bounds: Rect.fromLTWH(
            itemTextLeft,
            top + 17,
            right - itemTextLeft,
            29,
          ),
          format: PdfStringFormat(
            wordWrap: PdfWordWrapType.word,
            lineAlignment: PdfVerticalAlignment.top,
          ),
        );
        // PdfStandardFont supports italic or bold as a single style. A subtle
        // second pass gives the project title the template's bold-italic look.
        for (final offset in const <double>[.25, .5]) {
          graphics.drawString(
            itemProjectTitle,
            itemItalic,
            brush: black,
            bounds: Rect.fromLTWH(
              itemTextLeft + offset,
              top + 17,
              right - itemTextLeft,
              29,
            ),
            format: PdfStringFormat(
              wordWrap: PdfWordWrapType.word,
              lineAlignment: PdfVerticalAlignment.top,
            ),
          );
        }
      }
    }

    // Signature block follows the selected bidder and representative.
    graphics.drawRectangle(
      brush: white,
      bounds: const Rect.fromLTWH(235, 535, 335, 128),
    );
    const signatureLeft = 250.0;
    const signatureWidth = 300.0;
    final leftAligned = PdfStringFormat(alignment: PdfTextAlignment.left);
    final formattedBidderName = bidderName
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
    graphics.drawString(
      'Duly authorized to sign the Bid for and behalf of:',
      regular,
      brush: black,
      bounds: const Rect.fromLTWH(signatureLeft, 544, signatureWidth, 16),
      format: leftAligned,
    );
    graphics.drawString(
      formattedBidderName,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(signatureLeft, 572, signatureWidth, 16),
      format: leftAligned,
    );
    graphics.drawString(
      formattedBidderName,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(
        signatureLeft + .22,
        572,
        signatureWidth,
        16,
      ),
      format: leftAligned,
    );
    graphics.drawString(
      formalName,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(signatureLeft, 610, signatureWidth, 16),
      format: leftAligned,
    );
    graphics.drawString(
      formalName,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(
        signatureLeft + .22,
        610,
        signatureWidth,
        16,
      ),
      format: leftAligned,
    );
    graphics.drawString(
      'Authorized Representative',
      italic,
      brush: black,
      bounds: const Rect.fromLTWH(signatureLeft, 628, signatureWidth, 16),
      format: leftAligned,
    );
    graphics.drawString(
      date,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(signatureLeft, 646, signatureWidth, 16),
      format: leftAligned,
    );
    graphics.drawString(
      date,
      boldItalic,
      brush: black,
      bounds: const Rect.fromLTWH(
        signatureLeft + .22,
        646,
        signatureWidth,
        16,
      ),
      format: leftAligned,
    );
  }

  static void _drawAfterSalesServiceCertificate(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final pageIndex = _findPageContaining(
      document,
      const <String>[
        'AFTER-SALES SERVICE CERTIFICATE',
        'AFTER SALES SERVICE CERTIFICATE',
      ],
    );
    if (pageIndex < 0) return;
    final page = document.pages[pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final bidderName = (values['bidderName'] ?? '').trim();
    final procuringEntity = (values['procuringEntity'] ?? '').trim();
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final parsedAfterSalesYears =
        int.tryParse((values['afterSalesYears'] ?? '').trim()) ?? 1;
    final afterSalesYears =
        parsedAfterSalesYears < 1 ? 1 : parsedAfterSalesYears;
    final afterSalesYearsInWords =
        _integerInWords(afterSalesYears).toLowerCase();
    final afterSalesPeriod = '$afterSalesYearsInWords ($afterSalesYears) '
        '${afterSalesYears == 1 ? 'year' : 'years'}';
    final selectedName = (values['submittedBy'] ?? '').trim().toUpperCase();
    final formalName = selectedName.contains('CARLOS RAFAEL A. JAMILO')
        ? 'CARLOS RAFAEL A. JAMILO'
        : selectedName.contains('MARLJONE BLAIRE B. TINGTING')
            ? 'MARLJONE BLAIRE B. TINGTING'
            : 'JHO ANN Q. CLEOPAS';
    final pageLines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );
    _replaceCertificateHeaderAddress(page, pageLines);
    TextLine? certificateLine;
    TextLine? secondParagraphLine;
    TextLine? submittedLine;
    for (final line in pageLines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('THIS SERVES TO CERTIFY')) certificateLine ??= line;
      if (text.contains('BEYOND THE INITIAL DELIVERY')) {
        secondParagraphLine ??= line;
      }
      if (text.contains('SUBMITTED BY')) submittedLine ??= line;
    }

    // Replace the sample Sumilao certification paragraph.
    final certificateTop = certificateLine?.bounds.top ?? 194.0;
    const certificateLeft = 106.0;
    final certificateRight = page.getClientSize().width - 96;
    // Mixed fonts split the source paragraph into unrelated extraction
    // fragments, so its calculated height is unreliable. Clear the complete
    // known paragraph band while stopping above the second paragraph.
    const certificateHeight = 145.0;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        80,
        certificateTop - 12,
        page.getClientSize().width - 150,
        certificateHeight + 12,
      ),
    );
    final bodyRegular = PdfStandardFont(PdfFontFamily.timesRoman, 13.5);
    final bodyBold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      13.5,
      style: PdfFontStyle.bold,
    );
    final bodyItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      13.5,
      style: PdfFontStyle.italic,
    );
    final bodyParts = <(String, PdfFont)>[
      ('This serves to certify that ', bodyRegular),
      (bidderName, bodyBold),
      (
        ' is fully committed to providing comprehensive after-sales support '
            'to the ',
        bodyRegular
      ),
      (procuringEntity, bodyBold),
      (' for the project: ', bodyRegular),
      (projectTitle, bodyItalic),
      ('.', bodyRegular),
    ];
    final bodyLeft = certificateLeft;
    final bodyRight = certificateRight;
    const bodyLineHeight = 16.2;
    var bodyX = bodyLeft + 28;
    var bodyY = certificateTop;
    var bodyPendingSpace = false;
    for (final part in bodyParts) {
      for (final match in RegExp(r'\S+').allMatches(part.$1)) {
        final word = match.group(0)!;
        final hasLeadingSpace = bodyPendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        bodyPendingSpace = false;
        final spaceWidth = hasLeadingSpace ? 3.4 : 0.0;
        final width = part.$2.measureString(word).width;
        if (bodyX + spaceWidth + width > bodyRight && bodyX > bodyLeft) {
          bodyY += bodyLineHeight;
          bodyX = bodyLeft;
        }
        if (bodyX > bodyLeft) bodyX += spaceWidth;
        graphics.drawString(
          word,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(bodyX, bodyY, width + 1, bodyLineHeight),
        );
        if (identical(part.$2, bodyItalic)) {
          // Use several close italic passes to match the source document's
          // visibly heavy bold-italic project title.
          for (final offset in const <double>[.3, .6, .9]) {
            graphics.drawString(
              word,
              part.$2,
              brush: black,
              bounds: Rect.fromLTWH(
                bodyX + offset,
                bodyY,
                width + 2,
                bodyLineHeight,
              ),
            );
          }
        }
        bodyX += width;
      }
      bodyPendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }

    // Restore the complete support-period paragraph in the source format.
    final supportTop =
        secondParagraphLine?.bounds.top ?? (certificateTop + 145);
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(96, supportTop - 5, 430, 100),
    );
    final supportParts = <(String, PdfFont)>[
      (
        'Beyond the initial delivery of materials, our company pledges a '
            'dedicated ',
        bodyRegular
      ),
      (afterSalesPeriod, bodyBold),
      (
        ' period of technical support and after-sales service. We remain at '
            'the full disposal of the municipal end-users to ensure that all '
            'operational needs are met and that our professional assistance is '
            'readily available throughout the first '
            '${afterSalesYears == 1 ? 'year' : '$afterSalesYearsInWords years'} '
            'of the facility’s '
            'rehabilitation.',
        bodyRegular
      ),
    ];
    var supportX = bodyLeft + 28;
    var supportY = supportTop;
    var supportPendingSpace = false;
    for (final part in supportParts) {
      for (final match in RegExp(r'\S+').allMatches(part.$1)) {
        final word = match.group(0)!;
        final hasLeadingSpace = supportPendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        supportPendingSpace = false;
        final spaceWidth = hasLeadingSpace ? 3.4 : 0.0;
        final width = part.$2.measureString(word).width;
        if (supportX + spaceWidth + width > bodyRight && supportX > bodyLeft) {
          supportY += bodyLineHeight;
          supportX = bodyLeft;
        }
        if (supportX > bodyLeft) supportX += spaceWidth;
        graphics.drawString(
          word,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(
            supportX,
            supportY,
            width + 1,
            bodyLineHeight,
          ),
        );
        supportX += width;
      }
      supportPendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }

    // Replace the embedded signatory while keeping the original form grid.
    final labelLeft = submittedLine?.bounds.left ?? 143.0;
    final colonLeft = labelLeft + 109;
    final valueLeft = labelLeft + 145;
    final top = (submittedLine?.bounds.top ?? 456.0) - 1;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        labelLeft - 5,
        top - 5,
        page.getClientSize().width - labelLeft - 25,
        112,
      ),
    );
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 10.5);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.bold,
    );
    void drawRow(String label, String value, double y) {
      graphics.drawString(
        label,
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(labelLeft, y, 100, 15),
      );
      graphics.drawString(
        ':',
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(colonLeft, y, 10, 15),
      );
      graphics.drawString(
        value,
        valueFont,
        brush: black,
        bounds: Rect.fromLTWH(valueLeft, y, 250, 15),
      );
    }

    drawRow('Submitted by', formalName, top);
    final nameWidth = valueFont.measureString(formalName).width;
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: .5),
      Offset(valueLeft, top + 12),
      Offset(valueLeft + nameWidth, top + 12),
    );
    graphics.drawString(
      '(Printed Name & Signature)',
      labelFont,
      brush: black,
      bounds: Rect.fromLTWH(valueLeft, top + 15, 200, 14),
    );
    drawRow('Designation', 'Authorized Representative', top + 31);
    drawRow('Name of Firm', bidderName.toUpperCase(), top + 48);
    drawRow('Date', date, top + 65);
  }

  static void _drawProductWarrantyCertificate(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final pageIndex = _findPageContaining(
      document,
      const <String>['CERTIFICATE OF PRODUCT WARRANTY'],
    );
    if (pageIndex < 0) return;
    final page = document.pages[pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final bidderName = (values['bidderName'] ?? '').trim();
    final displayBidderName = bidderName
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final municipality = (values['municipality'] ?? '').trim();
    final province = (values['province'] ?? '').trim();
    final date = (values['date'] ?? '').trim();
    final parsedWarrantyYears =
        int.tryParse((values['warrantyYears'] ?? '').trim()) ?? 2;
    final warrantyYears = parsedWarrantyYears < 1 ? 2 : parsedWarrantyYears;
    final warrantyPeriod =
        '${_integerInWords(warrantyYears).toLowerCase()} ($warrantyYears) '
        '${warrantyYears == 1 ? 'year' : 'years'}';
    final selectedName = (values['submittedBy'] ?? '').trim().toUpperCase();
    final formalName = selectedName.contains('CARLOS RAFAEL A. JAMILO')
        ? 'Carlos Rafael A. Jamilo'
        : selectedName.contains('MARLJONE BLAIRE B. TINGTING')
            ? 'Marljone Blaire B. Tingting'
            : 'Jho Ann Q. Cleopas';
    final lines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );
    _replaceCertificateHeaderAddress(page, lines);
    TextLine? titleLine;
    TextLine? certificationLine;
    TextLine? guaranteeLine;
    TextLine? commitmentLine;
    TextLine? submittedLine;
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('CERTIFICATE OF PRODUCT WARRANTY')) titleLine ??= line;
      if (text.contains('THIS IS TO CERTIFY THAT')) certificationLine ??= line;
      if (text.contains('WE GUARANTEE')) guaranteeLine ??= line;
      if (text.contains('REMAINS COMMITTED')) commitmentLine ??= line;
      if (text.contains('SUBMITTED BY')) submittedLine ??= line;
    }
    if (titleLine != null) {
      final titleTop = titleLine.bounds.top - 3;
      final titleFont = PdfStandardFont(
        PdfFontFamily.timesRoman,
        16,
        style: PdfFontStyle.italic,
      );
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          70,
          titleTop - 2,
          page.getClientSize().width - 140,
          28,
        ),
      );
      // Multiple close passes reproduce a strong bold-italic title while
      // retaining the slanted Times Roman style used by the template.
      for (final offset in const <double>[0, .3, .6]) {
        graphics.drawString(
          'CERTIFICATE OF PRODUCT WARRANTY',
          titleFont,
          brush: black,
          bounds: Rect.fromLTWH(
            70 + offset,
            titleTop,
            page.getClientSize().width - 140,
            24,
          ),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
      }
    }
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 13.5);
    final bold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      13.5,
      style: PdfFontStyle.bold,
    );
    final italic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      13.5,
      style: PdfFontStyle.italic,
    );
    final bodyLeft = 106.0;
    final bodyRight = page.getClientSize().width - 96;
    final firstTop = certificationLine?.bounds.top ?? 188.0;
    final firstHeight = guaranteeLine == null
        ? 95.0
        : (guaranteeLine.bounds.top - firstTop - 8).clamp(65, 120).toDouble();
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
          72, firstTop - 8, page.getClientSize().width - 130, firstHeight + 18),
    );
    void drawStyledParagraph(
      List<(String, PdfFont)> parts,
      double top, {
      double firstLineIndent = 0,
    }) {
      const lineHeight = 16.2;
      var x = bodyLeft + firstLineIndent;
      var y = top;
      var pendingSpace = false;
      for (final part in parts) {
        for (final match in RegExp(r'\S+').allMatches(part.$1)) {
          final word = match.group(0)!;
          final hasLeadingSpace = pendingSpace ||
              (match.start > 0 &&
                  RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
          pendingSpace = false;
          final spaceWidth = hasLeadingSpace ? 2.7 : 0.0;
          final width = part.$2.measureString(word).width;
          if (x + spaceWidth + width > bodyRight && x > bodyLeft) {
            y += lineHeight;
            x = bodyLeft;
          }
          if (x > bodyLeft) x += spaceWidth;
          graphics.drawString(word, part.$2,
              brush: black, bounds: Rect.fromLTWH(x, y, width + 1, lineHeight));
          if (identical(part.$2, italic)) {
            // The project title uses the template's strong bold-italic look.
            for (final offset in const <double>[.3, .6]) {
              graphics.drawString(
                word,
                part.$2,
                brush: black,
                bounds: Rect.fromLTWH(
                  x + offset,
                  y,
                  width + 1,
                  lineHeight,
                ),
              );
            }
          }
          x += width;
        }
        pendingSpace = RegExp(r'\s$').hasMatch(part.$1);
      }
    }

    drawStyledParagraph(<(String, PdfFont)>[
      ('This is to certify that ', regular),
      (displayBidderName, bold),
      (' provides a ', regular),
      (warrantyPeriod, bold),
      (' Limited Warranty on all materials supplied for the ', regular),
      (projectTitle, italic),
      (' in ', regular),
      ('Municipality of $municipality, $province', bold),
      ('.', regular),
    ], firstTop);

    // Update the company name in the closing commitment sentence.
    if (commitmentLine != null) {
      final top = commitmentLine.bounds.top - 3;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          72,
          top - 2,
          page.getClientSize().width - 130,
          42,
        ),
      );
      graphics.drawString(
        '$displayBidderName remains committed to ensuring the quality and durability '
        'of our contributions to the Municipality’s infrastructure.',
        regular,
        brush: black,
        bounds: Rect.fromLTWH(bodyLeft, top + 3, bodyRight - bodyLeft, 34),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
      graphics.drawString(
        displayBidderName,
        bold,
        brush: black,
        bounds: Rect.fromLTWH(
          bodyLeft,
          top + 3,
          bold.measureString(displayBidderName).width + 2,
          14,
        ),
      );
      // Clear the complete sentence once more and render it as one continuous
      // mixed-style paragraph. This avoids the bold company name being drawn
      // on top of the regular copy underneath.
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          72,
          top - 2,
          page.getClientSize().width - 130,
          42,
        ),
      );
      drawStyledParagraph(<(String, PdfFont)>[
        (displayBidderName, bold),
        (
          ' remains committed to ensuring the quality and durability of our '
              'contributions to the Municipality’s infrastructure.',
          regular
        ),
      ], top + 3, firstLineIndent: 0);
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          72,
          top - 2,
          page.getClientSize().width - 130,
          42,
        ),
      );
      drawStyledParagraph(<(String, PdfFont)>[
        (displayBidderName, bold),
        (
          ' remains committed to ensuring the quality and durability of our '
              "contributions to the Municipality's infrastructure.",
          regular
        ),
      ], top + 3, firstLineIndent: 0);
    }

    final labelLeft = submittedLine?.bounds.left ?? 143.0;
    final colonLeft = labelLeft + 109;
    final valueLeft = labelLeft + 145;
    final signatureTop = (submittedLine?.bounds.top ?? 475.0) - 1;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        labelLeft - 5,
        signatureTop - 5,
        page.getClientSize().width - labelLeft - 25,
        132,
      ),
    );
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 14);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.bold,
    );
    void drawRow(String label, String value, double y) {
      graphics.drawString(label, labelFont,
          brush: black, bounds: Rect.fromLTWH(labelLeft, y, 105, 22));
      graphics.drawString(':', labelFont,
          brush: black, bounds: Rect.fromLTWH(colonLeft, y, 10, 22));
      graphics.drawString(value, valueFont,
          brush: black, bounds: Rect.fromLTWH(valueLeft, y, 280, 22));
    }

    drawRow('Submitted by', formalName, signatureTop);
    final nameWidth = valueFont.measureString(formalName).width;
    graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: .5),
      Offset(valueLeft, signatureTop + 18),
      Offset(valueLeft + nameWidth, signatureTop + 18),
    );
    graphics.drawString('(Printed Name & Signature)',
        PdfStandardFont(PdfFontFamily.timesRoman, 11),
        brush: black,
        bounds: Rect.fromLTWH(valueLeft, signatureTop + 22, 230, 17));
    drawRow('Designation', 'Authorized Representative', signatureTop + 45);
    drawRow('Name of Firm', displayBidderName, signatureTop + 70);
    drawRow('Date', date, signatureTop + 95);
  }

  static double _measureMarkedSpecificationTextHeight(
    String text,
    PdfFont font,
    double width,
  ) {
    final markerPattern = RegExp(r'^\s*(âœ“|â€¢|â—‹|â– |âž¢)\s*');
    var totalHeight = 0.0;

    for (final rawLine in text.replaceAll('\u2029', '\n').split('\n')) {
      final match = markerPattern.firstMatch(rawLine);
      final content =
          match == null ? rawLine.trim() : rawLine.substring(match.end).trim();
      final rawContentWidth = width - (match == null ? 0 : 14);
      final contentWidth = rawContentWidth < 1.0 ? 1.0 : rawContentWidth;
      final measured = font.measureString(
        content.isEmpty ? ' ' : content,
        layoutArea: Size(contentWidth, 10000),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
      final minimumLineHeight = font.size + 2;
      totalHeight += measured.height > minimumLineHeight
          ? measured.height
          : minimumLineHeight;
    }

    return totalHeight;
  }

  static List<List<String>> _chunkMarkedSpecificationLines(
    List<String> sourceLines,
    PdfFont font,
    double width,
    double maximumHeight,
  ) {
    final chunks = <List<String>>[];
    var current = <String>[];

    for (final line in sourceLines) {
      final candidate = <String>[...current, line];
      final candidateHeight = _measureMarkedSpecificationTextHeight(
        candidate.join('\n'),
        font,
        width,
      );
      if (current.isNotEmpty && candidateHeight > maximumHeight) {
        chunks.add(current);
        current = <String>[line];
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static void _removeSlccSection(PdfDocument document) {
    const slccPageIndex = 20;
    const slccPageCount = 3;

    for (var removed = 0;
        removed < slccPageCount && slccPageIndex < document.pages.count;
        removed++) {
      document.pages.removeAt(slccPageIndex);
    }
  }

  static void _replaceCertificateHeaderAddress(
    PdfPage page,
    List<TextLine> lines,
  ) {
    TextLine? addressLine;
    TextLine? mobileLine;
    TextLine? emailLine;
    for (final line in lines) {
      final normalized = line.text.toUpperCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
      if (normalized.trimLeft().startsWith('MOBILE NO')) {
        mobileLine ??= line;
      }
      if (normalized.trimLeft().startsWith('EMAIL')) {
        emailLine ??= line;
      }
      if (normalized.contains('SAN AGUSTIN VALLEY HOMES') ||
          normalized.contains('L-25 & 27 B-2')) {
        addressLine = line;
      }
    }
    if (addressLine == null) return;

    final graphics = page.graphics;
    final pageWidth = page.getClientSize().width;
    // Rebuild the three contact lines as one block. Clearing and redrawing the
    // whole block prevents remnants/overlap from the flattened templates and
    // keeps Manpower, AFS, and Warranty visually identical.
    final referenceHeight =
        mobileLine?.bounds.height ?? addressLine.bounds.height;
    final top = addressLine.bounds.top;
    final left = mobileLine?.bounds.left ?? addressLine.bounds.left;
    final clearTop = top - 1;
    final detectedBottom = emailLine?.bounds.bottom ??
        mobileLine?.bounds.bottom ??
        addressLine.bounds.bottom;
    final clearBottom = detectedBottom + 1;
    graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(
        left - 2,
        clearTop,
        pageWidth - left - 18,
        clearBottom - clearTop,
      ),
    );

    final availableWidth = pageWidth - left - 20;
    // Use one fixed size on Manpower, AFS, and Warranty so all three
    // letterheads remain visually identical.
    // Match the visual size of the existing Mobile No. and Email lines.
    const fontSize = 10.0;
    final font = PdfStandardFont(
      PdfFontFamily.helvetica,
      fontSize,
      style: PdfFontStyle.italic,
    );
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final originalGap = mobileLine == null
        ? referenceHeight + 1
        : mobileLine.bounds.top - addressLine.bounds.top;
    final lineGap = originalGap.clamp(fontSize + .5, fontSize + 2).toDouble();
    const contactLines = <String>[
      'Mobile No.: 0917 129 2972 / 0926 253 0301',
      'Email: MikataPrime@gmail.com',
    ];
    final replacementLines = <String>[
      'CDO Office: $_permanentBusinessAddress',
      ...contactLines,
    ];

    for (var lineIndex = 0; lineIndex < replacementLines.length; lineIndex++) {
      final lineTop = top + (lineIndex * lineGap);
      // Standard PDF fonts cannot combine bold and italic. Closely repeated
      // italic passes reproduce the bold-slanted style of the source header.
      for (final offset in const <double>[0, .18, .36]) {
        graphics.drawString(
          replacementLines[lineIndex],
          font,
          brush: black,
          bounds: Rect.fromLTWH(
            left + offset,
            lineTop,
            availableWidth,
            fontSize + 2,
          ),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.none),
        );
      }
    }
  }

  static void _drawJuratPlaceholders(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final date = (values['date'] ?? '').trim();
    final yearMatch = RegExp(r'\b(\d{4})\b').firstMatch(date);
    final year = yearMatch?.group(1) ?? '2026';
    final lines = PdfTextExtractor(document).extractTextLines();
    TextLine? subscribedLine;
    TextLine? witnessLine;
    TextLine? ptrLine;
    TextLine? ibpLine;
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('SUBSCRIBED AND SWORN')) subscribedLine ??= line;
      if (text.contains('WITNESS MY HAND AND SEAL')) witnessLine ??= line;
      if (text.startsWith('PTR NO.')) ptrLine ??= line;
      if (text.startsWith('IBP NO.')) ibpLine ??= line;
    }
    if (subscribedLine == null) return;

    final page = document.pages[subscribedLine.pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 11.5);
    final boldItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11.5,
      style: PdfFontStyle.italic,
    );
    final left = subscribedLine.bounds.left;
    final right = page.getClientSize().width - left;
    final subscribedTop = subscribedLine.bounds.top - 2;

    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(left - 3, subscribedTop - 2, right - left + 6, 82),
    );
    void drawRuns(
      double top,
      double width,
      List<(String, PdfFont, bool)> runs, {
      double lineHeight = 13.5,
    }) {
      var x = left;
      var y = top;
      var needsSpace = false;
      for (final run in runs) {
        for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          final spaceWidth = needsSpace ? 3.0 : 0.0;
          final wordWidth = run.$2.measureString(word).width;
          if (x > left && x + spaceWidth + wordWidth > left + width) {
            x = left;
            y += lineHeight;
          } else if (x > left) {
            x += spaceWidth;
          }
          graphics.drawString(
            word,
            run.$2,
            brush: black,
            bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
          );
          if (run.$3) {
            graphics.drawString(
              word,
              run.$2,
              brush: black,
              bounds: Rect.fromLTWH(x + .3, y, wordWidth + 2, lineHeight),
            );
          }
          x += wordWidth;
          needsSpace = true;
        }
      }
    }

    drawRuns(subscribedTop, right - left, <(String, PdfFont, bool)>[
      (
        'SUBSCRIBED AND SWORN to before me this ______ day of ________',
        regular,
        false
      ),
      (year, boldItalic, true),
      ('at', regular, false),
      (
        'Municipality of __________, __________, Philippines.',
        boldItalic,
        true
      ),
      (
        'Affiant/s is/are personally known to me and was/were '
            'identified by me through competent evidence of identity as defined '
            'in the 2004 Rules on Notarial Practice (A.M. No. 02-8-13-SC). '
            'Affiant/s exhibited to me his/her',
        regular,
        false
      ),
      ('National ID,', boldItalic, true),
      (
        'with his/her photograph and signature appearing thereon, with no. '
            '____________________',
        regular,
        false
      ),
    ]);

    final witnessTop = (witnessLine?.bounds.top ?? subscribedTop + 86) - 2;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(left - 3, witnessTop - 2, right - left + 6, 22),
    );
    drawRuns(witnessTop, right - left, <(String, PdfFont, bool)>[
      ('WITNESS MY HAND AND SEAL this ____ day of ________', regular, false),
      ('$year.', boldItalic, true),
    ]);

    void replaceNotaryDate(TextLine? line, String label) {
      if (line == null) return;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          line.bounds.left - 2,
          line.bounds.top - 1,
          line.bounds.width + 30,
          line.bounds.height + 3,
        ),
      );
      final labelWidth = regular.measureString('$label ____, ________').width;
      graphics.drawString(
        '$label ____, ________',
        regular,
        brush: black,
        bounds: Rect.fromLTWH(
          line.bounds.left,
          line.bounds.top,
          line.bounds.width + 30,
          16,
        ),
      );
      final yearLeft = line.bounds.left + labelWidth + 3;
      graphics.drawString(
        year,
        boldItalic,
        brush: black,
        bounds: Rect.fromLTWH(yearLeft, line.bounds.top, 45, 16),
      );
      graphics.drawString(
        year,
        boldItalic,
        brush: black,
        bounds: Rect.fromLTWH(yearLeft + .3, line.bounds.top, 45, 16),
      );
    }

    replaceNotaryDate(ptrLine, 'PTR No.');
    replaceNotaryDate(ibpLine, 'IBP No.');
  }

  static void _drawBidForm(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final lines = PdfTextExtractor(document).extractTextLines();
    int? bidFormPageIndex;
    for (final line in lines) {
      final text =
          line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text == 'BID FORM') {
        bidFormPageIndex = line.pageIndex;
        break;
      }
    }
    if (bidFormPageIndex == null) return;
    TextLine? idLine;
    TextLine? toLine;
    TextLine? itemA;
    TextLine? itemB;
    TextLine? itemC;
    TextLine? itemD;
    TextLine? authorizedLine;
    TextLine? acknowledgeLine;
    for (final line in lines) {
      if (line.pageIndex != bidFormPageIndex) continue;
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('PROJECT IDENTIFICATION NO.')) idLine ??= line;
      if (text.startsWith('TO:')) toLine ??= line;
      if (text.contains('I/WE HAVE NO RESERVATION')) itemA ??= line;
      if (text.contains('I/WE OFFER TO EXECUTE')) itemB ??= line;
      if (text.contains('THE TOTAL PRICE OF OUR BID IN WORDS')) itemC ??= line;
      if (text.contains('THE DISCOUNTS OFFERED')) itemD ??= line;
      if (text.contains('THE UNDERSIGNED IS AUTHORIZED')) {
        authorizedLine ??= line;
      }
      if (text.contains('I/WE ACKNOWLEDGE THAT FAILURE')) {
        acknowledgeLine ??= line;
      }
    }
    if (idLine == null) return;

    List<dynamic> specifications = const [];
    List<dynamic> prices = const [];
    final encodedSpecifications = values['technicalSpecifications'] ?? '';
    final encodedPrices = values['priceSchedule'] ?? '';
    if (encodedSpecifications.isNotEmpty) {
      final decoded = jsonDecode(encodedSpecifications);
      if (decoded is List) specifications = decoded;
    }
    if (encodedPrices.isNotEmpty) {
      final decoded = jsonDecode(encodedPrices);
      if (decoded is List) prices = decoded;
    }
    double number(dynamic value) =>
        double.tryParse((value ?? '').toString().replaceAll(',', '').trim()) ??
        0;
    var total = 0.0;
    for (var index = 0; index < specifications.length; index++) {
      final specification = specifications[index] is Map
          ? specifications[index] as Map
          : const {};
      final price = index < prices.length && prices[index] is Map
          ? prices[index] as Map
          : const {};
      final adjustedUnitPrice =
          (number(price['totalPricePerUnit']) - number(price['deduction']))
              .clamp(0, double.infinity)
              .toDouble();
      total += (number(specification['quantity']) * adjustedUnitPrice)
          .roundToDouble();
    }

    final page = document.pages[idLine.pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 10.5);
    final italic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10.5,
      style: PdfFontStyle.italic,
    );
    final boldItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10.5,
      style: PdfFontStyle.italic,
    );
    final headingRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final headingItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.italic,
    );
    final itemCRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final itemCBoldItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.italic,
    );
    final authorizedRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final authorizedItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.italic,
    );
    final reference = (values['referenceNumber'] ?? '').trim();
    final municipality = (values['municipality'] ?? '').trim();
    final province = (values['province'] ?? '').trim();
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final selected =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
    final bidderName = (values['bidderName'] ?? '').trim();
    final bidDate = (values['date'] ?? '').trim();
    final location = 'Municipality of $municipality, $province';
    final money = _formatBidAmount(total);
    final amountWords = _bidAmountInWords(total);

    void replaceLine(TextLine? line, String text,
        {PdfFont? font, double extraWidth = 20}) {
      if (line == null) return;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(line.bounds.left - 3, line.bounds.top - 2,
            line.bounds.width + extraWidth + 6, line.bounds.height + 5),
      );
      graphics.drawString(text, font ?? regular,
          brush: black,
          bounds: Rect.fromLTWH(line.bounds.left, line.bounds.top,
              line.bounds.width + extraWidth, line.bounds.height + 4));
    }

    void replaceStyledLine(
      TextLine? line,
      List<(String, PdfFont)> parts, {
      double extraWidth = 20,
    }) {
      if (line == null) return;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(line.bounds.left - 3, line.bounds.top - 2,
            line.bounds.width + extraWidth + 6, line.bounds.height + 5),
      );
      var x = line.bounds.left;
      for (final part in parts) {
        final width = part.$2.measureString(part.$1).width;
        graphics.drawString(
          part.$1,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(
              x, line.bounds.top, width + 2, line.bounds.height + 4),
        );
        if (identical(part.$2, boldItalic) ||
            identical(part.$2, headingItalic)) {
          graphics.drawString(
            part.$1,
            part.$2,
            brush: black,
            bounds: Rect.fromLTWH(
                x + .2, line.bounds.top, width + 2, line.bounds.height + 4),
          );
        }
        x += width;
      }
    }

    replaceStyledLine(
        idLine,
        <(String, PdfFont)>[
          ('Project Identification No.: ', headingRegular),
          (reference, headingItalic),
        ],
        extraWidth: 80);
    replaceStyledLine(
        toLine,
        <(String, PdfFont)>[
          ('To: ', headingItalic),
          (location, headingItalic),
        ],
        extraWidth: 120);

    void replaceParagraph(
      TextLine? start,
      TextLine? next,
      String text, {
      PdfFont? font,
    }) {
      if (start == null) return;
      final left = start.bounds.left;
      final right = page.getClientSize().width - 70;
      final top = start.bounds.top - 2;
      final height = next == null
          ? 54.0
          : (next.bounds.top - top - 2).clamp(36, 78).toDouble();
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(left - 3, top - 2, right - left + 6, height + 4),
      );
      graphics.drawString(text, font ?? regular,
          brush: black,
          bounds: Rect.fromLTWH(left, top, right - left, height),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
    }

    void drawStyledParagraph(
      TextLine? start,
      TextLine? next,
      List<(String, PdfFont, bool)> parts, {
      double hangingIndent = 0,
      double labelColumnWidth = 0,
      double lineHeight = 12.5,
    }) {
      if (start == null) return;
      final left = start.bounds.left;
      final right = page.getClientSize().width - 70;
      final top = start.bounds.top - 2;
      final height = next == null
          ? 54.0
          : (next.bounds.top - top - 2).clamp(36, 78).toDouble();
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(left - 3, top - 2, right - left + 6, height + 4),
      );
      var x = left;
      var y = top;
      var pendingSpace = false;
      var isFirstWord = true;
      for (final part in parts) {
        for (final match in RegExp(r'\S+').allMatches(part.$1)) {
          final word = match.group(0)!;
          final hasLeadingSpace = pendingSpace ||
              (match.start > 0 &&
                  RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
          pendingSpace = false;
          final spaceWidth = hasLeadingSpace ? 2.7 : 0.0;
          final width = part.$2.measureString(word).width;
          if (x + spaceWidth + width > right && x > left) {
            y += lineHeight;
            x = left + hangingIndent;
          }
          if (x > left) x += spaceWidth;
          graphics.drawString(word, part.$2,
              brush: black, bounds: Rect.fromLTWH(x, y, width + 1, lineHeight));
          if (part.$3) {
            // Match the template's clean bold-italic weight without making
            // the glyphs look doubled or excessively heavy.
            graphics.drawString(
              word,
              part.$2,
              brush: black,
              bounds: Rect.fromLTWH(x + .25, y, width + 1, lineHeight),
            );
          }
          x += width;
          if (isFirstWord && labelColumnWidth > 0) {
            x = left + labelColumnWidth;
          }
          isFirstWord = false;
        }
        pendingSpace = RegExp(r'\s$').hasMatch(part.$1);
      }
    }

    replaceParagraph(
      itemA,
      itemB,
      'a)  I/We have no reservation to the PBD, including the Supplemental Bid '
      'Bulletins, for the Procurement $projectTitle.',
    );
    replaceParagraph(
      itemC,
      itemD,
      'c)  The total price of our Bid in words and figures, excluding any '
      'discount offered below, is $amountWords Only (PHP $money).',
      font: italic,
    );
    replaceParagraph(
      authorizedLine,
      acknowledgeLine,
      'The undersigned is authorized to submit the bid on behalf of $selected '
      'as evidenced by the attached Secretary’s Certificate.',
    );

    // Restore the source BID FORM's mixed regular and bold-italic emphasis.
    drawStyledParagraph(
      itemA,
      itemB,
      <(String, PdfFont, bool)>[
        (
          'a)  I/We have no reservation to the PBD, including the Supplemental '
              'Bid Bulletins, for the ',
          regular,
          false
        ),
        (projectTitle, italic, true),
        ('.', regular, false),
      ],
      hangingIndent: 16,
      labelColumnWidth: 16,
    );
    drawStyledParagraph(
      itemC,
      itemD,
      <(String, PdfFont, bool)>[
        (
          'c)  The total price of our Bid in words and figures, excluding any '
              'discount offered below, is ',
          itemCRegular,
          false
        ),
        ('$amountWords Only (PHP $money).', itemCBoldItalic, true),
      ],
      hangingIndent: 16,
      labelColumnWidth: 16,
      lineHeight: 14.5,
    );
    drawStyledParagraph(
        authorizedLine,
        acknowledgeLine,
        <(String, PdfFont, bool)>[
          (
            'The undersigned is authorized to submit the bid on behalf of ',
            authorizedRegular,
            false
          ),
          (selected, authorizedItalic, true),
          (' as evidenced by the attached ', authorizedRegular, false),
          ("Secretary's Certificate.", authorizedItalic, true),
        ],
        lineHeight: 14.5);

    // The BID FORM signature is on the following template page. Replace that
    // block separately so it always follows the current sidebar values.
    TextLine? continuationSignature;
    for (final line in lines) {
      if (line.pageIndex <= bidFormPageIndex) continue;
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('DULY AUTHORIZED TO SIGN THE BID FOR AND BEHALF OF')) {
        continuationSignature = line;
        break;
      }
    }
    if (continuationSignature != null) {
      final signaturePage = document.pages[continuationSignature.pageIndex];
      final signatureGraphics = signaturePage.graphics;
      final left = continuationSignature.bounds.left;
      final top = continuationSignature.bounds.top;
      final availableWidth = signaturePage.size.width - left - 42;

      signatureGraphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 4,
          top - 3,
          availableWidth + 8,
          132,
        ),
      );
      signatureGraphics.drawString(
        'Duly authorized to sign the Bid for and behalf of:',
        PdfStandardFont(PdfFontFamily.timesRoman, 12),
        brush: black,
        bounds: Rect.fromLTWH(left, top, availableWidth, 17),
      );

      void drawEmphasized(String text, double y, {bool italicText = true}) {
        final font = PdfStandardFont(
          PdfFontFamily.timesRoman,
          12,
          style: italicText ? PdfFontStyle.italic : PdfFontStyle.regular,
        );
        signatureGraphics.drawString(
          text,
          font,
          brush: black,
          bounds: Rect.fromLTWH(left, y, availableWidth, 17),
        );
        signatureGraphics.drawString(
          text,
          font,
          brush: black,
          bounds: Rect.fromLTWH(left + .2, y, availableWidth, 17),
        );
      }

      drawEmphasized(bidderName, top + 30);
      drawEmphasized(selected, top + 72);
      signatureGraphics.drawString(
        'Authorized Representative',
        PdfStandardFont(
          PdfFontFamily.timesRoman,
          12,
          style: PdfFontStyle.italic,
        ),
        brush: black,
        bounds: Rect.fromLTWH(left, top + 91, availableWidth, 17),
      );
      drawEmphasized(bidDate, top + 110);
    }
  }

  static void _drawSecretaryCertificate(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final lines = PdfTextExtractor(document).extractTextLines();
    int? pageIndex;
    for (final line in lines) {
      final text =
          line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text == "SECRETARY'S CERTIFICATE" ||
          text == 'SECRETARY’S CERTIFICATE') {
        pageIndex = line.pageIndex;
        break;
      }
    }
    if (pageIndex == null) return;

    TextLine? venueLine;
    TextLine? introduction;
    TextLine? itemOne;
    TextLine? itemTwo;
    TextLine? itemThree;
    TextLine? resolved;
    TextLine? resolvedFurther;
    TextLine? resolvedFinally;
    TextLine? itemFour;
    for (final line in lines) {
      if (line.pageIndex != pageIndex) continue;
      final text =
          line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.contains('MUNICIPALITY OF')) {
        venueLine ??= line;
      }
      if (text.startsWith('I, ALYSSA LYNN TALINGTING')) introduction ??= line;
      if (text.contains('I AM THE DULY ELECTED AND QUALIFIED'))
        itemOne ??= line;
      if (text.contains('AS CORPORATE SECRETARY')) itemTwo ??= line;
      if (text.contains('AT THE SPECIAL MEETING OF THE BOARD OF DIRECTORS')) {
        itemThree ??= line;
      }
      if (text.contains('RESOLVED, THAT')) resolved ??= line;
      if (text.contains('RESOLVED FURTHER')) resolvedFurther ??= line;
      if (text.contains('RESOLVED FINALLY')) resolvedFinally ??= line;
      if (text.contains('THE FOREGOING RESOLUTIONS HAVE NOT'))
        itemFour ??= line;
    }
    if (introduction == null) return;

    final page = document.pages[pageIndex];
    final graphics = page.graphics;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final bold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final resolutionItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.italic,
    );
    final resolutionBoldItalic = PdfStandardFont(
      PdfFontFamily.timesRoman,
      11,
      style: PdfFontStyle.italic,
    );
    const permanentAddress = _permanentBusinessAddress;
    final municipality = (values['municipality'] ?? '').trim();
    final province = (values['province'] ?? '').trim();
    final projectTitle = (values['projectTitle'] ?? '').trim();
    final documentDate = (values['date'] ?? '').trim();
    var meetingDate = documentDate;
    try {
      final parsedDate = DateFormat('MMMM d, yyyy').parseStrict(documentDate);
      meetingDate = DateFormat('MMMM d, yyyy').format(
        parsedDate.subtract(const Duration(days: 3)),
      );
    } on FormatException {
      // Keep the supplied value if it is not in the expected display format.
    }
    final representative =
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();

    if (venueLine != null) {
      final venue = venueLine!;
      const venueText = 'Municipality of __________, __________   ) S.S';
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          venue.bounds.left - 2,
          venue.bounds.top - 1,
          page.size.width - venue.bounds.left + 2,
          venue.bounds.height + 4,
        ),
      );
      graphics.drawString(
        venueText,
        regular,
        brush: black,
        bounds: Rect.fromLTWH(
          venue.bounds.left,
          venue.bounds.top,
          page.size.width - venue.bounds.left - 45,
          18,
        ),
      );
    }

    void drawRuns(
      double left,
      double top,
      double width,
      List<(String, PdfFont)> runs, {
      double lineHeight = 15,
    }) {
      var x = left;
      var y = top;
      var pendingSpace = false;
      for (final run in runs) {
        final words = run.$1.trim().split(RegExp(r'\s+'));
        for (final word in words) {
          if (word.isEmpty) continue;
          // Standard PDF fonts can report a zero-width standalone space.
          // Use a visible word gap so mixed-style runs keep natural spacing.
          final measuredSpace = run.$2.measureString(' x').width -
              run.$2.measureString('x').width;
          final spaceWidth = pendingSpace
              ? (measuredSpace > 2.5 ? measuredSpace : run.$2.size * 0.28)
              : 0.0;
          final wordWidth = run.$2.measureString(word).width;
          if (x > left && x + spaceWidth + wordWidth > left + width) {
            x = left;
            y += lineHeight;
          }
          if (pendingSpace && x > left) x += spaceWidth;
          graphics.drawString(
            word,
            run.$2,
            brush: black,
            bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
          );
          x += wordWidth;
          pendingSpace = true;
        }
        pendingSpace = run.$1.endsWith(' ');
      }
    }

    void replaceBlock(
      TextLine? start,
      TextLine? end,
      String text, {
      PdfFont? font,
      double leftInset = 0,
      double rightMargin = 65,
      double bottomPadding = 2,
    }) {
      if (start == null || end == null) return;
      final left = start.bounds.left - leftInset;
      final top = start.bounds.top - 2;
      final bottom = end.bounds.top - bottomPadding;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 3,
          top,
          page.size.width - left + 3,
          bottom - top,
        ),
      );
      graphics.drawString(
        text,
        font ?? regular,
        brush: black,
        bounds: Rect.fromLTWH(
          left,
          start.bounds.top,
          page.size.width - left - rightMargin,
          bottom - start.bounds.top,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.justify,
          wordWrap: PdfWordWrapType.word,
          lineSpacing: 2,
        ),
      );
    }

    replaceBlock(
      introduction,
      itemOne,
      '',
    );
    drawRuns(
      introduction.bounds.left,
      introduction.bounds.top,
      page.size.width - introduction.bounds.left - 65,
      <(String, PdfFont)>[
        ('I, ', regular),
        ('ALYSSA LYNN TALINGTING, ', bold),
        ('of legal age, Filipino, and with office address at ', regular),
        ('$permanentAddress, ', regular),
        (
          'after having been duly sworn in accordance with law, hereby depose and state that:',
          regular,
        ),
      ],
    );
    if (itemOne != null && itemTwo != null) {
      final left = itemOne.bounds.left;
      final top = itemOne.bounds.top - 2;
      final bottom = itemTwo.bounds.top - 2;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 3,
          top,
          page.size.width - left + 3,
          bottom - top,
        ),
      );
      graphics.drawString(
        '1.',
        regular,
        brush: black,
        bounds: Rect.fromLTWH(left, itemOne.bounds.top, 18, 16),
      );
      drawRuns(
        left + 18,
        itemOne.bounds.top,
        page.size.width - left - 83,
        <(String, PdfFont)>[
          (
            'I am the duly elected and qualified Corporate Secretary of ',
            regular,
          ),
          ('MIKATA PRIME CORPORATION, ', bold),
          (
            'a corporation duly organized and existing under and by virtue of the laws of the Republic of the Philippines, with principal office address at ',
            regular,
          ),
          ('$permanentAddress;', regular),
        ],
      );
    }
    if (itemThree != null && resolved != null) {
      final left = itemThree.bounds.left;
      final top = itemThree.bounds.top - 2;
      final bottom = resolved.bounds.top - 2;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 3,
          top,
          page.size.width - left + 3,
          bottom - top,
        ),
      );
      graphics.drawString(
        '3.',
        regular,
        brush: black,
        bounds: Rect.fromLTWH(left, itemThree.bounds.top, 18, 16),
      );
      graphics.drawString(
        'At the special meeting of the Board of Directors of Corporation held '
        'on $meetingDate at its principal office, during which a quorum was '
        'present and acting throughout, the following resolutions were '
        'unanimously passed and approved:',
        regular,
        brush: black,
        bounds: Rect.fromLTWH(
          left + 18,
          itemThree.bounds.top,
          page.size.width - left - 83,
          bottom - itemThree.bounds.top,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.justify,
          wordWrap: PdfWordWrapType.word,
          lineSpacing: 2,
        ),
      );
    }
    if (resolved != null && itemFour != null) {
      final left = resolved.bounds.left;
      final width = page.size.width - left - 35;
      graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 3,
          resolved.bounds.top - 2,
          page.size.width - left + 3,
          itemFour.bounds.top - resolved.bounds.top,
        ),
      );

      double drawResolutionParagraph(
        double top,
        List<(String, PdfFont)> runs,
      ) {
        final words = <(String, PdfFont)>[];
        for (final run in runs) {
          for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
            if (word.isNotEmpty) words.add((word, run.$2));
          }
        }
        final lines = <List<(String, PdfFont)>>[];
        var line = <(String, PdfFont)>[];
        var usedWidth = 0.0;
        final normalSpace = resolutionItalic.measureString(' x').width -
            resolutionItalic.measureString('x').width;
        for (final word in words) {
          final wordWidth = word.$2.measureString(word.$1).width;
          final nextWidth =
              usedWidth + (line.isEmpty ? 0 : normalSpace) + wordWidth;
          if (line.isNotEmpty && nextWidth > width) {
            lines.add(line);
            line = <(String, PdfFont)>[];
            usedWidth = 0;
          }
          if (line.isNotEmpty) usedWidth += normalSpace;
          line.add(word);
          usedWidth += wordWidth;
        }
        if (line.isNotEmpty) lines.add(line);

        const lineHeight = 13.0;
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          final currentLine = lines[lineIndex];
          final wordsWidth = currentLine.fold<double>(
            0,
            (total, word) => total + word.$2.measureString(word.$1).width,
          );
          final isLastLine = lineIndex == lines.length - 1;
          final gap = currentLine.length <= 1
              ? 0.0
              : isLastLine
                  ? normalSpace
                  : (width - wordsWidth) / (currentLine.length - 1);
          var x = left;
          for (final word in currentLine) {
            final wordWidth = word.$2.measureString(word.$1).width;
            graphics.drawString(
              word.$1,
              word.$2,
              brush: black,
              bounds: Rect.fromLTWH(x, top, wordWidth + 2, lineHeight),
            );
            if (identical(word.$2, resolutionBoldItalic)) {
              graphics.drawString(
                word.$1,
                word.$2,
                brush: black,
                bounds: Rect.fromLTWH(x + .3, top, wordWidth + 2, lineHeight),
              );
            }
            x += wordWidth + gap;
          }
          top += lineHeight;
        }
        return top;
      }

      var resolutionTop = resolved.bounds.top;
      resolutionTop =
          drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
        ('"RESOLVED, ', resolutionItalic),
        ('that ', resolutionItalic),
        ('MIKATA PRIME CORPORATION ', resolutionBoldItalic),
        (
          'is hereby authorized to participate in the public bidding, negotiate, and enter into a contract with the ',
          resolutionItalic
        ),
        ('Municipality of $municipality, $province ', resolutionBoldItalic),
        ('for the project entitled: ', resolutionItalic),
        ('"$projectTitle";', resolutionBoldItalic),
      ]);
      resolutionTop += 7;
      resolutionTop =
          drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
        ('"RESOLVED FURTHER, ', resolutionItalic),
        ('that the Corporation hereby designates ', resolutionItalic),
        ('${representative.toUpperCase()}, ', resolutionBoldItalic),
        ('as the ', resolutionItalic),
        ('Authorized Representative ', resolutionBoldItalic),
        (
          'of the Corporation, to represent, sign, execute, submit, and deliver any and all documents, agreements, forms, and proposals necessary to effectively participate in the bidding and implement the aforementioned project, granting unto the said representative full power and authority to do and perform any and all acts required;',
          resolutionItalic
        ),
      ]);
      resolutionTop += 7;
      drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
        ('"RESOLVED FINALLY, ', resolutionItalic),
        (
          'that any and all prior actions taken by the Authorized Representative, as well as the Proprietor/President of the Corporation, ',
          resolutionItalic
        ),
        ('PATRICK CARLO P. DEDEL, ', resolutionBoldItalic),
        (
          'in connection with the foregoing are hereby approved, ratified, and confirmed as the acts of the Corporation."',
          resolutionItalic
        ),
      ]);
    }
    String ordinal(int day) {
      if (day >= 11 && day <= 13) return '${day}th';
      return switch (day % 10) {
        1 => '${day}st',
        2 => '${day}nd',
        3 => '${day}rd',
        _ => '${day}th',
      };
    }

    var legalDate = documentDate;
    try {
      final parsedDate = DateFormat('MMMM d, yyyy').parseStrict(documentDate);
      legalDate = '${ordinal(parsedDate.day)} day of '
          '${DateFormat('MMMM yyyy').format(parsedDate)}';
    } on FormatException {
      // Keep the supplied value if it is not in the expected display format.
    }
    const legalLocation = 'Municipality of __________, __________, Philippines';

    final lastPageIndex = document.pages.count - 1;
    TextLine? witnessLine;
    TextLine? subscribedLine;
    for (final line in lines) {
      if (line.pageIndex != lastPageIndex) continue;
      final compactText =
          line.text.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
      if (compactText.contains('INWITNESSWHEREOF') ||
          compactText.contains('HEREUNTOSETMYHAND')) {
        witnessLine ??= line;
      }
      if (compactText.contains('SUBSCRIBEDANDSWORN') ||
          compactText.contains('AFFIANTEXHIBITING')) {
        subscribedLine ??= line;
      }
    }

    void replaceLegalParagraph(
      TextLine? sourceLine,
      List<(String, PdfFont)> runs, {
      required double top,
      double height = 36,
    }) {
      // These jurat paragraphs are always on the final generated page (61).
      final targetPage = document.pages[document.pages.count - 1];
      final targetGraphics = targetPage.graphics;
      final left = sourceLine?.bounds.left ?? 51.0;
      final paragraphTop = sourceLine?.bounds.top ?? top;
      final width = targetPage.size.width - left - 45;
      targetGraphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(
          left - 4,
          paragraphTop - 2,
          targetPage.size.width - left + 4,
          height + 4,
        ),
      );
      var x = left;
      var y = paragraphTop;
      var hasWord = false;
      const lineHeight = 15.0;
      for (final run in runs) {
        for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          final measuredSpace = run.$2.measureString(' x').width -
              run.$2.measureString('x').width;
          final spaceWidth = hasWord
              ? (measuredSpace > 2.5 ? measuredSpace : run.$2.size * 0.28)
              : 0.0;
          final wordWidth = run.$2.measureString(word).width;
          if (x > left && x + spaceWidth + wordWidth > left + width) {
            x = left;
            y += lineHeight;
            hasWord = false;
          }
          if (hasWord) x += spaceWidth;
          targetGraphics.drawString(
            word,
            run.$2,
            brush: black,
            bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
          );
          x += wordWidth;
          hasWord = true;
        }
      }
    }

    replaceLegalParagraph(
        witnessLine,
        <(String, PdfFont)>[
          ('IN WITNESS WHEREOF, ', bold),
          ('I have hereunto set my hand this ', regular),
          ('$legalDate ', bold),
          ('at $legalLocation.', regular),
        ],
        top: 32);
    replaceLegalParagraph(
        subscribedLine,
        <(String, PdfFont)>[
          ('SUBSCRIBED AND SWORN ', bold),
          (
            'to before me this $legalDate at $legalLocation, affiant exhibiting to me their competent evidence of identity.',
            regular
          ),
        ],
        top: 126);
  }

  static String _formatBidAmount(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$whole.${parts.last}';
  }

  static String _bidAmountInWords(double amount) {
    final centavosTotal = (amount * 100).round();
    final pesos = centavosTotal ~/ 100;
    final centavos = centavosTotal % 100;
    final pesoWords = _integerInWords(pesos);
    if (centavos == 0) return '$pesoWords Pesos';
    return '$pesoWords Pesos and ${_integerInWords(centavos)} Centavos';
  }

  static String _integerInWords(int value) {
    if (value == 0) return 'Zero';
    const ones = <String>[
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = <String>[
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    String underThousand(int number) {
      final words = <String>[];
      if (number >= 100) {
        words.add('${ones[number ~/ 100]} Hundred');
        number %= 100;
      }
      if (number >= 20) {
        words.add(tens[number ~/ 10]);
        number %= 10;
      }
      if (number > 0) words.add(ones[number]);
      return words.join(' ');
    }

    final groups = <(int, String)>[
      (1000000000, 'Billion'),
      (1000000, 'Million'),
      (1000, 'Thousand'),
      (1, ''),
    ];
    final words = <String>[];
    var remaining = value;
    for (final group in groups) {
      final part = remaining ~/ group.$1;
      if (part == 0) continue;
      words.add(underThousand(part));
      if (group.$2.isNotEmpty) words.add(group.$2);
      remaining %= group.$1;
    }
    return words.join(' ');
  }

  static int _findBidPriceSummaryStartPage(PdfDocument document) {
    final lines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: 55,
      endPageIndex: 66.clamp(0, document.pages.count - 1).toInt(),
    );
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('SUMMARY OF BID PRICES')) return line.pageIndex;
    }
    return -1;
  }

  static int _findScheduleRequirementsStartPage(PdfDocument document) {
    final lines = PdfTextExtractor(document).extractTextLines(
      startPageIndex: 60,
      endPageIndex: 72.clamp(0, document.pages.count - 1).toInt(),
    );
    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (text.contains('SCHEDULE OF REQUIREMENTS')) return line.pageIndex;
    }
    return -1;
  }

  static int _drawScheduleRequirements(
    PdfDocument document,
    Map<String, String> values,
    int startPageIndex,
  ) {
    List<dynamic> specifications = const [];
    final encoded = values['technicalSpecifications'] ?? '';
    if (encoded.isNotEmpty) {
      final decoded = jsonDecode(encoded);
      if (decoded is List) specifications = decoded.take(72).toList();
    }
    final delivery = (values['deliveredWeeksMonths'] ?? '').trim();
    final includeTotal =
        (values['includeScheduleTotal'] ?? '').toLowerCase() == 'true';
    List<dynamic> savedPrices = const [];
    final encodedPrices = values['priceSchedule'] ?? '';
    if (encodedPrices.isNotEmpty) {
      final decoded = jsonDecode(encodedPrices);
      if (decoded is List) savedPrices = decoded.take(72).toList();
    }

    double number(dynamic value) =>
        double.tryParse((value ?? '').toString().replaceAll(',', '').trim()) ??
        0;
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      final grouped = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return '$grouped.${parts.last}';
    }

    String scheduleDescription(dynamic value) {
      final specification = value is Map ? value : const {};
      final name = (specification['specification'] ?? '').toString().trim();
      final details = (specification['parameter'] ?? '').toString().trim();
      if (details.isEmpty) return name;
      if (name.isEmpty || details == name) return details;
      return '$name\n$details';
    }

    // Schedule rows can contain complete, multi-line technical descriptions.
    // Size and paginate them by their rendered content instead of forcing every
    // row into a fixed 23-point box (which clipped everything after line one).
    int wrappedLineCount(String value) {
      const approximateCharactersPerLine = 32;
      final lines = value.split(RegExp(r'\r?\n'));
      return lines.fold<int>(0, (count, line) {
        final length = line.trim().length;
        return count +
            (length == 0 ? 1 : (length / approximateCharactersPerLine).ceil());
      });
    }

    final rowHeights = <double>[
      for (final value in specifications)
        (() {
          final description = scheduleDescription(value);
          return (wrappedLineCount(description) * 15.0 + 10.0)
              .clamp(23.0, 500.0)
              .toDouble();
        })(),
    ];
    final pageRowCounts = <int>[];
    var nextRow = 0;
    while (nextRow < specifications.length && pageRowCounts.length < 3) {
      // The first sheet has the document heading; continuation sheets have
      // more vertical room. Keep space below the table for the signature.
      final availableHeight = pageRowCounts.isEmpty ? 410.0 : 545.0;
      var usedHeight = 0.0;
      var count = 0;
      while (nextRow + count < specifications.length) {
        final height = rowHeights[nextRow + count];
        if (count > 0 && usedHeight + height > availableHeight) break;
        usedHeight += height;
        count++;
      }
      pageRowCounts.add(count);
      nextRow += count;
    }
    if (pageRowCounts.isEmpty) pageRowCounts.add(0);
    final pageCount = pageRowCounts.length;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
    final titleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      18,
      style: PdfFontStyle.bold,
    );
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      13,
      style: PdfFontStyle.bold,
    );
    final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    var itemIndex = 0;

    for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final page = document.pages[startPageIndex + pageNumber];
      final size = page.getClientSize();
      page.graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(0, 0, size.width, size.height),
      );
      const left = 42.0;
      final right = size.width - 42;
      final width = right - left;
      final columns = <double>[
        left,
        left + width * .11,
        left + width * .48,
        left + width * .62,
        left + width * .78,
        right,
      ];
      var tableTop = 35.0;
      if (pageNumber == 0) {
        page.graphics.drawString(
          'Schedule of Requirements',
          titleFont,
          brush: black,
          bounds: Rect.fromLTWH(left, 24, width, 24),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        final procuringEntity =
            (values['procuringEntity'] ?? '').trim().toUpperCase();
        final projectTitle =
            (values['projectTitle'] ?? '').trim().toUpperCase();
        final reference = (values['referenceNumber'] ?? '').trim();
        const labelLeft = 48.0;
        const colonLeft = 250.0;
        const valueLeft = 280.0;
        void headerRow(String label, String value, double y, double height) {
          page.graphics.drawString(label, labelFont,
              brush: black, bounds: Rect.fromLTWH(labelLeft, y, 190, 14));
          page.graphics.drawString(':', labelFont,
              brush: black, bounds: Rect.fromLTWH(colonLeft, y, 10, 14));
          page.graphics.drawString(
            value,
            valueFont,
            brush: black,
            bounds: Rect.fromLTWH(
                valueLeft, y, size.width - valueLeft - 45, height),
            format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
          );
        }

        headerRow('NAME OF THE PROCURING ENTITY', procuringEntity, 58, 15);
        headerRow('PROJECT TITLE', projectTitle, 76, 34);
        headerRow('REFERENCE NUMBER', reference, 112, 15);
        page.graphics.drawString(
          'The delivery schedule is expressed as weeks/month stipulated share after a delivery date which is the date of delivery to the project site.',
          labelFont,
          brush: black,
          bounds: Rect.fromLTWH(left, 135, width, 28),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
        );
        tableTop = 168;
      }
      const headerHeight = 48.0;
      final rowsOnPage = pageRowCounts[pageNumber];
      final tableBottom = tableTop +
          headerHeight +
          rowHeights
              .skip(itemIndex)
              .take(rowsOnPage)
              .fold<double>(0, (sum, height) => sum + height);
      for (final x in columns) {
        page.graphics
            .drawLine(gridPen, Offset(x, tableTop), Offset(x, tableBottom));
      }
      page.graphics
          .drawLine(gridPen, Offset(left, tableTop), Offset(right, tableTop));
      page.graphics.drawLine(
        gridPen,
        Offset(left, tableTop + headerHeight),
        Offset(right, tableTop + headerHeight),
      );
      final headers = <String>[
        'Item\nNo.',
        'Specification/s',
        includeTotal ? 'Qty/Unit' : 'Qty',
        includeTotal ? 'Total' : 'Unit',
        'Delivered\nWeeks/Months',
      ];
      for (var column = 0; column < headers.length; column++) {
        page.graphics.drawString(
          headers[column],
          valueFont,
          brush: black,
          bounds: Rect.fromLTWH(
            columns[column] + 2,
            tableTop + 2,
            columns[column + 1] - columns[column] - 4,
            headerHeight - 4,
          ),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );
      }
      var y = tableTop + headerHeight;
      for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
        final rowHeight = rowHeights[itemIndex];
        final specification = specifications[itemIndex] is Map
            ? specifications[itemIndex] as Map
            : const {};
        final quantity = (specification['quantity'] ?? '').toString().trim();
        final unit = (specification['unit'] ?? '').toString().trim();
        final saved =
            itemIndex < savedPrices.length && savedPrices[itemIndex] is Map
                ? savedPrices[itemIndex] as Map
                : const {};
        final adjustedUnitPrice =
            (number(saved['totalPricePerUnit']) - number(saved['deduction']))
                .clamp(0, double.infinity)
                .toDouble();
        final deliveredTotal = number(quantity) * adjustedUnitPrice;
        final texts = <String>[
          '${itemIndex + 1}',
          scheduleDescription(specification),
          includeTotal
              ? [quantity, unit].where((value) => value.isNotEmpty).join(' ')
              : quantity,
          includeTotal
              ? (deliveredTotal == 0 ? '' : money(deliveredTotal))
              : unit,
          delivery,
        ];
        for (var column = 0; column < texts.length; column++) {
          final cellBounds = Rect.fromLTWH(
            columns[column] + 3,
            y + 1,
            columns[column + 1] - columns[column] - 6,
            rowHeight - 2,
          );
          if (column == 1) {
            _drawMarkedSpecificationText(
              page.graphics,
              texts[column],
              rowFont,
              black,
              cellBounds,
            );
          } else {
            page.graphics.drawString(
              texts[column],
              column == 4 ? valueFont : rowFont,
              brush: black,
              bounds: cellBounds,
              format: PdfStringFormat(
                alignment: PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle,
                wordWrap: PdfWordWrapType.word,
              ),
            );
          }
        }
        y += rowHeight;
        page.graphics.drawLine(gridPen, Offset(left, y), Offset(right, y));
      }
      if (pageNumber == pageCount - 1) {
        _drawTechnicalSpecificationsSignatureAt(page, values, y + 25);
      }
    }
    return pageCount;
  }

  static int _drawBidPriceSummary(
    PdfDocument document,
    Map<String, String> values,
    int startPageIndex,
  ) {
    List<dynamic> specifications = const [];
    List<dynamic> savedPrices = const [];
    final encodedSpecifications = values['technicalSpecifications'] ?? '';
    final encodedPrices = values['priceSchedule'] ?? '';
    if (encodedSpecifications.isNotEmpty) {
      final decoded = jsonDecode(encodedSpecifications);
      if (decoded is List) specifications = decoded.take(72).toList();
    }
    if (encodedPrices.isNotEmpty) {
      final decoded = jsonDecode(encodedPrices);
      if (decoded is List) savedPrices = decoded.take(72).toList();
    }

    double number(dynamic value) =>
        double.tryParse((value ?? '').toString().replaceAll(',', '').trim()) ??
        0;
    String money(double value) {
      final parts = value.toStringAsFixed(2).split('.');
      final grouped = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return '$grouped.${parts.last}';
    }

    final summaryRows = <Map<String, dynamic>>[];
    for (var sourceIndex = 0;
        sourceIndex < specifications.length;
        sourceIndex++) {
      final source = specifications[sourceIndex] is Map
          ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
          : <String, dynamic>{};
      final lines = (source['specification'] ?? '')
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final descriptionLines = lines.isEmpty ? <String>[''] : lines;
      for (var start = 0; start < descriptionLines.length; start += 14) {
        summaryRows.add(<String, dynamic>{
          ...source,
          '_sourceIndex': sourceIndex,
          '_itemNumber': sourceIndex + 1,
          '_continuation': start > 0,
          '_descriptionLines': descriptionLines.skip(start).take(14).toList(),
        });
      }
    }
    final summaryRowHeights = <double>[
      for (final row in summaryRows)
        ((row['_descriptionLines'] as List).length * 17.0 + 8.0)
            .clamp(34.0, 260.0)
            .toDouble(),
    ];
    final pageRowCounts = <int>[];
    var nextRow = 0;
    while (nextRow < summaryRows.length && pageRowCounts.length < 8) {
      var usedHeight = 0.0;
      var count = 0;
      while (nextRow + count < summaryRows.length) {
        final height = summaryRowHeights[nextRow + count];
        if (count > 0 && usedHeight + height > 320) break;
        usedHeight += height;
        count++;
      }
      pageRowCounts.add(count);
      nextRow += count;
    }
    if (pageRowCounts.isEmpty) pageRowCounts.add(0);
    final pageCount = pageRowCounts.length;
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final red = PdfSolidBrush(PdfColor(220, 0, 0));
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
    final titleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      18,
      style: PdfFontStyle.bold,
    );
    final headerFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final priceFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    final instructionFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.italic,
    );
    final signatureBold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    var itemIndex = 0;
    var grandTotal = 0.0;

    for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
      final page = document.pages[startPageIndex + pageNumber];
      final size = page.getClientSize();
      page.graphics.drawRectangle(
        brush: white,
        bounds: Rect.fromLTWH(0, 0, size.width, size.height),
      );
      const left = 42.0;
      final right = size.width - 42;
      final itemRight = left + 48;
      final descriptionRight = left + (right - left) * .67;
      var tableTop = 38.0;
      if (pageNumber == 0) {
        page.graphics.drawString(
          'SUMMARY OF BID PRICES',
          titleFont,
          brush: black,
          bounds: Rect.fromLTWH(left, 25, right - left, 26),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        page.graphics.drawString(
          'The Procuring Entity may modify the table below as necessary to comply with the requirements of the Procurement Project',
          instructionFont,
          brush: black,
          bounds: Rect.fromLTWH(left, 51, right - left, 24),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        tableTop = 76;
      }
      const headerHeight = 40.0;
      const sectionHeight = 22.0;
      final rowsOnPage = pageRowCounts[pageNumber];
      final pageStartRow = itemIndex;
      final rowsHeight = summaryRowHeights
          .skip(pageStartRow)
          .take(rowsOnPage)
          .fold<double>(0, (sum, height) => sum + height);
      final dataBottom = tableTop + headerHeight + sectionHeight + rowsHeight;
      // Outer borders span the whole table. Internal column dividers skip the
      // merged "Specifications:" row, matching the source template.
      for (final x in <double>[left, right]) {
        page.graphics
            .drawLine(gridPen, Offset(x, tableTop), Offset(x, dataBottom));
      }
      final sectionBottom = tableTop + headerHeight + sectionHeight;
      for (final x in <double>[itemRight, descriptionRight]) {
        page.graphics.drawLine(
          gridPen,
          Offset(x, tableTop),
          Offset(x, tableTop + headerHeight),
        );
        page.graphics.drawLine(
          gridPen,
          Offset(x, sectionBottom),
          Offset(x, dataBottom),
        );
      }
      page.graphics
          .drawLine(gridPen, Offset(left, tableTop), Offset(right, tableTop));
      page.graphics.drawLine(
        gridPen,
        Offset(left, tableTop + headerHeight),
        Offset(right, tableTop + headerHeight),
      );
      const headers = <String>['Item\nNo.', 'Description/s', ''];
      final bounds = <Rect>[
        Rect.fromLTWH(left, tableTop, itemRight - left, headerHeight),
        Rect.fromLTWH(
            itemRight, tableTop, descriptionRight - itemRight, headerHeight),
        Rect.fromLTWH(
            descriptionRight, tableTop, right - descriptionRight, headerHeight),
      ];
      for (var column = 0; column < headers.length; column++) {
        page.graphics.drawString(
          headers[column],
          headerFont,
          brush: black,
          bounds: bounds[column],
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );
      }
      var y = tableTop + headerHeight;
      page.graphics.drawString(
        'Specifications:',
        headerFont,
        brush: black,
        bounds: Rect.fromLTWH(
            left + 4, y, descriptionRight - left - 8, sectionHeight),
        format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle),
      );
      y += sectionHeight;
      page.graphics.drawLine(gridPen, Offset(left, y), Offset(right, y));
      for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
        final specification = summaryRows[itemIndex];
        final sourceIndex = specification['_sourceIndex'] as int;
        final isContinuation = specification['_continuation'] == true;
        final saved =
            sourceIndex < savedPrices.length && savedPrices[sourceIndex] is Map
                ? savedPrices[sourceIndex] as Map
                : const {};
        final adjustedUnitPrice =
            (number(saved['totalPricePerUnit']) - number(saved['deduction']))
                .clamp(0, double.infinity)
                .toDouble();
        final delivered =
            (number(specification['quantity']) * adjustedUnitPrice)
                .roundToDouble();
        if (!isContinuation) grandTotal += delivered;
        final rowHeight = summaryRowHeights[itemIndex];
        final valuesForRow = <String>[
          isContinuation ? '' : '${specification['_itemNumber']}',
          (specification['_descriptionLines'] as List).join('\n'),
          isContinuation ? '' : money(delivered),
        ];
        final rowBounds = <Rect>[
          Rect.fromLTWH(left + 2, y + 1, itemRight - left - 4, rowHeight - 2),
          Rect.fromLTWH(itemRight + 4, y + 1, descriptionRight - itemRight - 8,
              rowHeight - 2),
          Rect.fromLTWH(descriptionRight + 4, y + 1,
              right - descriptionRight - 8, rowHeight - 2),
        ];
        for (var column = 0; column < valuesForRow.length; column++) {
          if (column == 1) {
            _drawMarkedSpecificationText(
              page.graphics,
              valuesForRow[column],
              rowFont,
              black,
              rowBounds[column],
            );
          } else {
            page.graphics.drawString(
              valuesForRow[column],
              column == 2 ? priceFont : rowFont,
              brush: column == 2 ? red : black,
              bounds: rowBounds[column],
              format: PdfStringFormat(
                alignment: PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle,
                wordWrap: PdfWordWrapType.word,
              ),
            );
          }
        }
        y += rowHeight;
        page.graphics.drawLine(gridPen, Offset(left, y), Offset(right, y));
      }

      if (pageNumber == pageCount - 1) {
        const totalHeight = 24.0;
        final totalBottom = y + totalHeight;
        page.graphics.drawLine(
            gridPen, Offset(left, totalBottom), Offset(right, totalBottom));
        for (final x in <double>[left, descriptionRight, right]) {
          page.graphics.drawLine(gridPen, Offset(x, y), Offset(x, totalBottom));
        }
        page.graphics.drawString(
          'TOTAL',
          headerFont,
          brush: black,
          bounds: Rect.fromLTWH(left, y, descriptionRight - left, totalHeight),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );
        page.graphics.drawString(
          money(grandTotal),
          headerFont,
          brush: red,
          bounds: Rect.fromLTWH(
              descriptionRight, y, right - descriptionRight, totalHeight),
          format: PdfStringFormat(
            alignment: PdfTextAlignment.center,
            lineAlignment: PdfVerticalAlignment.middle,
          ),
        );

        final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
        final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
        final signatureTop = totalBottom + 20;
        final nameValueLeft = left + 44;
        final submittedWidth = signatureBold.measureString(submittedBy).width;
        final nameLineRight = nameValueLeft +
            (submittedWidth + 32).clamp(150.0, 230.0).toDouble();
        page.graphics.drawString('Name:', signatureBold,
            brush: black, bounds: Rect.fromLTWH(left, signatureTop, 55, 18));
        page.graphics.drawString(submittedBy, signatureBold,
            brush: black,
            bounds: Rect.fromLTWH(
              nameValueLeft,
              signatureTop,
              nameLineRight - nameValueLeft,
              18,
            ));
        page.graphics.drawLine(
          gridPen,
          Offset(nameValueLeft, signatureTop + 16),
          Offset(nameLineRight, signatureTop + 16),
        );
        page.graphics.drawString('Signature:', signatureBold,
            brush: black,
            bounds: Rect.fromLTWH(left, signatureTop + 18, 72, 18));
        page.graphics.drawLine(
          gridPen,
          Offset(left + 62, signatureTop + 34),
          Offset(left + 300, signatureTop + 34),
        );
        const authorizationText =
            'Duly authorized to sign the Bid for and behalf of:';
        page.graphics.drawString(
          authorizationText,
          signatureBold,
          brush: black,
          bounds: Rect.fromLTWH(left, signatureTop + 36, 360, 18),
        );
        final authorizationWidth =
            signatureBold.measureString(authorizationText).width;
        final bidderLeft = left + authorizationWidth + 4;
        final bidderWidth = signatureBold.measureString(bidderName).width;
        final bidderLineRight =
            bidderLeft + (bidderWidth + 32).clamp(170.0, 260.0).toDouble();
        page.graphics.drawString(
          bidderName,
          signatureBold,
          brush: black,
          bounds: Rect.fromLTWH(
            bidderLeft,
            signatureTop + 36,
            bidderLineRight - bidderLeft,
            18,
          ),
        );
        page.graphics.drawLine(
          gridPen,
          Offset(bidderLeft, signatureTop + 52),
          Offset(bidderLineRight, signatureTop + 52),
        );
      }
    }
    return pageCount;
  }

  static void _drawTechnicalSpecificationsCompliance(
    PdfDocument document,
    Map<String, String> values,
  ) {
    final extractor = PdfTextExtractor(document);
    final lines = extractor.extractTextLines(
      startPageIndex: 46,
      endPageIndex: 48,
    );
    final itemLines = lines.where((line) {
      final itemNumber = int.tryParse(line.text.trim());
      return itemNumber != null &&
          itemNumber >= 1 &&
          itemNumber <= 72 &&
          line.bounds.left < 90;
    }).toList()
      ..sort((first, second) {
        final firstNumber = int.parse(first.text.trim());
        final secondNumber = int.parse(second.text.trim());
        return firstNumber.compareTo(secondNumber);
      });

    List<dynamic> specifications = const [];
    final encodedSpecifications = values['technicalSpecifications'] ?? '';
    if (encodedSpecifications.isNotEmpty) {
      final decoded = jsonDecode(encodedSpecifications);
      if (decoded is List) specifications = decoded;
    }

    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final boldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
      style: PdfFontStyle.bold,
    );
    const columns = <double>[36, 104, 301, 379, 468, 576];

    for (var index = 0; index < itemLines.length && index < 72; index++) {
      final itemLine = itemLines[index];
      final pageItems = itemLines
          .where((candidate) => candidate.pageIndex == itemLine.pageIndex)
          .toList()
        ..sort(
            (first, second) => first.bounds.top.compareTo(second.bounds.top));
      final pageItemIndex = pageItems.indexOf(itemLine);
      final center = itemLine.bounds.center.dy;
      final previousCenter = pageItemIndex > 0
          ? pageItems[pageItemIndex - 1].bounds.center.dy
          : null;
      final nextCenter = pageItemIndex + 1 < pageItems.length
          ? pageItems[pageItemIndex + 1].bounds.center.dy
          : null;
      final fallbackHeight = itemLine.bounds.height + 4;
      final rowTop = previousCenter == null
          ? center - ((nextCenter ?? center + fallbackHeight) - center) / 2
          : (previousCenter + center) / 2;
      final rowBottom = nextCenter == null
          ? center + (center - (previousCenter ?? center - fallbackHeight)) / 2
          : (center + nextCenter) / 2;
      final rowHeight = rowBottom - rowTop;
      final page = document.pages[itemLine.pageIndex];

      // Remove all original cell text in this row without covering grid lines.
      for (final line in lines.where(
        (candidate) => candidate.pageIndex == itemLine.pageIndex,
      )) {
        final lineCenter = line.bounds.center.dy;
        if (lineCenter < rowTop || lineCenter >= rowBottom) continue;
        if (line.bounds.left < columns.first ||
            line.bounds.right > columns.last + 2) {
          continue;
        }
        page.graphics.drawRectangle(
          brush: whiteBrush,
          bounds: Rect.fromLTWH(
            line.bounds.left - 1,
            line.bounds.top - 0.5,
            line.bounds.width + 2,
            line.bounds.height + 1,
          ),
        );
      }

      if (index >= specifications.length || specifications[index] is! Map) {
        continue;
      }
      final specification = specifications[index] as Map;
      final description = (specification['specification'] ?? '').toString();
      final quantity = (specification['quantity'] ?? '').toString();
      final unit = (specification['unit'] ?? '').toString();

      void drawCell(
        String text,
        int column, {
        bool bold = false,
        PdfTextAlignment alignment = PdfTextAlignment.left,
      }) {
        if (text.trim().isEmpty) return;
        page.graphics.drawString(
          text,
          bold ? boldFont : regularFont,
          brush: blackBrush,
          bounds: Rect.fromLTWH(
            columns[column] + 4,
            rowTop + 1,
            columns[column + 1] - columns[column] - 8,
            rowHeight - 2,
          ),
          format: PdfStringFormat(
            alignment: alignment,
            lineAlignment: PdfVerticalAlignment.middle,
            wordWrap: PdfWordWrapType.word,
          ),
        );
      }

      drawCell('${index + 1}', 0, alignment: PdfTextAlignment.center);
      drawCell(description, 1);
      drawCell(quantity, 2, alignment: PdfTextAlignment.center);
      drawCell(unit, 3, alignment: PdfTextAlignment.center);
      drawCell('COMPLY', 4, bold: true, alignment: PdfTextAlignment.center);
    }
  }
}
