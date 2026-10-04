part of '../pdf_service.dart';

Future<void> _replaceSlccSection(
  PdfDocument document,
  Map<String, String> values,
) async {
  final requestedTemplate =
      values['slccTemplateType']?.trim().toLowerCase() ?? 'none';

  // ============================================================
  // SLCC STRUCTURE
  // ============================================================
  //
  // Original bidocs_template.pdf contains 3 legacy SLCC pages.
  //
  // We remove those 3 original SLCC pages first.
  //
  // Then:
  //
  // CCTV
  //   -> insert SLCC_table_cctv.pdf
  //
  // STREETLIGHT
  //   -> insert SLCC_table_streetlight.pdf
  //
  // NONE
  //   -> insert nothing
  //
  // IMPORTANT:
  // SLCC_CCTV_template.pdf and SLCC_Streetlight_template.pdf
  // are NO LONGER USED.
  // ============================================================

  const slccPageIndex = 20;
  const legacySlccPageCount = 3;

  if (slccPageIndex >= document.pages.count) {
    throw StateError(
      'Cannot replace SLCC: '
      'SLCC start index $slccPageIndex is outside document. '
      'documentPages=${document.pages.count}.',
    );
  }

  // ============================================================
  // REMOVE ORIGINAL 3 SLCC PAGES
  // ============================================================

  for (var removed = 0;
      removed < legacySlccPageCount;
      removed++) {
    if (slccPageIndex >= document.pages.count) {
      throw StateError(
        'Cannot remove legacy SLCC pages. '
        'Expected=$legacySlccPageCount '
        'removed=$removed '
        'documentPages=${document.pages.count}.',
      );
    }

    document.pages.removeAt(slccPageIndex);

    await Future<void>.delayed(
      const Duration(milliseconds: 1),
    );
  }

  // ============================================================
  // NONE
  // ============================================================

  if (requestedTemplate == 'none') {
    // Nothing is inserted.
    //
    // The 3 legacy SLCC pages were already removed above.
    return;
  }

  // ============================================================
  // SELECT NEW SLCC PDF
  // ============================================================

  late final String assetPath;

  switch (requestedTemplate) {
    case 'cctv':
      assetPath =
          'assets/pdf/SLCC_table_cctv.pdf';
      break;

    case 'streetlight':
    case 'streetlights':
    case 'street_light':
    case 'street_lights':
      assetPath =
          'assets/pdf/SLCC_table_streetlight.pdf';
      break;

    default:
      throw StateError(
        'Unsupported SLCC template type: '
        '$requestedTemplate. '
        'Expected: none, cctv, or streetlight.',
      );
  }

  // ============================================================
  // LOAD SELECTED SLCC PDF
  // ============================================================

  final data =
      await rootBundle.load(assetPath);

  final sourceDocument =
      PdfDocument(
    inputBytes:
        data.buffer.asUint8List(),
  );

  try {
    if (sourceDocument.pages.count == 0) {
      throw StateError(
        'Selected SLCC PDF contains no pages: '
        '$assetPath.',
      );
    }

    // ============================================================
    // INSERT SELECTED SLCC
    // ============================================================

    const a4Size = Size(
      595.28,
      841.89,
    );

    for (var index = 0;
        index < sourceDocument.pages.count;
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

      final offset = Offset(
        (a4Size.width -
                fittedSize.width) /
            2,
        (a4Size.height -
                fittedSize.height) /
            2,
      );

      final insertIndex =
          slccPageIndex + index;

      final targetPage =
          document.pages.insert(
        insertIndex,
        a4Size,
        PdfMargins()..all = 0,
      );

      targetPage.graphics.drawPdfTemplate(
        sourcePage.createTemplate(),
        offset,
        fittedSize,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 1),
      );
    }
  } finally {
    sourceDocument.dispose();
  }
}

