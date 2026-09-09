part of '../pdf_service.dart';

Future<void> _replacePhilgepsCertificateSection(
  PdfDocument document,
) async {
  final lines = PdfTextExtractor(document).extractTextLines();
  int? certificatePageIndex;
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('CERTIFICATE OF PHILGEPS REGISTRATION')) {
      certificatePageIndex = line.pageIndex;
      break;
    }
  }
  if (certificatePageIndex == null) return;

  final data = await rootBundle.load('assets/pdf/certificate_template.pdf');
  final sourceDocument = PdfDocument(inputBytes: data.buffer.asUint8List());
  if (sourceDocument.pages.count == 0) {
    sourceDocument.dispose();
    return;
  }

  // The bundled bid template contains the old three-page PhilGEPS
  // certificate. Replace that complete section with the newly supplied
  // certificate PDF while preserving every other page and its position.
  const oldCertificatePageCount = 3;
  for (var removed = 0;
      removed < oldCertificatePageCount &&
          certificatePageIndex < document.pages.count;
      removed++) {
    document.pages.removeAt(certificatePageIndex);
  }

  for (var index = 0; index < sourceDocument.pages.count; index++) {
    final sourcePage = sourceDocument.pages[index];
    final sourceSize = sourcePage.size;
    final targetPage = document.pages.insert(
      certificatePageIndex + index,
      sourceSize,
      PdfMargins()..all = 0,
    );
    targetPage.graphics.drawPdfTemplate(
      sourcePage.createTemplate(),
      Offset.zero,
      sourceSize,
    );
  }
  sourceDocument.dispose();
}

void _drawAfterSalesServiceCertificate(
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
  final afterSalesYears = parsedAfterSalesYears < 1 ? 1 : parsedAfterSalesYears;
  final afterSalesYearsInWords = _integerInWords(afterSalesYears).toLowerCase();
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
          (match.start > 0 && RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
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
  final supportTop = secondParagraphLine?.bounds.top ?? (certificateTop + 145);
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
          (match.start > 0 && RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
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

void _drawProductWarrantyCertificate(
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

void _replaceCertificateHeaderAddress(
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
