part of '../pdf_service.dart';

Future<void> _replaceAfsSection(PdfDocument document) async {
  if (document.pages.count == 0) return;

  // ================================================================
  // FIND THE REAL TECHNICAL SPECIFICATIONS / NFCC PAGE
  // ================================================================

  final extractor = PdfTextExtractor(document);

  final pageTexts = <String>[
    for (var i = 0; i < document.pages.count; i++)
      extractor
          .extractText(
            startPageIndex: i,
            endPageIndex: i,
          )
          .replaceAll('\u0000', '')
          .replaceAll(RegExp(r'\s+'), '')
          .toUpperCase(),
  ];

  int? technicalSpecificationsPageIndex;
  int? nfccPageIndex;

  for (var i = 0; i < pageTexts.length; i++) {
    final text = pageTexts[i];

    final isChecklistPage =
        text.contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS') ||
        text.contains('TABLEOFCONTENTS');

    if (!isChecklistPage &&
        technicalSpecificationsPageIndex == null &&
        text.contains('TECHNICALSPECIFICATIONS')) {
      technicalSpecificationsPageIndex = i;
    }

    if (!isChecklistPage &&
        nfccPageIndex == null &&
        text.contains('NETFINANCIALCONTRACTINGCAPACITY')) {
      nfccPageIndex = i;
    }
  }

  // NFCC is structurally immediately before Technical Specifications.
  if (technicalSpecificationsPageIndex != null &&
      technicalSpecificationsPageIndex > 0) {
    nfccPageIndex = technicalSpecificationsPageIndex - 1;
  }

  if (nfccPageIndex == null) {
    return;
  }

  // ================================================================
  // FIND OLD AFS RANGE
  // ================================================================
  //
  // The ORIGINAL/master bidding document has 18 old AFS pages.
  //
  // This is ONLY the number of OLD pages to remove.
  // It does NOT limit the replacement AFS.
  // ================================================================

  const legacyAfsPageCount = 18;

  final afsPageIndex = nfccPageIndex - legacyAfsPageCount;

  if (afsPageIndex < 0 ||
      afsPageIndex >= document.pages.count) {
    return;
  }

  var removableAfsPageCount =
      nfccPageIndex - afsPageIndex;

  removableAfsPageCount = removableAfsPageCount
      .clamp(0, legacyAfsPageCount)
      .toInt();

  // ================================================================
  // LOAD NEW AFS
  // ================================================================

  final data = await rootBundle.load(
    'assets/pdf/AFS_template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  try {
    if (sourceDocument.pages.count == 0) {
      return;
    }

    // ==============================================================
    // REMOVE OLD AFS
    // ==============================================================

    for (var i = 0; i < removableAfsPageCount; i++) {
      if (afsPageIndex >= document.pages.count) {
        break;
      }

      document.pages.removeAt(afsPageIndex);

      if (i % 4 == 3) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    // ==============================================================
    // INSERT ALL NEW AFS PAGES
    // ==============================================================
    //
    // 15 pages  -> all 15
    // 50 pages  -> all 50
    // 90 pages  -> all 90
    //
    // No fixed replacement page limit.
    // ==============================================================

    const a4Size = Size(
      595.28,
      841.89,
    );

    // These are internal markers.
    // White + 1pt = invisible on the page,
    // but still extractable later.
    final markerFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      1,
    );

    final invisibleBrush = PdfSolidBrush(
      PdfColor(255, 255, 255),
    );

    for (var index = 0;
        index < sourceDocument.pages.count;
        index++) {
      final sourcePage = sourceDocument.pages[index];

      final sourceSize = sourcePage.size;

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

      // ============================================================
      // EXACT AFS START MARKER
      // ============================================================

      if (index == 0) {
        targetPage.graphics.drawString(
          'PHILGEPS_AFS_START',
          markerFont,
          brush: invisibleBrush,
          bounds: const Rect.fromLTWH(
            1,
            1,
            120,
            5,
          ),
        );
      }

      // ============================================================
      // EXACT AFS END MARKER
      // ============================================================

      if (index == sourceDocument.pages.count - 1) {
        targetPage.graphics.drawString(
          'PHILGEPS_AFS_END',
          markerFont,
          brush: invisibleBrush,
          bounds: const Rect.fromLTWH(
            1,
            7,
            120,
            5,
          ),
        );
      }

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

  // ================================================================
  // FIND NFCC DYNAMICALLY
  // ================================================================

  final extractor = PdfTextExtractor(document);

  final pageTexts = <String>[
    for (var i = 0; i < document.pages.count; i++)
      extractor
          .extractText(
            startPageIndex: i,
            endPageIndex: i,
          )
          .replaceAll('\u0000', '')
          .replaceAll(RegExp(r'\s+'), '')
          .toUpperCase(),
  ];

  int? nfccPageIndex;
  int? technicalSpecificationsPageIndex;

  for (var i = 0; i < pageTexts.length; i++) {
    final text = pageTexts[i];

    final isChecklistPage =
        text.contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS') ||
        text.contains('TABLEOFCONTENTS');

    if (!isChecklistPage &&
        technicalSpecificationsPageIndex == null &&
        text.contains('TECHNICALSPECIFICATIONS')) {
      technicalSpecificationsPageIndex = i;
    }

    if (!isChecklistPage &&
        nfccPageIndex == null &&
        text.contains('NETFINANCIALCONTRACTINGCAPACITY')) {
      nfccPageIndex = i;
    }
  }

  // Most reliable structure:
  //
  // AFS
  // NFCC
  // Technical Specifications
  //
  // Therefore NFCC is immediately before Technical Specifications.
  if (technicalSpecificationsPageIndex != null &&
      technicalSpecificationsPageIndex > 0) {
    nfccPageIndex = technicalSpecificationsPageIndex - 1;
  }

  if (nfccPageIndex == null ||
      nfccPageIndex < 0 ||
      nfccPageIndex >= document.pages.count) {
    return;
  }

  // ================================================================
  // LOAD NFCC TEMPLATE
  // ================================================================

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

  // ================================================================
  // VALUES
  // ================================================================

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

  // ================================================================
  // CLEAR OLD HEADER
  // ================================================================

  graphics.drawRectangle(
    brush: white,
    bounds: Rect.fromLTWH(
      18,
      58,
      sourcePage.size.width - 36,
      110,
    ),
  );

  // ================================================================
  // HEADER HELPER
  // ================================================================

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

  // ================================================================
  // SIGNATORY BLOCK
  // ================================================================

  final footerTop =
      sourcePage.size.height - 235;

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

  final submittedWidth = bold
      .measureString(
        submittedBy.toUpperCase(),
      )
      .width;

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

  // ================================================================
  // SAVE / REOPEN NFCC
  // ================================================================

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

    // Remove old NFCC.
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