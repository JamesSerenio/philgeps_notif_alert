part of '../pdf_service.dart';

Future<void> _replaceAfsSection(PdfDocument document) async {
  if (document.pages.count == 0) return;

  // Find Technical Specifications and NFCC dynamically.
  final lines = PdfTextExtractor(document).extractTextLines();

  int? technicalSpecificationsPageIndex;
  int? nfccPageIndex;

  for (final line in lines) {
    final text = line.text
        .replaceAll('\u0000', '')
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final isChecklistText =
        text.contains('CHECKLIST OF ELIGIBILITY REQUIREMENTS') ||
        text.contains('TABLE OF CONTENTS');

    if (!isChecklistText &&
        technicalSpecificationsPageIndex == null &&
        text.contains('TECHNICAL SPECIFICATIONS')) {
      technicalSpecificationsPageIndex = line.pageIndex;
    }

    if (!isChecklistText &&
        nfccPageIndex == null &&
        text.contains('NET FINANCIAL CONTRACTING CAPACITY')) {
      nfccPageIndex = line.pageIndex;
    }
  }

  // NFCC is immediately before Technical Specifications.
  if (technicalSpecificationsPageIndex != null &&
      technicalSpecificationsPageIndex > 0) {
    nfccPageIndex = technicalSpecificationsPageIndex - 1;
  }

  if (nfccPageIndex == null) return;

  // This is ONLY the number of OLD AFS pages in the master PDF.
  // It does NOT limit the new AFS page count.
  const legacyAfsPageCount = 18;

  final afsPageIndex = nfccPageIndex - legacyAfsPageCount;

  if (afsPageIndex < 0 || afsPageIndex >= document.pages.count) {
    return;
  }

  var removableAfsPageCount = nfccPageIndex - afsPageIndex;

  removableAfsPageCount = removableAfsPageCount
      .clamp(0, legacyAfsPageCount)
      .toInt();

  final data = await rootBundle.load(
    'assets/pdf/AFS_template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  try {
    if (sourceDocument.pages.count == 0) return;

    // Remove OLD AFS pages.
    for (var i = 0; i < removableAfsPageCount; i++) {
      if (afsPageIndex >= document.pages.count) break;

      document.pages.removeAt(afsPageIndex);

      if (i % 4 == 3) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    // Insert ALL pages from the new AFS.
    // No fixed maximum page count.
    const a4Size = Size(
      595.28,
      841.89,
    );

    for (var index = 0;
        index < sourceDocument.pages.count;
        index++) {
      final sourcePage = sourceDocument.pages[index];
      final sourceSize = sourcePage.size;

      final widthScale = a4Size.width / sourceSize.width;
      final heightScale = a4Size.height / sourceSize.height;

      final scale = widthScale < heightScale
          ? widthScale
          : heightScale;

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

      if (index % 3 == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 2),
        );
      }
    }
  } finally {
    sourceDocument.dispose();
  }
}

