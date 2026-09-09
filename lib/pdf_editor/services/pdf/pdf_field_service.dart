part of '../pdf_service.dart';

const String _permanentBusinessAddress =
    'ZONE 13, CARMEN, CAGAYAN DE ORO CITY, MISAMIS ORIENTAL, 9000';

void _drawPageOne(
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

    for (final word in _pdfStandardFontSafeText(text).split(RegExp(r'\s+'))) {
      final candidate = _pdfStandardFontSafeText(
        currentLine.isEmpty ? word : '$currentLine $word',
      );

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

void _drawContractStatementPage(
  PdfPage page,
  Map<String, String> values, {
  required double signatureTop,
  required double signatureClearTop,
  required double businessAddressClearTop,
  required double businessAddressTop,
}) {
  // This source form uses landscape-width coordinates but some template
  // revisions carry a /Rotate value that makes readers display it as a
  // portrait sheet. Normalize the page orientation before adding fields.
  page.rotation = PdfPageRotateAngle.rotateAngle0;
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
  final projectLineCount =
      wrappedProjectTitle.isEmpty ? 1 : wrappedProjectTitle.split('\n').length;
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

void _drawManpowerSignature(
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
    final text = line.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
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
