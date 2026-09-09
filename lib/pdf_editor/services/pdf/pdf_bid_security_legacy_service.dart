part of '../pdf_service.dart';

void _drawBidSecuringDeclarationDetails(
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
  final pageLines =
      allLines.where((line) => line.pageIndex == declarationPageIndex).toList();
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
        (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
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
        document.pages[line.pageIndex].getClientSize().width - bounds.left - 20,
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

void _drawBidSecuringDeclarationFixedLastPage(
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
