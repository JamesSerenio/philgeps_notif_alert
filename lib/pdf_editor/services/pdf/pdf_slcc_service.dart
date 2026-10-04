part of '../pdf_service.dart';

Future<void> _replaceSlccSection(
  PdfDocument document,
  Map<String, String> values,
) async {
  final requestedTemplate =
      values['slccTemplateType']?.trim().toLowerCase() ?? 'cctv';
  // Keep the legacy placeholder pages until all fixed-index replacements
  // finish. They are removed near the end when SLCC is disabled.
  if (requestedTemplate == 'none') return;
  final templateType =
      requestedTemplate == 'streetlight' ? 'streetlight' : 'cctv';
  final assetPath = templateType == 'streetlight'
      ? 'assets/pdf/SLCC_Streetlight_template.pdf'
      : 'assets/pdf/SLCC_CCTV_template.pdf';

  // The source bid document keeps the replaceable SLCC sheets specifically
  // on PDF pages 21-23. Keep page 20 untouched.
  const slccPageIndex = 20;
  if (slccPageIndex >= document.pages.count) return;

  final data = await rootBundle.load(assetPath);
  final sourceDocument = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  // The legacy SLCC occupies PDF pages 21-23 (three consecutive pages).
  // Remove only those sheets and insert the selected replacement at the
  // exact same location.
  for (var page = 0; page < 3 && slccPageIndex < document.pages.count; page++) {
    document.pages.removeAt(slccPageIndex);
    await Future<void>.delayed(const Duration(milliseconds: 1));
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
    final offset = Offset(
      (a4Size.width - fittedSize.width) / 2,
      (a4Size.height - fittedSize.height) / 2,
    );
    final targetPage = document.pages.insert(
      slccPageIndex + index,
      a4Size,
      PdfMargins()..all = 0,
    );
    targetPage.graphics.drawPdfTemplate(
      sourcePage.createTemplate(),
      offset,
      fittedSize,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  sourceDocument.dispose();
}

void _drawSlccPrivateRow(
  PdfPage page,
  Map<String, String> values,
) {
  final graphics = page.graphics;
  final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
  final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));

  String value(String key) => (values[key] ?? '').trim();
  String labeled(String label, String key) {
    final text = value(key);
    return text.isEmpty ? '$label NONE' : '$label $text';
  }

  String labeledUpper(String label, String key) {
    final text = value(key);
    return text.isEmpty ? '$label NONE' : '$label ${text.toUpperCase()}';
  }

  final percent = value('slccPercent');
  const rowTop = 285.0;
  const rowBottom = 410.0;
  const columns = <double>[37, 148, 283, 369, 482, 575, 691, 821];

  // Preserve the original template grid. Clear only the inside of each
  // PRIVATE data cell, leaving enough inset to keep every original border.
  for (var index = 1; index < columns.length - 1; index++) {
    final left = columns[index];
    final right = columns[index + 1];
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

  // Only this separator needs to be restored after clearing the editable
  // cells. Keep the template's other rules untouched so no doubled grid is
  // introduced by tiny coordinate differences in the source PDF.
  final tableBorderPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
  graphics.drawLine(
    tableBorderPen,
    const Offset(479.5, 235),
    const Offset(479.5, rowBottom),
  );

  final cells = <({Rect bounds, String text, bool bold, bool centered})>[
    (
      bounds: const Rect.fromLTWH(153, 290, 125, 115),
      text: [
        labeledUpper('a.', 'slccOwnerName'),
        labeledUpper('b.', 'slccAddressTelephone'),
        labeledUpper('c.', 'slccNumber'),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
    (
      bounds: const Rect.fromLTWH(287, 290, 78, 115),
      text: value('slccNatureOfWork').toUpperCase(),
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(373, 290, 105, 115),
      text: value('slccDescription').toUpperCase(),
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(486, 290, 85, 115),
      text: percent.isEmpty
          ? ''
          : percent.endsWith('%')
              ? percent
              : '$percent%',
      bold: false,
      centered: true,
    ),
    (
      bounds: const Rect.fromLTWH(579, 290, 108, 115),
      text: [
        labeled('a.', 'slccAmountOfAward'),
        labeled('b.', 'slccCompletionDuration'),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
    (
      bounds: const Rect.fromLTWH(695, 290, 122, 115),
      text: [
        labeled('a.', 'slccDateAwarded'),
        labeled('b.', 'slccContractEffectivity'),
        labeled('c.', 'slccDateCompleted'),
      ].join('\n'),
      bold: false,
      centered: false,
    ),
  ];

  for (final cell in cells) {
    if (cell.text.isEmpty) continue;

    final font = PdfStandardFont(
      PdfFontFamily.timesRoman,
      12,
      style: cell.bold ? PdfFontStyle.bold : PdfFontStyle.regular,
    );
    graphics.drawString(
      cell.text,
      font,
      brush: blackBrush,
      bounds: cell.bounds,
      format: PdfStringFormat(
        alignment:
            cell.centered ? PdfTextAlignment.center : PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.middle,
        wordWrap: PdfWordWrapType.word,
      ),
    );
  }
}

void _removeSlccSection(PdfDocument document) {
  const slccPageIndex = 20;
  const slccPageCount = 3;

  for (var removed = 0;
      removed < slccPageCount && slccPageIndex < document.pages.count;
      removed++) {
    document.pages.removeAt(slccPageIndex);
  }
}