Future<void> _replaceNfccPage(
  PdfDocument document,
  Map<String, String> values,
) async {
  if (document.pages.count == 0) return;

  int? nfccPageIndex;
  int? technicalSpecificationsPageIndex;

  final documentLines =
      PdfTextExtractor(document).extractTextLines();

  for (final line in documentLines) {
    final text = line.text
        .replaceAll('\u0000', '')
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final isChecklistText =
        text.contains('CHECKLIST OF ELIGIBILITY REQUIREMENTS') ||
        text.contains('TABLE OF CONTENTS');

    if (!isChecklistText &&
        technicalSpecificationsPageIndex == null &&
        text.contains('TECHNICAL SPECIFICATIONS')) {
      technicalSpecificationsPageIndex = line.pageIndex;
    }

    if (!isChecklistText &&
        nfccPageIndex == null &&
        text.contains('NET FINANCIAL CONTRACTING CAPACITY')) {
      nfccPageIndex = line.pageIndex;
    }
  }

  // NFCC is immediately before Technical Specifications.
  if (technicalSpecificationsPageIndex != null &&
      technicalSpecificationsPageIndex > 0) {
    nfccPageIndex = technicalSpecificationsPageIndex - 1;
  }

  if (nfccPageIndex == null ||
      nfccPageIndex < 0 ||
      nfccPageIndex >= document.pages.count) {
    return;
  }

  final data = await rootBundle.load(
    'assets/pdf/NFCC_Template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  if (sourceDocument.pages.count == 0) {
    sourceDocument.dispose();
    return;
  }

  final sourcePage = sourceDocument.pages[0];
  final graphics = sourcePage.graphics;

  final white = PdfSolidBrush(
    PdfColor(255, 255, 255),
  );

  final black = PdfSolidBrush(
    PdfColor(0, 0, 0),
  );

  final red = PdfSolidBrush(
    PdfColor(210, 0, 0),
  );

  final regular = PdfStandardFont(
    PdfFontFamily.helvetica,
    12,
  );

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

  final headerLabelFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
  );

  final headerValueFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
    style: PdfFontStyle.bold,
  );

  final procuringEntity =
      (values['procuringEntity'] ?? '').trim();

  final referenceNumber =
      (values['referenceNumber'] ?? '').trim();

  final projectTitle =
      (values['projectTitle'] ?? '').trim();

  final bidderName =
      (values['bidderName'] ?? '').trim();

  final submittedBy =
      (values['submittedBy'] ?? '').trim();

  final date =
      (values['date'] ?? '').trim();

  const address = _permanentBusinessAddress;

  // Clear old variable header.
  graphics.drawRectangle(
    brush: white,
    bounds: Rect.fromLTWH(
      18,
      58,
      sourcePage.size.width - 36,
      110,
    ),
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
      bounds: Rect.fromLTWH(
        20,
        top,
        174,
        18,
      ),
    );

    graphics.drawString(
      ':',
      headerLabelFont,
      brush: black,
      bounds: Rect.fromLTWH(
        196,
        top,
        10,
        18,
      ),
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
      format: PdfStringFormat(
        wordWrap: PdfWordWrapType.word,
      ),
    );
  }

  drawHeader(
    'NAME OF THE PROCURING ENTITY',
    procuringEntity.toUpperCase(),
    61,
  );

  drawHeader(
    'PROJECT TITLE',
    projectTitle.toUpperCase(),
    76,
    valueHeight: 30,
  );

  drawHeader(
    'REFERENCE NUMBER',
    referenceNumber,
    108,
  );

  drawHeader(
    'CONTRACTOR',
    bidderName.toUpperCase(),
    123,
  );

  drawHeader(
    'ADDRESS',
    address,
    138,
    valueHeight: 27,
  );

  // Signatory block.
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
    bounds: Rect.fromLTWH(
      20,
      footerTop,
      105,
      18,
    ),
  );

  graphics.drawString(
    submittedBy.toUpperCase(),
    bold,
    brush: black,
    bounds: Rect.fromLTWH(
      125,
      footerTop,
      330,
      18,
    ),
  );

  final submittedWidth =
      bold.measureString(submittedBy.toUpperCase()).width;

  graphics.drawLine(
    PdfPen(
      PdfColor(0, 0, 0),
      width: 0.7,
    ),
    Offset(
      125,
      footerTop + 14,
    ),
    Offset(
      125 + submittedWidth,
      footerTop + 14,
    ),
  );

  graphics.drawString(
    'Designation',
    regular,
    brush: black,
    bounds: Rect.fromLTWH(
      20,
      footerTop + 18,
      105,
      18,
    ),
  );

  graphics.drawString(
    ':    Authorized Representative',
    italic,
    brush: black,
    bounds: Rect.fromLTWH(
      125,
      footerTop + 18,
      330,
      18,
    ),
  );

  graphics.drawString(
    'Date',
    regular,
    brush: black,
    bounds: Rect.fromLTWH(
      20,
      footerTop + 36,
      105,
      18,
    ),
  );

  graphics.drawString(
    ':    $date',
    regular,
    brush: black,
    bounds: Rect.fromLTWH(
      125,
      footerTop + 36,
      280,
      18,
    ),
  );

  // Save/reopen so new graphics are included.
  final modifiedSourceBytes =
      await sourceDocument.save();

  sourceDocument.dispose();

  final flattenedSourceDocument = PdfDocument(
    inputBytes: modifiedSourceBytes,
  );

  try {
    if (flattenedSourceDocument.pages.count == 0) {
      return;
    }

    final flattenedSourcePage =
        flattenedSourceDocument.pages[0];

    document.pages.removeAt(
      nfccPageIndex,
    );

    const a4Size = Size(
      595.28,
      841.89,
    );

    final sourceSize =
        flattenedSourcePage.size;

    final widthScale =
        a4Size.width / sourceSize.width;

    final heightScale =
        a4Size.height / sourceSize.height;

    final scale = widthScale < heightScale
        ? widthScale
        : heightScale;

    final fittedSize = Size(
      sourceSize.width * scale,
      sourceSize.height * scale,
    );

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
  } finally {
    flattenedSourceDocument.dispose();
  }
}

/// Standard PDF fonts do not contain Unicode checkmark glyphs.
/// Normalize common pasted checkmarks before any page is drawn so one
/// specification cannot abort the entire document with "character 9971".