void _drawSlccPrivateRow(
  PdfPage page,
  Map<String, String> values,
) {
  final graphics = page.graphics;

  final whiteBrush =
      PdfSolidBrush(
    PdfColor(
      255,
      255,
      255,
    ),
  );

  final blackBrush =
      PdfSolidBrush(
    PdfColor(
      0,
      0,
      0,
    ),
  );

  String value(String key) =>
      (values[key] ?? '').trim();

  String labeled(
    String label,
    String key,
  ) {
    final text = value(key);

    return text.isEmpty
        ? '$label NONE'
        : '$label $text';
  }

  String labeledUpper(
    String label,
    String key,
  ) {
    final text = value(key);

    return text.isEmpty
        ? '$label NONE'
        : '$label ${text.toUpperCase()}';
  }

  final percent =
      value('slccPercent');

  const rowTop = 285.0;
  const rowBottom = 410.0;

  const columns = <double>[
    37,
    148,
    283,
    369,
    482,
    575,
    691,
    821,
  ];

  // ============================================================
  // CLEAR PRIVATE ROW CONTENT
  // ============================================================

  for (var index = 1;
      index < columns.length - 1;
      index++) {
    final left =
        columns[index];

    final right =
        columns[index + 1];

    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(
        left + 3,
        rowTop + 2,
        right - left - 6,
        rowBottom - rowTop - 4,
      ),
    );
  }

  // Restore separator.
  final tableBorderPen =
      PdfPen(
    PdfColor(
      0,
      0,
      0,
    ),
    width: 0.5,
  );

  graphics.drawLine(
    tableBorderPen,
    const Offset(
      479.5,
      235,
    ),
    const Offset(
      479.5,
      rowBottom,
    ),
  );

  final cells = <
      ({
        Rect bounds,
        String text,
        bool bold,
        bool centered
      })>[
    (
      bounds: const Rect.fromLTWH(
        153,
        290,
        125,
        115,
      ),
      text: [
        labeledUpper(
          'a.',
          'slccOwnerName',
        ),
        labeledUpper(
          'b.',
          'slccAddressTelephone',
        ),
        labeledUpper(
          'c.',
          'slccNumber',
        ),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
    (
      bounds: const Rect.fromLTWH(
        287,
        290,
        78,
        115,
      ),
      text: value(
        'slccNatureOfWork',
      ).toUpperCase(),
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(
        373,
        290,
        105,
        115,
      ),
      text: value(
        'slccDescription',
      ).toUpperCase(),
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(
        486,
        290,
        85,
        115,
      ),
      text: percent.isEmpty
          ? ''
          : percent.endsWith('%')
              ? percent
              : '$percent%',
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(
        579,
        290,
        108,
        115,
      ),
      text: [
        labeled(
          'a.',
          'slccAmountOfAward',
        ),
        labeled(
          'b.',
          'slccCompletionDuration',
        ),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
    (
      bounds: const Rect.fromLTWH(
        695,
        290,
        122,
        115,
      ),
      text: [
        labeled(
          'a.',
          'slccDateAwarded',
        ),
        labeled(
          'b.',
          'slccContractEffectivity',
        ),
        labeled(
          'c.',
          'slccDateCompleted',
        ),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
  ];

  for (final cell in cells) {
    if (cell.text.isEmpty) {
      continue;
    }

    final font =
        PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: cell.bold
          ? PdfFontStyle.bold
          : PdfFontStyle.regular,
    );

    graphics.drawString(
      cell.text,
      font,
      brush: blackBrush,
      bounds: cell.bounds,
      format: PdfStringFormat(
        alignment:
            cell.centered
                ? PdfTextAlignment.center
                : PdfTextAlignment.left,
        lineAlignment:
            PdfVerticalAlignment.middle,
        wordWrap:
            PdfWordWrapType.word,
      ),
    );
  }
}

void _removeSlccSection(
  PdfDocument document,
) {
  // ============================================================
  // IMPORTANT
  // ============================================================
  //
  // _replaceSlccSection() now handles NONE itself.
  //
  // Therefore this function is retained only for compatibility
  // with existing pdf_service.dart code.
  //
  // DO NOT remove another 3 pages here because doing so would
  // remove the pages immediately AFTER the SLCC section.
  //
  // Example:
  //
  // _replaceSlccSection(... none ...)
  // already removes original 3 SLCC pages.
  //
  // Calling this afterward must therefore do NOTHING.
  // ============================================================

  return;
}