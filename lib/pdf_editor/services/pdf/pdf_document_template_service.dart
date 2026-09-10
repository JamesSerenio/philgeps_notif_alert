part of '../pdf_service.dart';

Future<void> _insertInitaoDocumentPages(
  PdfDocument document,
  Map<String, String> values,
) async {
  final data = await rootBundle.load(
    'assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf',
  );
  final template = PdfDocument(inputBytes: data.buffer.asUint8List());
  try {
    if (template.pages.count != 6) {
      throw StateError('The INITAO document template must contain six pages.');
    }
    // Remove only the legacy contents page after all original index-based
    // mappings finish. The INITAO contents page replaces it.
    final extractor = PdfTextExtractor(document);
    final legacyContentsPages = <int>[];
    for (var page = 0; page < document.pages.count; page++) {
      final text = extractor
          .extractText(startPageIndex: page, endPageIndex: page)
          .replaceAll(RegExp(r'\s+'), ' ')
          .toUpperCase();
      if (text.contains('CHECKLIST OF ELIGIBILITY REQUIREMENTS FOR GOODS')) {
        legacyContentsPages.add(page);
      }
    }
    for (final page in legacyContentsPages.reversed) {
      document.pages.removeAt(page);
    }
    _drawInitaoContentsFields(template.pages[0], values);
    const sourceOrder = [4, 5, 1, 2, 3, 0];
    for (var index = 0; index < sourceOrder.length; index++) {
      final source = template.pages[sourceOrder[index]];
      final target =
          document.pages.insert(index, source.size, PdfMargins()..all = 0);
      target.graphics
          .drawPdfTemplate(source.createTemplate(), Offset.zero, source.size);
    }
  } finally {
    template.dispose();
  }
}

void _drawInitaoContentsFields(PdfPage page, Map<String, String> values) {
  final graphics = page.graphics;
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final bold =
      PdfStandardFont(PdfFontFamily.timesRoman, 12, style: PdfFontStyle.bold);
  // Only cover variable header areas. Labels, colons, Republic heading,
  // table rules, and the entire contents listing remain in the source PDF.
  graphics.drawRectangle(
      brush: white, bounds: const Rect.fromLTWH(150, 51, 295, 29));
  graphics.drawRectangle(
      brush: white, bounds: const Rect.fromLTWH(178, 107, 385, 58));
  final center = PdfStringFormat(alignment: PdfTextAlignment.center);
  graphics.drawString(
      'Province Of ' + (values['province'] ?? '').trim(), regular,
      brush: black,
      bounds: const Rect.fromLTWH(150, 52.6, 295, 14),
      format: center);
  graphics.drawString(
      'Municipality of ' + (values['municipality'] ?? '').trim(), regular,
      brush: black,
      bounds: const Rect.fromLTWH(150, 66.1, 295, 14),
      format: center);
  graphics.drawString((values['projectTitle'] ?? '').trim(), bold,
      brush: black,
      bounds: const Rect.fromLTWH(180.2, 108.9, 379, 27.7),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
  graphics.drawString((values['date'] ?? '').trim(), bold,
      brush: black, bounds: const Rect.fromLTWH(180.2, 136.6, 379, 14));
  graphics.drawString((values['bidderName'] ?? '').trim(), bold,
      brush: black, bounds: const Rect.fromLTWH(180.2, 150.9, 379, 14));
}
