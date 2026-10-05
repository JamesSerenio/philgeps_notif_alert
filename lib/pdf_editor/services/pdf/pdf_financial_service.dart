part of '../pdf_service.dart';

String _financialNormalizedPageText(
  PdfDocument document,
  int pageIndex,
) {
  return PdfTextExtractor(document)
      .extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      )
      .replaceAll('\u0000', '')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toUpperCase();
}

String _financialCompactText(
  String text,
) {
  return text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

bool _financialIsContentsPage(
  String text,
) {
  final compact = _financialCompactText(text);

  return compact.contains(
        'CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS',
      ) ||
      compact.contains(
        'TABLEOFCONTENTS',
      );
}

/// ================================================================
/// FIND REAL TECHNICAL SPECIFICATIONS
/// ================================================================

int _findRealTechnicalSpecificationsPage(
  PdfDocument document,
) {
  for (var pageIndex = 0;
      pageIndex < document.pages.count;
      pageIndex++) {
    final text = _financialNormalizedPageText(
      document,
      pageIndex,
    );

    if (_financialIsContentsPage(text)) {
      continue;
    }

    final compact = _financialCompactText(text);

    final hasTitle = compact.contains(
      'TECHNICALSPECIFICATIONS',
    );

    final hasCompliance = compact.contains(
      'STATEMENTOFCOMPLIANCE',
    );

    final hasSpecificationHeader = compact.contains(
      'SPECIFICATION/S',
    );

    if (hasTitle &&
        (hasCompliance || hasSpecificationHeader)) {
      return pageIndex;
    }
  }

  return -1;
}

/// ================================================================
/// FIND REAL NFCC
/// ================================================================

int _findRealNfccPage(
  PdfDocument document,
) {
  for (var pageIndex = 0;
      pageIndex < document.pages.count;
      pageIndex++) {
    final text = _financialNormalizedPageText(
      document,
      pageIndex,
    );

    if (_financialIsContentsPage(text)) {
      continue;
    }

    final compact = _financialCompactText(text);

    if (compact.contains(
      'NETFINANCIALCONTRACTINGCAPACITY',
    )) {
      return pageIndex;
    }
  }

  final technicalIndex =
      _findRealTechnicalSpecificationsPage(
    document,
  );

  if (technicalIndex >= 2) {
    return technicalIndex - 2;
  }

  return -1;
}

/// ================================================================
/// REMOVE TWO EXTRA LEGACY FINANCIAL PAGES
/// ================================================================

Future<void> _removeTwoLegacyFinancialPagesBeforeAfs(
  PdfDocument document,
  int nfccPageIndex,
) async {
  const afsPageCount = 15;
  const unwantedPageCount = 2;

  final afsStartIndex =
      nfccPageIndex - afsPageCount;

  final unwantedStartIndex =
      afsStartIndex - unwantedPageCount;

  if (afsStartIndex <= 0) {
    throw StateError(
      'Cannot remove legacy financial pages: '
      'invalid AFS start. '
      'afsStart=$afsStartIndex '
      'nfcc=$nfccPageIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  if (unwantedStartIndex <= 0 ||
      unwantedStartIndex + 1 >=
          document.pages.count) {
    throw StateError(
      'Cannot remove legacy financial pages: '
      'invalid two-page range. '
      'start=$unwantedStartIndex '
      'afsStart=$afsStartIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  for (var pageIndex = unwantedStartIndex;
      pageIndex < afsStartIndex;
      pageIndex++) {
    final text = _financialNormalizedPageText(
      document,
      pageIndex,
    );

    final compact = _financialCompactText(text);

    if (_financialIsContentsPage(text)) {
      throw StateError(
        'Legacy financial cleanup blocked: '
        'target contains Checklist/Table of Contents. '
        'pageIndex=$pageIndex.',
      );
    }

    if (compact.contains(
      'STATEMENTOFALLITSONGOING',
    )) {
      throw StateError(
        'Legacy financial cleanup blocked: '
        'target contains Statement of Ongoing. '
        'pageIndex=$pageIndex.',
      );
    }

    if (compact.contains(
      'STATEMENTOFBIDDER',
    )) {
      throw StateError(
        'Legacy financial cleanup blocked: '
        'target contains SLCC. '
        'pageIndex=$pageIndex.',
      );
    }

    if (compact.contains(
      'NETFINANCIALCONTRACTINGCAPACITY',
    )) {
      throw StateError(
        'Legacy financial cleanup blocked: '
        'target contains NFCC. '
        'pageIndex=$pageIndex.',
      );
    }

    if (compact.contains(
      'TECHNICALSPECIFICATIONS',
    )) {
      throw StateError(
        'Legacy financial cleanup blocked: '
        'target contains Technical Specifications. '
        'pageIndex=$pageIndex.',
      );
    }
  }

  for (var removed = 0;
      removed < unwantedPageCount;
      removed++) {
    if (unwantedStartIndex <= 0 ||
        unwantedStartIndex >=
            document.pages.count) {
      throw StateError(
        'Legacy financial cleanup exceeded bounds. '
        'removed=$removed '
        'index=$unwantedStartIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    document.pages.removeAt(
      unwantedStartIndex,
    );

    await Future<void>.delayed(
      const Duration(milliseconds: 1),
    );
  }
}

/// ================================================================
/// REMOVE 3 LEGACY FINANCIAL PAGES BEFORE AFS
/// ================================================================

Future<_AfsPlacement> _removeLegacyAfsFrontMatterAfterPhilgeps(
  PdfDocument document,
  _AfsPlacement placement,
) async {
  if (document.pages.count == 0) {
    return placement;
  }

  if (!placement.isValidFor(document)) {
    throw StateError(
      'Cannot clean AFS front matter: invalid AFS placement. '
      'start=${placement.startIndex} '
      'pages=${placement.pageCount} '
      'documentPages=${document.pages.count}.',
    );
  }

  if (placement.pageCount != 15) {
    throw StateError(
      'Cannot clean AFS front matter: expected 15 AFS pages, '
      'got ${placement.pageCount}.',
    );
  }

  const legacyFrontMatterCount = 3;

  final frontMatterStartIndex =
      placement.startIndex - legacyFrontMatterCount;

  if (frontMatterStartIndex <= 0) {
    throw StateError(
      'Cannot remove 3 legacy AFS front-matter pages: '
      'unsafe start index. '
      'frontMatterStart=$frontMatterStartIndex '
      'afsStart=${placement.startIndex} '
      'documentPages=${document.pages.count}.',
    );
  }

  if (frontMatterStartIndex + legacyFrontMatterCount >
      placement.startIndex) {
    throw StateError(
      'Cannot remove legacy AFS front matter: '
      'calculated range overlaps AFS.',
    );
  }

  for (var pageIndex = frontMatterStartIndex;
      pageIndex < placement.startIndex;
      pageIndex++) {
    final text = _financialNormalizedPageText(
      document,
      pageIndex,
    );

    final compact = _financialCompactText(text);

    final protected =
        _financialIsContentsPage(text) ||
        compact.contains('STATEMENTOFALLITSONGOING') ||
        compact.contains('STATEMENTOFBIDDER') ||
        compact.contains('NETFINANCIALCONTRACTINGCAPACITY') ||
        compact.contains('TECHNICALSPECIFICATIONS');

    if (protected) {
      throw StateError(
        'Legacy AFS cleanup blocked: '
        'protected page detected at index=$pageIndex.',
      );
    }
  }

  final pageCountBefore = document.pages.count;

  for (var removed = 0;
      removed < legacyFrontMatterCount;
      removed++) {
    if (frontMatterStartIndex <= 0 ||
        frontMatterStartIndex >=
            document.pages.count) {
      throw StateError(
        'Legacy AFS cleanup exceeded document bounds. '
        'removed=$removed '
        'index=$frontMatterStartIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    document.pages.removeAt(
      frontMatterStartIndex,
    );

    await Future<void>.delayed(
      const Duration(milliseconds: 1),
    );
  }

  final updatedPlacement = _AfsPlacement(
    startIndex:
        placement.startIndex - legacyFrontMatterCount,
    pageCount: placement.pageCount,
  );

  if (!updatedPlacement.isValidFor(document)) {
    throw StateError(
      'AFS placement became invalid after '
      '3-page legacy cleanup. '
      'start=${updatedPlacement.startIndex} '
      'pages=${updatedPlacement.pageCount} '
      'end=${updatedPlacement.endExclusive} '
      'documentPages=${document.pages.count}.',
    );
  }

  if (updatedPlacement.pageCount != 15) {
    throw StateError(
      'AFS integrity failure after legacy cleanup: '
      'expected 15 pages, '
      'got ${updatedPlacement.pageCount}.',
    );
  }

  final expectedPageCount =
      pageCountBefore - legacyFrontMatterCount;

  if (document.pages.count != expectedPageCount) {
    throw StateError(
      'Legacy AFS cleanup page-count mismatch. '
      'before=$pageCountBefore '
      'removed=$legacyFrontMatterCount '
      'expected=$expectedPageCount '
      'actual=${document.pages.count}.',
    );
  }

  print(
    'PDF AFS FRONT-MATTER CLEANUP: '
    'removed=$legacyFrontMatterCount '
    'frontMatterStart=$frontMatterStartIndex '
    'afsStartBefore=${placement.startIndex} '
    'afsStartAfter=${updatedPlacement.startIndex} '
    'before=$pageCountBefore '
    'after=${document.pages.count}',
  );

  return updatedPlacement;
}

/// ================================================================
/// REPLACE AFS
/// ================================================================

Future<_AfsPlacement?> _replaceAfsSection(
  PdfDocument document,
) async {
  if (document.pages.count == 0) {
    throw StateError(
      'Cannot replace AFS: document contains no pages.',
    );
  }

  final originalNfccPageIndex =
      _findRealNfccPage(
    document,
  );

  if (originalNfccPageIndex <= 0 ||
      originalNfccPageIndex >=
          document.pages.count) {
    throw StateError(
      'Cannot replace AFS: real NFCC page not found. '
      'nfcc=$originalNfccPageIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  final nfccPageIndex =
      originalNfccPageIndex;

  final data = await rootBundle.load(
    'assets/pdf/AFS_template.pdf',
  );

  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  try {
    final sourceAfsPageCount =
        sourceDocument.pages.count;

    if (sourceAfsPageCount != 15) {
      throw StateError(
        'AFS source integrity failure: '
        'expected 15 pages, '
        'got $sourceAfsPageCount.',
      );
    }

    const oldAfsPageCount = 15;

    final afsPageIndex =
        nfccPageIndex - oldAfsPageCount;

    final afsEndExclusive =
        afsPageIndex + oldAfsPageCount;

    if (afsPageIndex <= 0 ||
        afsPageIndex >=
            document.pages.count) {
      throw StateError(
        'Cannot replace AFS: unsafe AFS start. '
        'afsStart=$afsPageIndex '
        'nfcc=$nfccPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    if (afsEndExclusive != nfccPageIndex) {
      throw StateError(
        'Cannot replace AFS: invalid AFS/NFCC boundary. '
        'afsStart=$afsPageIndex '
        'afsEnd=$afsEndExclusive '
        'nfcc=$nfccPageIndex.',
      );
    }

    for (var pageIndex = afsPageIndex;
        pageIndex < afsEndExclusive;
        pageIndex++) {
      final text = _financialNormalizedPageText(
        document,
        pageIndex,
      );

      final compact =
          _financialCompactText(text);

      if (_financialIsContentsPage(text)) {
        throw StateError(
          'AFS safety failure: '
          'Checklist/Table of Contents is inside '
          'the AFS replacement range. '
          'pageIndex=$pageIndex.',
        );
      }

      if (compact.contains(
        'STATEMENTOFALLITSONGOING',
      )) {
        throw StateError(
          'AFS safety failure: Statement of Ongoing '
          'is inside the AFS replacement range. '
          'pageIndex=$pageIndex.',
        );
      }

      if (compact.contains(
        'STATEMENTOFBIDDER',
      )) {
        throw StateError(
          'AFS safety failure: SLCC is inside '
          'the AFS replacement range. '
          'pageIndex=$pageIndex.',
        );
      }

      if (compact.contains(
        'NETFINANCIALCONTRACTINGCAPACITY',
      )) {
        throw StateError(
          'AFS safety failure: NFCC is inside '
          'the AFS replacement range. '
          'pageIndex=$pageIndex.',
        );
      }

      if (compact.contains(
        'TECHNICALSPECIFICATIONS',
      )) {
        throw StateError(
          'AFS safety failure: Technical Specifications '
          'is inside the AFS replacement range. '
          'pageIndex=$pageIndex.',
        );
      }
    }

    final pageCountBeforeAfsReplacement =
        document.pages.count;

    for (var removed = 0;
        removed < oldAfsPageCount;
        removed++) {
      if (afsPageIndex <= 0 ||
          afsPageIndex >=
              document.pages.count) {
        throw StateError(
          'AFS removal exceeded safe bounds. '
          'removed=$removed '
          'afsStart=$afsPageIndex '
          'documentPages=${document.pages.count}.',
        );
      }

      document.pages.removeAt(
        afsPageIndex,
      );

      if (removed % 3 == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    final expectedAfterAfsRemoval =
        pageCountBeforeAfsReplacement -
            oldAfsPageCount;

    if (document.pages.count !=
        expectedAfterAfsRemoval) {
      throw StateError(
        'AFS removal page-count mismatch. '
        'before=$pageCountBeforeAfsReplacement '
        'expectedAfter=$expectedAfterAfsRemoval '
        'actualAfter=${document.pages.count}.',
      );
    }

    const a4Size = Size(
      595.28,
      841.89,
    );

    for (var sourceIndex = 0;
        sourceIndex < sourceAfsPageCount;
        sourceIndex++) {
      final sourcePage =
          sourceDocument.pages[sourceIndex];

      final sourceSize = sourcePage.size;

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
          afsPageIndex + sourceIndex;

      if (insertIndex <= 0 ||
          insertIndex > document.pages.count) {
        throw StateError(
          'AFS insertion index invalid. '
          'sourcePage=${sourceIndex + 1} '
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

      if (sourceIndex % 3 == 2) {
        await Future<void>.delayed(
          const Duration(milliseconds: 1),
        );
      }
    }

    if (document.pages.count !=
        pageCountBeforeAfsReplacement) {
      throw StateError(
        'AFS replacement changed page count unexpectedly. '
        'before=$pageCountBeforeAfsReplacement '
        'after=${document.pages.count} '
        'removed=$oldAfsPageCount '
        'inserted=$sourceAfsPageCount.',
      );
    }

    final placement = _AfsPlacement(
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

    if (placement.pageCount != 15) {
      throw StateError(
        'AFS integrity failure: '
        'expected 15 pages, '
        'got ${placement.pageCount}.',
      );
    }

    final currentNfccPageIndex =
        placement.endExclusive;

    final receiptPageIndex =
        currentNfccPageIndex + 1;

    final technicalPageIndex =
        currentNfccPageIndex + 2;

    if (currentNfccPageIndex < 0 ||
        currentNfccPageIndex >=
            document.pages.count) {
      throw StateError(
        'Receipt cleanup failed: '
        'NFCC index is invalid. '
        'nfcc=$currentNfccPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    if (receiptPageIndex < 0 ||
        receiptPageIndex >=
            document.pages.count) {
      throw StateError(
        'Receipt cleanup failed: '
        'receipt index is invalid. '
        'receipt=$receiptPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    if (technicalPageIndex < 0 ||
        technicalPageIndex >=
            document.pages.count) {
      throw StateError(
        'Receipt cleanup failed: '
        'Technical Specifications index is invalid. '
        'technical=$technicalPageIndex '
        'documentPages=${document.pages.count}.',
      );
    }

    final technicalText =
        _financialNormalizedPageText(
      document,
      technicalPageIndex,
    );

    final technicalCompact =
        _financialCompactText(
      technicalText,
    );

    final realTechnicalPage =
        technicalCompact.contains(
          'TECHNICALSPECIFICATIONS',
        ) &&
        (technicalCompact.contains(
              'STATEMENTOFCOMPLIANCE',
            ) ||
            technicalCompact.contains(
              'SPECIFICATION/S',
            ));

    if (!realTechnicalPage) {
      throw StateError(
        'Receipt cleanup blocked: expected '
        'Technical Specifications after receipt '
        'was not found. '
        'nfcc=$currentNfccPageIndex '
        'receipt=$receiptPageIndex '
        'technical=$technicalPageIndex.',
      );
    }

    document.pages.removeAt(
      receiptPageIndex,
    );

    await Future<void>.delayed(
      const Duration(milliseconds: 1),
    );

    if (!placement.isValidFor(
      document,
    )) {
      throw StateError(
        'AFS placement became invalid after '
        'receipt removal. '
        'start=${placement.startIndex} '
        'pages=${placement.pageCount} '
        'end=${placement.endExclusive} '
        'documentPages=${document.pages.count}.',
      );
    }

    if (placement.pageCount != 15) {
      throw StateError(
        'AFS integrity failure after receipt removal: '
        'expected 15 pages, '
        'got ${placement.pageCount}.',
      );
    }

    return placement;
  } finally {
    sourceDocument.dispose();
  }
}

/// ================================================================
/// REPLACE NFCC
/// ================================================================

Future<void> _replaceNfccPage(
  PdfDocument document,
  Map<String, String> values,
) async {
  if (document.pages.count == 0) {
    return;
  }

  final nfccPageIndex =
      _findRealNfccPage(
    document,
  );

  if (nfccPageIndex <= 0 ||
      nfccPageIndex >=
          document.pages.count) {
    throw StateError(
      'Cannot replace NFCC: real NFCC page not found. '
      'nfcc=$nfccPageIndex '
      'documentPages=${document.pages.count}.',
    );
  }

  final targetText =
      _financialNormalizedPageText(
    document,
    nfccPageIndex,
  );

  if (_financialIsContentsPage(
    targetText,
  )) {
    throw StateError(
      'Cannot replace NFCC: target is '
      'Checklist/Table of Contents. '
      'nfcc=$nfccPageIndex.',
    );
  }

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

  final red = PdfSolidBrush(
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

  final modifiedSourceBytes =
      await sourceDocument.save();

  sourceDocument.dispose();

  final flattenedSourceDocument =
      PdfDocument(
    inputBytes: modifiedSourceBytes,
  );

  try {
    if (flattenedSourceDocument
            .pages.count ==
        0) {
      throw StateError(
        'Cannot replace NFCC: '
        'flattened NFCC template contains no pages.',
      );
    }

    final flattenedSourcePage =
        flattenedSourceDocument.pages[0];

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

    final targetPage =
        document.pages.insert(
      nfccPageIndex,
      a4Size,
      PdfMargins()..all = 0,
    );

    targetPage.graphics.drawPdfTemplate(
      flattenedSourcePage.createTemplate(),
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
        'NFCC replacement unexpectedly changed '
        'total page count. '
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