part of '../pdf_service.dart';

Future<void> _replaceAfsSection(PdfDocument document) async {
  // After the selected SLCC template has been inserted, the legacy Audited
  // Financial Statements occupy PDF pages 29-46 inclusive.
  const afsPageIndex = 28;
  const legacyAfsPageCount = 18;
  if (afsPageIndex >= document.pages.count) return;

  // Earlier optional-page cleanup can shorten the pages before Technical
  // Specifications (notably when SLCC=None). Never let the fixed legacy AFS
  // range consume NFCC or the first Technical Specifications page.
  var removableAfsPageCount = legacyAfsPageCount;
  final lines = PdfTextExtractor(document).extractTextLines();
  for (final line in lines) {
    final title =
        line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.pageIndex >= afsPageIndex &&
        title.contains('TECHNICAL SPECIFICATIONS')) {
      removableAfsPageCount = (line.pageIndex - afsPageIndex - 1)
          .clamp(0, legacyAfsPageCount)
          .toInt();
      break;
    }
  }

  final data = await rootBundle.load('assets/pdf/AFS_template.pdf');
  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  for (var page = 0;
      page < removableAfsPageCount && afsPageIndex < document.pages.count;
      page++) {
    document.pages.removeAt(afsPageIndex);
    if (page % 3 == 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
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
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  sourceDocument.dispose();
}

Future<void> _replaceNfccPage(
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
    if (line.pageIndex >= 20 && text.contains('TECHNICAL SPECIFICATIONS')) {
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
  const address = _permanentBusinessAddress;

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
  drawHeader('PROJECT TITLE', projectTitle.toUpperCase(), 76, valueHeight: 30);
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
  final fittedSize = Size(sourceSize.width * scale, sourceSize.height * scale);
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
