part of '../pdf_service.dart';

int _findBidSecuringDeclarationPage(PdfDocument document) {
  for (final line in PdfTextExtractor(document).extractTextLines()) {
    if (line.text.toUpperCase().contains('BID SECURING DECLARATION')) {
      return line.pageIndex;
    }
  }
  return -1;
}

Future<void> _replaceBidSecuringDeclarationWithoutTable(
  PdfDocument document,
  Map<String, String> values,
) async {
  final declarationIndex = _findBidSecuringDeclarationPage(document);
  if (declarationIndex < 0) return;

  final templateData = await rootBundle.load(
    values['bidSecuringDeclarationTemplate'] == 'initao_lgu'
        ? 'assets/pdf/BID SECURING DECLARATION_initao_template.pdf'
        : 'assets/pdf/BID SECURING DECLARATION_impasugong_template.pdf',
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

void _drawBidSecuringDeclarationWithoutTableLastPage(
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

void _drawBidSecuringDeclarationTableDetails(
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
