part of '../pdf_service.dart';

int _findOmnibusSwornStatementPage(PdfDocument document) {
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

void _drawOmnibusSwornStatementIdentity(
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
    address = address.isEmpty ? 'Tankulan, Manolo Fortich, Bukidnon' : address;
  } else {
    formalName = formalName.isEmpty ? 'Jho Ann Q. Cleopas' : formalName;
    civilStatus = civilStatus.isEmpty ? 'married' : civilStatus;
    address = address.isEmpty ? 'Tankulan, Manolo Fortich, Bukidnon' : address;
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
          (match.start > 0 && RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
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
    ('I am the duly authorized and designated representative of ', regularFont),
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
          (match.start > 0 && RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
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
          bounds:
              Rect.fromLTWH(officeX + .22, officeY, wordWidth + 1, lineHeight),
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
          (match.start > 0 && RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
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

void _drawOmnibusSwornStatementLastPage(
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
