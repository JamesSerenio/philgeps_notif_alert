part of '../pdf_service.dart';

Future<_AfsPlacement?> _replaceAfsSection(
  PdfDocument document,
) async {
  if (document.pages.count == 0) {
    throw StateError(
      'Cannot replace AFS: document contains no pages.',
    );
  }

  // ============================================================
  // FIND TECHNICAL SPECIFICATIONS
  // ============================================================
  //
  // NFCC is structurally the page immediately before
  // Technical Specifications.
  //
  // We intentionally do NOT calculate AFS from:
  //
  // PhilGEPS + 1
  // Annex A + 1
  //
  // because those ranges may contain other required documents.
  //
  // The current replacement AFS has exactly 15 pages.
  // Therefore the old AFS block we replace is the 15 pages
  // immediately before NFCC.
  // ============================================================

  final textLines =
      PdfTextExtractor(document).extractTextLines();

  int? technicalSpecificationsPageIndex;

  for (final line in textLines) {
    final text = line.text
        .replaceAll('\u0000', '')
        .toUpperCase()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    final isChecklistText =
        text.contains(
          'CHECKLIST OF ELIGIBILITY REQUIREMENTS',
        ) ||
        text.contains(
          'TABLE OF CONTENTS',
        );

    if (!isChecklistText &&
        technicalSpecificationsPageIndex == null &&
        text.contains(
          'TECHNICAL SPECIFICATIONS',
        )) {
      technicalSpecificationsPageIndex =
          line.pageIndex;
    }
  }

  if (technicalSpecificationsPageIndex == null ||
      technicalSpecificationsPageIndex <= 0) {
    throw StateError(
      'Cannot replace AFS: '
      'Technical Specifications anchor not found.',
    );
  }

  // ============================================================
  // NFCC
  // ============================================================

  final nfccPageIndex =
      technicalSpecificationsPageIndex - 1;

  if (nfccPageIndex < 0 ||
      nfccPageIndex >= document.pages.count) {
    throw StateError(
      'Cannot replace AFS: invalid NFCC position. '
      'nfcc=$nfccPageIndex '
      'technical=$technicalSpecificationsPageIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  // ============================================================
  // LOAD AFS TEMPLATE
  // ============================================================

  final data = await rootBundle.load(
    'assets/pdf/AFS_template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  try {
    final sourceAfsPageCount =
        sourceDocument.pages.count;

    // The supplied AFS_template.pdf must always have 15 pages.
    if (sourceAfsPageCount != 15) {
      throw StateError(
        'AFS source integrity failure: '
        'expected 15 pages, '
        'got $sourceAfsPageCount.',
      );
    }

    // ============================================================
    // CALCULATE EXACT AFS RANGE
    // ============================================================

    // IMPORTANT:
    //
    // Replace ONLY 15 pages.
    //
    // Previous logic could remove a larger range between Annex A
    // and NFCC. If that range contained 18 pages while the new AFS
    // contained 15 pages:
    //
    // 18 removed
    // 15 inserted
    // = document loses 3 pages
    //
    // Example:
    //
    // expected 86 pages
    // generated 83 pages
    //
    // This implementation cannot shrink the document because AFS
    // replacement is strictly 15 -> 15.

    final oldAfsPageCount =
        sourceAfsPageCount;

    final afsPageIndex =
        nfccPageIndex - oldAfsPageCount;

    final afsEndExclusive =
        afsPageIndex + oldAfsPageCount;

    if (afsPageIndex < 0 ||
        afsPageIndex >= document.pages.count) {
      throw StateError(
        'Cannot replace AFS: invalid AFS start. '
        'afsStart=$afsPageIndex '
        'afsPages=$oldAfsPageCount '
        'nfcc=$nfccPageIndex '
        'technical=$technicalSpecificationsPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    if (afsEndExclusive != nfccPageIndex) {
      throw StateError(
        'Cannot replace AFS: AFS does not terminate at NFCC. '
        'afsStart=$afsPageIndex '
        'afsEnd=$afsEndExclusive '
        'nfcc=$nfccPageIndex.',
      );
    }

    if (afsEndExclusive >
        document.pages.count) {
      throw StateError(
        'Cannot replace AFS: AFS range exceeds document bounds. '
        'afsStart=$afsPageIndex '
        'afsEnd=$afsEndExclusive '
        'documentPages=${document.pages.count}.',
      );
    }

    // Preserve total page count.
    final documentPageCountBefore =
        document.pages.count;

    // ============================================================
    // REMOVE EXACTLY 15 OLD AFS PAGES
    // ============================================================

    for (var page = 0;
        page < oldAfsPageCount;
        page++) {
      if (afsPageIndex >=
          document.pages.count) {
        throw StateError(
          'AFS removal unexpectedly exceeded document bounds. '
          'removed=$page '
          'expected=$oldAfsPageCount '
          'afsStart=$afsPageIndex '
          'documentPages=${document.pages.count}.',
        );
      }

      // Always remove at the same index.
      //
      // After one page is removed, the next old AFS page shifts
      // into this same index.
      document.pages.removeAt(
        afsPageIndex,
      );

      if (page % 3 == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    final expectedPagesAfterRemoval =
        documentPageCountBefore -
            oldAfsPageCount;

    if (document.pages.count !=
        expectedPagesAfterRemoval) {
      throw StateError(
        'AFS removal page-count mismatch. '
        'before=$documentPageCountBefore '
        'removed=$oldAfsPageCount '
        'expectedAfter=$expectedPagesAfterRemoval '
        'actualAfter=${document.pages.count}.',
      );
    }

    // ============================================================
    // INSERT ALL 15 AFS TEMPLATE PAGES
    // ============================================================

    const a4Size = Size(
      595.28,
      841.89,
    );

    for (var index = 0;
        index < sourceAfsPageCount;
        index++) {
      final sourcePage =
          sourceDocument.pages[index];

      final sourceSize =
          sourcePage.size;

      final widthScale =
          a4Size.width / sourceSize.width;

      final heightScale =
          a4Size.height / sourceSize.height;

      final scale =
          widthScale < heightScale
              ? widthScale
              : heightScale;

      final fittedSize = Size(
        sourceSize.width * scale,
        sourceSize.height * scale,
      );

      final insertIndex =
          afsPageIndex + index;

      if (insertIndex < 0 ||
          insertIndex >
              document.pages.count) {
        throw StateError(
          'AFS insertion index is invalid. '
          'sourcePage=${index + 1} '
          'insertIndex=$insertIndex '
          'documentPages=${document.pages.count}.',
        );
      }

      final targetPage =
          document.pages.insert(
        insertIndex,
        a4Size,
        PdfMargins()..all = 0,
      );

      targetPage.graphics.drawPdfTemplate(
        sourcePage.createTemplate(),
        Offset(
          (a4Size.width -
                  fittedSize.width) /
              2,
          (a4Size.height -
                  fittedSize.height) /
              2,
        ),
        fittedSize,
      );

      if (index % 3 == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    // ============================================================
    // PAGE COUNT MUST NOT CHANGE
    // ============================================================

    if (document.pages.count !=
        documentPageCountBefore) {
      throw StateError(
        'AFS replacement changed total document page count. '
        'before=$documentPageCountBefore '
        'after=${document.pages.count} '
        'removed=$oldAfsPageCount '
        'inserted=$sourceAfsPageCount.',
      );
    }

    // ============================================================
    // CREATE STRUCTURAL PLACEMENT
    // ============================================================

    final placement =
        _AfsPlacement(
      startIndex: afsPageIndex,
      pageCount: sourceAfsPageCount,
    );

    if (!placement.isValidFor(
      document,
    )) {
      throw StateError(
        'AFS placement invalid after replacement. '
        'start=${placement.startIndex} '
        'pages=${placement.pageCount} '
        'end=${placement.endExclusive} '
        'documentPages=${document.pages.count}.',
      );
    }

    // ============================================================
    // FIRST + SECOND AFS PAGE PROTECTION
    // ============================================================

    final firstAfsPageIndex =
        placement.startIndex;

    final secondAfsPageIndex =
        placement.startIndex + 1;

    if (firstAfsPageIndex < 0 ||
        firstAfsPageIndex >=
            document.pages.count) {
      throw StateError(
        'AFS integrity failure: '
        'first AFS page is missing. '
        'start=${placement.startIndex} '
        'end=${placement.endExclusive} '
        'documentPages=${document.pages.count}.',
      );
    }

    if (secondAfsPageIndex < 0 ||
        secondAfsPageIndex >=
            document.pages.count) {
      throw StateError(
        'AFS integrity failure: '
        'second AFS page is missing. '
        'start=${placement.startIndex} '
        'second=$secondAfsPageIndex '
        'end=${placement.endExclusive} '
        'documentPages=${document.pages.count}.',
      );
    }

    // ============================================================
    // CONFIRM NFCC IS STILL AFTER AFS
    // ============================================================

    // 15 pages were removed and 15 pages inserted at exactly the
    // same start location.
    //
    // Therefore NFCC must remain immediately after the AFS block.

    final expectedNfccPageIndex =
        placement.endExclusive;

    if (expectedNfccPageIndex >=
        document.pages.count) {
      throw StateError(
        'AFS/NFCC integrity failure: '
        'expected NFCC index is outside document. '
        'afsStart=${placement.startIndex} '
        'afsEnd=${placement.endExclusive} '
        'expectedNfcc=$expectedNfccPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    return placement;
  } finally {
    sourceDocument.dispose();
  }
}

Future<void> _replaceNfccPage(
  PdfDocument document,
  Map<String, String> values,
) async {
  if (document.pages.count == 0) {
    return;
  }

  // ============================================================
  // LOCATE NFCC
  // ============================================================
  //
  // NFCC may be scanned/flattened, so its own text is not always
  // reliable.
  //
  // The structural relationship used here is:
  //
  // [NFCC]
  // [TECHNICAL SPECIFICATIONS]
  //
  // Therefore Technical Specifications is the reliable anchor and
  // NFCC is the page immediately before it.
  // ============================================================

  int? nfccPageIndex;

  final documentLines =
      PdfTextExtractor(document)
          .extractTextLines();

  int? technicalSpecificationsPageIndex;

  for (final line in documentLines) {
    final text = line.text
        .replaceAll(
          '\u0000',
          '',
        )
        .toUpperCase()
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        )
        .trim();

    final isChecklistText =
        text.contains(
          'CHECKLIST OF ELIGIBILITY REQUIREMENTS',
        ) ||
        text.contains(
          'TABLE OF CONTENTS',
        );

    if (!isChecklistText &&
        technicalSpecificationsPageIndex ==
            null &&
        text.contains(
          'TECHNICAL SPECIFICATIONS',
        )) {
      technicalSpecificationsPageIndex =
          line.pageIndex;
    }

    if (!isChecklistText &&
        nfccPageIndex == null &&
        text.contains(
          'NET FINANCIAL CONTRACTING CAPACITY',
        ) &&
        text.contains(
          'NFCC',
        ) &&
        text.length < 100) {
      nfccPageIndex =
          line.pageIndex;
    }
  }

  if (technicalSpecificationsPageIndex !=
          null &&
      technicalSpecificationsPageIndex >
          0) {
    nfccPageIndex =
        technicalSpecificationsPageIndex -
            1;
  }

  if (nfccPageIndex == null) {
    throw StateError(
      'Cannot replace NFCC: '
      'Technical Specifications/NFCC anchor was not found.',
    );
  }

  if (nfccPageIndex < 0 ||
      nfccPageIndex >=
          document.pages.count) {
    throw StateError(
      'Cannot replace NFCC: invalid NFCC index. '
      'nfcc=$nfccPageIndex '
      'technical=$technicalSpecificationsPageIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  // ============================================================
  // LOAD NFCC TEMPLATE
  // ============================================================

  final data = await rootBundle.load(
    'assets/pdf/NFCC_Template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  if (sourceDocument.pages.count == 0) {
    sourceDocument.dispose();

    throw StateError(
      'NFCC_Template.pdf contains no pages.',
    );
  }

  final sourcePage =
      sourceDocument.pages[0];

  final graphics =
      sourcePage.graphics;

  final white = PdfSolidBrush(
    PdfColor(
      255,
      255,
      255,
    ),
  );

  final black = PdfSolidBrush(
    PdfColor(
      0,
      0,
      0,
    ),
  );

  final regular =
      PdfStandardFont(
    PdfFontFamily.helvetica,
    12,
  );

  final bold =
      PdfStandardFont(
    PdfFontFamily.helvetica,
    12,
    style: PdfFontStyle.bold,
  );

  final italic =
      PdfStandardFont(
    PdfFontFamily.helvetica,
    12,
    style: PdfFontStyle.italic,
  );

  final headerLabelFont =
      PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
  );

  final headerValueFont =
      PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
    style: PdfFontStyle.bold,
  );

  final red =
      PdfSolidBrush(
    PdfColor(
      210,
      0,
      0,
    ),
  );

  final procuringEntity =
      (values['procuringEntity'] ?? '')
          .trim();

  final referenceNumber =
      (values['referenceNumber'] ?? '')
          .trim();

  final projectTitle =
      (values['projectTitle'] ?? '')
          .trim();

  final submittedBy =
      (values['submittedBy'] ?? '')
          .trim();

  final date =
      (values['date'] ?? '')
          .trim();

  const address =
      _permanentBusinessAddress;

  // ============================================================
  // CLEAR OLD HEADER
  // ============================================================

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
    (values['bidderName'] ?? '')
        .trim()
        .toUpperCase(),
    123,
  );

  drawHeader(
    'ADDRESS',
    address,
    138,
    valueHeight: 27,
  );

  // ============================================================
  // CLEAR OLD SIGNATORY
  // ============================================================

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

  final submittedWidth =
      bold
          .measureString(
            submittedBy.toUpperCase(),
          )
          .width;

  graphics.drawLine(
    PdfPen(
      PdfColor(
        0,
        0,
        0,
      ),
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

  // ============================================================
  // SAVE + REOPEN NFCC BEFORE IMPORT
  // ============================================================

  final modifiedSourceBytes =
      await sourceDocument.save();

  sourceDocument.dispose();

  final flattenedSourceDocument =
      PdfDocument(
    inputBytes:
        modifiedSourceBytes,
  );

  try {
    if (flattenedSourceDocument
        .pages
        .count ==
        0) {
      throw StateError(
        'Cannot replace NFCC: '
        'flattened NFCC template contains no pages.',
      );
    }

    final flattenedSourcePage =
        flattenedSourceDocument
            .pages[0];

    // Replacing one page with one page must preserve total count.
    final pageCountBefore =
        document.pages.count;

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
        a4Size.width /
            sourceSize.width;

    final heightScale =
        a4Size.height /
            sourceSize.height;

    final scale =
        widthScale < heightScale
            ? widthScale
            : heightScale;

    final fittedSize = Size(
      sourceSize.width * scale,
      sourceSize.height * scale,
    );

    final targetPage =
        document.pages.insert(
      nfccPageIndex,
      a4Size,
      PdfMargins()..all = 0,
    );

    targetPage.graphics.drawPdfTemplate(
      flattenedSourcePage
          .createTemplate(),
      Offset(
        (a4Size.width -
                fittedSize.width) /
            2,
        (a4Size.height -
                fittedSize.height) /
            2,
      ),
      fittedSize,
    );

    if (document.pages.count !=
        pageCountBefore) {
      throw StateError(
        'NFCC replacement unexpectedly changed total page count. '
        'before=$pageCountBefore '
        'after=${document.pages.count}.',
      );
    }
  } finally {
    flattenedSourceDocument.dispose();
  }
}

/// Standard PDF fonts do not contain Unicode checkmark glyphs.
///
/// Marker rendering is handled by the shared Unicode marker renderer
/// in pdf_text_service.dart. Do not convert ✓ to "v" here.