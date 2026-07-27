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

    // Pages 47-49 form one Technical Specifications section. Its signatory
    // and date block is located on the final page (page 49).
    if (document.pages.count > 48) {
      _drawTechnicalSpecificationsSignature(document.pages[48], values);
    }

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

    final percent = value('slccPercent');
    const rowTop = 280.0;
    const rowBottom = 406.0;
    const columns = <double>[37, 148, 283, 370, 482, 575, 690, 821];

    // Clear the complete PRIVATE row, then rebuild its borders. This removes
    // every trace of the fixed sample contract without touching the NONE row.
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(37, rowTop, 784, rowBottom - rowTop),
    );
    final gridPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
    graphics.drawLine(
      gridPen,
      const Offset(37, rowTop),
      const Offset(821, rowTop),
    );
    graphics.drawLine(
      gridPen,
      const Offset(37, rowBottom),
      const Offset(821, rowBottom),
    );
    for (final x in columns) {
      graphics.drawLine(gridPen, Offset(x, rowTop), Offset(x, rowBottom));
    }

    final privateLabelFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: PdfFontStyle.bold,
    );
    graphics.drawString(
      'PRIVATE',
      privateLabelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(42, 282, 102, 18),
    );

    final cells = <({Rect bounds, String text, bool bold, bool centered})>[
      (
        bounds: const Rect.fromLTWH(153, 284, 125, 118),
        text: [
          labeled('a.', 'slccOwnerName'),
          labeled('b.', 'slccAddressTelephone'),
          labeled('c.', 'slccNumber'),
        ].join('\n'),
        bold: false,
        centered: false,
      ),
      (
        bounds: const Rect.fromLTWH(287, 284, 79, 118),
        text: value('slccNatureOfWork'),
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(374, 284, 104, 118),
        text: value('slccDescription'),
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(486, 284, 85, 118),
        text: percent.isEmpty
            ? ''
            : percent.endsWith('%')
                ? percent
                : '$percent%',
        bold: false,
        centered: true,
      ),
      (
        bounds: const Rect.fromLTWH(579, 284, 107, 118),
        text: [
          labeled('a.', 'slccAmountOfAward'),
          labeled('b.', 'slccCompletionDuration'),
        ].join('\n'),
        bold: false,
        centered: false,
      ),
      (
        bounds: const Rect.fromLTWH(694, 284, 123, 118),
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
          alignment: cell.centered
              ? PdfTextAlignment.center
              : PdfTextAlignment.left,
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
}
