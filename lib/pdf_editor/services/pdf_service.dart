import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'page_mapper.dart';

class PdfService {
  const PdfService._();

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
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
      );
      _drawSlccPrivateRow(document.pages[20], values);
    }

    // Page 45 NFCC form must follow the selected bid instead of retaining the
    // municipality and procuring entity embedded in the PDF template.
    if (document.pages.count > 44) {
      _drawNfccHeader(document.pages[44], values);
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

    // The manpower sheet is a static page in the source template. Replace its
    // embedded signature details with the values currently entered in the
    // editor, just like the generated schedules and specification sheets.
    _drawManpowerSignature(document, values);

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

    // Locate this form by its actual text after optional technical pages have
    // been removed, since its final page index can change.
    _drawBidSecuringDeclarationDetails(document, values);

    await Future<void>.delayed(const Duration(milliseconds: 1));

    // The scanned official receipt is only a sample attachment in the source
    // template and is not required in the generated bid documents.
    if (document.pages.count > 45) {
      document.pages.removeAt(45);
    }

    final List<int> outputBytes = await document.save();
    document.dispose();

    return Uint8List.fromList(outputBytes);
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

  static void _drawNfccHeader(
    PdfPage page,
    Map<String, String> values,
  ) {
    final municipality = (values['municipality'] ?? '').trim().toUpperCase();
    final province = (values['province'] ?? '').trim().toUpperCase();
    final procuringEntity =
        (values['procuringEntity'] ?? '').trim().toUpperCase();
    final contractTitle =
        'REBIDDING FOR THE PROCUREMENT OF VARIOUS CONSTRUCTION\n'
        'MATERIALS FOR DIFFERENT PROJECTS IN BARANGAY $municipality';

    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );
    final colonFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
    );
    final notaryFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
    );
    final format = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.top,
      wordWrap: PdfWordWrapType.word,
    );

    // Replace the template's fixed CITY OF CAGAYAN DE ORO venue with the
    // municipality and province selected for the current bid.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(30, 80, 410, 22),
    );
    graphics.drawString(
      'MUNICIPALITY OF $municipality, $province  ) S.S.',
      notaryFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(36, 84, 395, 18),
    );

    // Clear only the old value column, preserving the NFCC labels and colons.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(180, 215, 390, 64),
    );
    graphics.drawString(
      ':',
      colonFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(180, 218, 10, 16),
    );
    graphics.drawString(
      procuringEntity,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(184, 218, 375, 20),
      format: format,
    );
    graphics.drawString(
      ':',
      colonFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(180, 242, 10, 16),
    );
    graphics.drawString(
      contractTitle,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(184, 242, 375, 42),
      format: format,
    );
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
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
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

    final page = document.pages[declarationPageIndex];
    final pageLines = allLines
        .where((line) => line.pageIndex == declarationPageIndex)
        .toList();
    final graphics = page.graphics;
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final textFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final recipientFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      11,
      style: PdfFontStyle.italic,
    );
    final linePen = PdfPen(PdfColor(0, 0, 0), width: 0.7);
    final municipality = (values['municipality'] ?? '').trim().toUpperCase();
    final province = (values['province'] ?? '').trim().toUpperCase();
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

    // Cover the complete original sentence, including the fixed "May",
    // "Sumilao" and "Bukidnon" values in the source template.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(33, witnessTop - 2, 545, 42),
    );

    // Move the witness statement to the signature page, directly above the
    // "Duly authorized" caption.
    var witnessGraphics = graphics;
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
      witnessGraphics = document.pages[signaturePageIndex].graphics;
      witnessTop = dulyTop - 44;
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
    witnessGraphics.drawString(
      '2026 at Municipality',
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(yearLeft, witnessTop, 120, 15),
    );

    // Venue: Municipality of [municipality], [province].
    witnessGraphics.drawString(
      'of',
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36, witnessTop + 20, 12, 15),
    );
    witnessGraphics.drawLine(
      linePen,
      Offset(50, witnessTop + 32),
      Offset(153, witnessTop + 32),
    );
    witnessGraphics.drawString(
      ',',
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(155, witnessTop + 20, 5, 15),
    );
    witnessGraphics.drawLine(
      linePen,
      Offset(164, witnessTop + 32),
      Offset(267, witnessTop + 32),
    );
    witnessGraphics.drawString(
      '.',
      textFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(269, witnessTop + 20, 5, 15),
    );

    if (signaturePageIndex != null && dulyTop != null) {
      final signatureGraphics = document.pages[signaturePageIndex].graphics;
      final bidderName = (values['bidderName'] ?? '').trim();
      final submittedBy = (values['submittedBy'] ?? '').trim();
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
          dulyTop + 25,
          document.pages[signaturePageIndex].getClientSize().width,
          108,
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

    const columns = <double>[36, 94, 270, 335, 400, 490, 576];
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
    const headerHeight = 38.0;
    const minimumRowHeight = 18.0;
    const signatureSpace = 125.0;
    final firstPage = document.pages[46];
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
    final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final boldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
      style: PdfFontStyle.bold,
    );
    final statementTitleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );
    final statementBodyFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
    final specificationFormat = PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.word,
    );
    final specificationWidth = columns[2] - columns[1] - 6;
    final parameterWidth = columns[5] - columns[4] - 6;
    final rowHeights = <double>[
      for (final value in specifications)
        (() {
          final specification =
              value is Map ? (value['specification'] ?? '').toString() : '';
          final parameter =
              value is Map ? (value['parameter'] ?? '').toString() : '';
          final measuredSpecification = regularFont.measureString(
            specification,
            layoutArea: Size(specificationWidth, 500),
            format: specificationFormat,
          );
          final measuredParameter = regularFont.measureString(
            parameter,
            layoutArea: Size(parameterWidth, 500),
            format: specificationFormat,
          );
          final contentHeight =
              measuredSpecification.height > measuredParameter.height
                  ? measuredSpecification.height
                  : measuredParameter.height;
          return (contentHeight + 6).clamp(minimumRowHeight, 90).toDouble();
        })(),
    ];
    final pageRowCounts = <int>[];
    var rowsOnCurrentPage = 0;
    var usedHeight = 0.0;
    var technicalPageForLayout = 0;
    for (final height in rowHeights) {
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
        'the Bidder or supplier liable for prosecution subject to the '
        'provisions of ITB Clause Error! Reference source not found and/or GCC '
        'Clause Error! Reference source not found.';

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
    firstPage.graphics.drawString(
      statementText,
      statementBodyFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(
        columns.first + 6,
        statementTop + statementTitleHeight + 7,
        columns.last - columns.first - 12,
        statementBodyHeight - 14,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.justify,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.word,
      ),
    );

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
        page.graphics.drawLine(
          gridPen,
          Offset(columns.first, horizontalY),
          Offset(columns.last, horizontalY),
        );
      }

      const headers = <String>[
        'Item\nNo.',
        'Specification/s',
        'Qty',
        'Unit',
        'Parameter',
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
        final specification = specifications[itemIndex] is Map
            ? specifications[itemIndex] as Map
            : const {};
        final texts = <String>[
          '${itemIndex + 1}',
          (specification['specification'] ?? '').toString(),
          (specification['quantity'] ?? '').toString(),
          (specification['unit'] ?? '').toString(),
          (specification['parameter'] ?? '').toString(),
          'COMPLY',
        ];
        final rowHeight = rowHeights[itemIndex];
        for (var column = 0; column < texts.length; column++) {
          page.graphics.drawString(
            texts[column],
            column == 5 ? boldFont : regularFont,
            brush: blackBrush,
            bounds: Rect.fromLTWH(
              columns[column] + 3,
              rowTop + 1,
              columns[column + 1] - columns[column] - 6,
              rowHeight - 2,
            ),
            format: PdfStringFormat(
              alignment:
                  column == 1 ? PdfTextAlignment.left : PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
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
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
      style: PdfFontStyle.bold,
    );
    // Match the formal signature grid used by the contract-statement pages.
    const labelLeft = 36.0;
    const colonLeft = 112.0;
    const valueLeft = 150.0;

    void drawRow(String label, String value, double y) {
      page.graphics.drawString(
        label,
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(labelLeft, y, 68, 18),
      );
      page.graphics.drawString(
        ':',
        labelFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(colonLeft, y, 10, 18),
      );
      page.graphics.drawString(
        value,
        valueFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(valueLeft, y, 375, 18),
      );
    }

    drawRow('Submitted by', submittedBy, top);
    final nameWidth =
        valueFont.measureString(submittedBy).width.clamp(0, 375).toDouble();
    page.graphics.drawLine(
      PdfPen(PdfColor(0, 0, 0), width: 0.5),
      Offset(valueLeft, top + 12),
      Offset(valueLeft + nameWidth, top + 12),
    );
    page.graphics.drawString(
      '(Printed Name & Signature)',
      labelFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(valueLeft, top + 15, 210, 14),
    );
    drawRow('Designation', 'Authorized Representative', top + 31);
    drawRow('Name of Firm', bidderName, top + 48);
    drawRow('Date', date, top + 65);
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

    // Seven rows on the first page match the original clean layout; ten fit
    // on each continuation page. This supports all 72 specification items.
    final pageRowCounts = <int>[];
    var remaining = specifications.length;
    pageRowCounts.add(remaining.clamp(0, 7).toInt());
    remaining -= pageRowCounts.first;
    while (remaining > 0) {
      final count = remaining.clamp(0, 10).toInt();
      pageRowCounts.add(count);
      remaining -= count;
    }
    final pageCount = pageRowCounts.length.clamp(1, 8).toInt();
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
    final regular = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final bold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      8.5,
      style: PdfFontStyle.bold,
    );
    final detailFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);
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
        page.graphics.drawString('Name of Bidder: $bidder', detailFont,
            brush: black,
            bounds: Rect.fromLTWH(
              horizontalMargin,
              58,
              tableWidth * .48,
              14,
            ));
        page.graphics.drawString('Project ID No.: $reference', detailFont,
            brush: black,
            bounds: Rect.fromLTWH(
              horizontalMargin + tableWidth * .53,
              58,
              tableWidth * .25,
              14,
            ));
        page.graphics.drawString(
            'Pricing Details for Goods Offered from Within the Philippines',
            detailFont,
            brush: black,
            bounds: Rect.fromLTWH(
              horizontalMargin,
              77,
              tableWidth * .70,
              14,
            ));
        tableTop = 96;
      }
      page.graphics.drawString(
          'Page ${pageNumber + 1} of $pageCount', detailFont,
          brush: black,
          bounds: Rect.fromLTWH(size.width - horizontalMargin - 100,
              pageNumber == 0 ? 58 : 16, 100, 14),
          format: PdfStringFormat(alignment: PdfTextAlignment.right));
      const headerHeight = 92.0;
      final rowCount = pageRowCounts[pageNumber];
      final available = size.height -
          tableTop -
          headerHeight -
          (pageNumber == pageCount - 1 ? 112 : 25);
      final rowHeight =
          rowCount == 0 ? 30.0 : (available / rowCount).clamp(30.0, 48.0);
      final tableBottom = tableTop + headerHeight + rowHeight * rowCount;
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
        final specification = specifications[itemIndex] is Map
            ? specifications[itemIndex] as Map
            : const {};
        final saved =
            itemIndex < savedPrices.length && savedPrices[itemIndex] is Map
                ? savedPrices[itemIndex] as Map
                : const {};
        final total = number(saved['totalPricePerUnit']);
        final quantity = number(specification['quantity']);
        final delivered = (quantity * total).roundToDouble();
        grandTotal += delivered;
        final texts = <String>[
          '${itemIndex + 1}',
          (specification['specification'] ?? '').toString(),
          'PHL',
          (specification['quantity'] ?? '').toString(),
          (specification['unit'] ?? '').toString(),
          money(total * .50),
          money(total * .20),
          money(total * .30),
          '',
          money(total),
          money(delivered),
        ];
        for (var column = 0; column < texts.length; column++) {
          page.graphics.drawString(texts[column], regular,
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

    final pageLines = lines.where((line) => line.pageIndex == pageIndex);
    TextLine? submittedLabel;
    for (final line in pageLines) {
      final text = line.text.trim().toUpperCase();
      if (text == 'SUBMITTED BY:' || text == 'SUBMITTED BY') {
        submittedLabel = line;
        break;
      }
    }
    if (submittedLabel == null) return;

    final page = document.pages[pageIndex];
    final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
    final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
    final date = (values['date'] ?? '').trim();
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
      style: PdfFontStyle.bold,
    );
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
        91,
      ),
    );

    void drawRow(String label, String value, double y) {
      page.graphics.drawString(
        label,
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(labelLeft, y, 100, 15),
      );
      page.graphics.drawString(
        ':',
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(colonLeft, y, 10, 15),
      );
      page.graphics.drawString(
        value,
        valueFont,
        brush: black,
        bounds: Rect.fromLTWH(valueLeft, y, clearRight - valueLeft, 15),
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
      Offset(valueLeft, top + 12),
      Offset(valueLeft + nameWidth, top + 12),
    );
    page.graphics.drawString(
      '(Printed Name & Signature)',
      labelFont,
      brush: black,
      bounds: Rect.fromLTWH(valueLeft, top + 15, 210, 14),
    );
    drawRow('Designation', 'Authorized Representative', top + 31);
    drawRow('Name of Firm', bidderName, top + 48);
    drawRow('Date', date, top + 65);
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
    final pageCount = specifications.length <= 18
        ? 1
        : specifications.length <= 42
            ? 2
            : 3;
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
    final titleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      15,
      style: PdfFontStyle.bold,
    );
    final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 10);
    final valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );
    final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 9.5);
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
      const headerHeight = 44.0;
      const rowHeight = 23.0;
      final remaining = specifications.length - itemIndex;
      // Larger, more readable text needs fewer rows per sheet. This still
      // supports the full 72-item limit across the three source templates.
      final capacity = pageNumber == 0 ? 24 : 24;
      final rowsOnPage = remaining.clamp(0, capacity).toInt();
      final tableBottom = tableTop + headerHeight + rowsOnPage * rowHeight;
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
      const headers = <String>[
        'Item\nNo.',
        'Specification/s',
        'Qty',
        'Unit',
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
        final specification = specifications[itemIndex] is Map
            ? specifications[itemIndex] as Map
            : const {};
        final texts = <String>[
          '${itemIndex + 1}',
          (specification['specification'] ?? '').toString(),
          (specification['quantity'] ?? '').toString(),
          (specification['unit'] ?? '').toString(),
          delivery,
        ];
        for (var column = 0; column < texts.length; column++) {
          page.graphics.drawString(
            texts[column],
            column == 4 ? valueFont : rowFont,
            brush: black,
            bounds: Rect.fromLTWH(
              columns[column] + 3,
              y + 1,
              columns[column + 1] - columns[column] - 6,
              rowHeight - 2,
            ),
            format: PdfStringFormat(
              alignment:
                  column == 1 ? PdfTextAlignment.left : PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
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

    final pageCount = specifications.length <= 31
        ? 1
        : specifications.length <= 68
            ? 2
            : 3;
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final red = PdfSolidBrush(PdfColor(220, 0, 0));
    final white = PdfSolidBrush(PdfColor(255, 255, 255));
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
    final titleFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.bold,
    );
    final headerFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      8.5,
      style: PdfFontStyle.bold,
    );
    final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 8.5);
    final instructionFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      8.5,
      style: PdfFontStyle.italic,
    );
    final signatureFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final signatureBold = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
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
          bounds: Rect.fromLTWH(left, 28, right - left, 22),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        page.graphics.drawString(
          'The Procuring Entity may modify the table below as necessary to comply with the requirements of the Procurement Project',
          instructionFont,
          brush: black,
          bounds: Rect.fromLTWH(left, 52, right - left, 15),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        tableTop = 76;
      }
      const headerHeight = 28.0;
      const sectionHeight = 14.0;
      const rowHeight = 14.0;
      final remaining = specifications.length - itemIndex;
      final pageCapacity = pageNumber == 0 ? 31 : 37;
      final rowsOnPage = remaining.clamp(0, pageCapacity).toInt();
      final dataBottom =
          tableTop + headerHeight + sectionHeight + rowsOnPage * rowHeight;
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
        final specification = specifications[itemIndex] is Map
            ? specifications[itemIndex] as Map
            : const {};
        final saved =
            itemIndex < savedPrices.length && savedPrices[itemIndex] is Map
                ? savedPrices[itemIndex] as Map
                : const {};
        final delivered = (number(specification['quantity']) *
                number(saved['totalPricePerUnit']))
            .roundToDouble();
        grandTotal += delivered;
        final valuesForRow = <String>[
          '${itemIndex + 1}',
          (specification['specification'] ?? '').toString(),
          money(delivered),
        ];
        final rowBounds = <Rect>[
          Rect.fromLTWH(left + 2, y + 1, itemRight - left - 4, rowHeight - 2),
          Rect.fromLTWH(itemRight + 4, y + 1, descriptionRight - itemRight - 8,
              rowHeight - 2),
          Rect.fromLTWH(descriptionRight + 4, y + 1,
              right - descriptionRight - 8, rowHeight - 2),
        ];
        for (var column = 0; column < valuesForRow.length; column++) {
          page.graphics.drawString(
            valuesForRow[column],
            rowFont,
            brush: column == 2 ? red : black,
            bounds: rowBounds[column],
            format: PdfStringFormat(
              alignment:
                  column == 1 ? PdfTextAlignment.left : PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
        }
        y += rowHeight;
        page.graphics.drawLine(gridPen, Offset(left, y), Offset(right, y));
      }

      if (pageNumber == pageCount - 1) {
        const totalHeight = 20.0;
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
        final signatureTop = totalBottom + 18;
        final nameValueLeft = left + 44;
        final submittedWidth = signatureBold.measureString(submittedBy).width;
        final nameLineRight = nameValueLeft +
            (submittedWidth + 32).clamp(150.0, 230.0).toDouble();
        page.graphics.drawString('Name:', signatureBold,
            brush: black, bounds: Rect.fromLTWH(left, signatureTop, 48, 14));
        page.graphics.drawString(submittedBy, signatureBold,
            brush: black,
            bounds: Rect.fromLTWH(
              nameValueLeft,
              signatureTop,
              nameLineRight - nameValueLeft,
              14,
            ));
        page.graphics.drawLine(
          gridPen,
          Offset(nameValueLeft, signatureTop + 12),
          Offset(nameLineRight, signatureTop + 12),
        );
        page.graphics.drawString('Signature:', signatureBold,
            brush: black,
            bounds: Rect.fromLTWH(left, signatureTop + 13, 60, 14));
        page.graphics.drawLine(
          gridPen,
          Offset(left + 48, signatureTop + 25),
          Offset(left + 278, signatureTop + 25),
        );
        const authorizationText =
            'Duly authorized to sign the Bid for and behalf of:';
        page.graphics.drawString(
          authorizationText,
          signatureBold,
          brush: black,
          bounds: Rect.fromLTWH(left, signatureTop + 26, 300, 14),
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
            signatureTop + 26,
            bidderLineRight - bidderLeft,
            14,
          ),
        );
        page.graphics.drawLine(
          gridPen,
          Offset(bidderLeft, signatureTop + 38),
          Offset(bidderLineRight, signatureTop + 38),
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
