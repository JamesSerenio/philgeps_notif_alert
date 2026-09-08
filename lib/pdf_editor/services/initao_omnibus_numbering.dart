import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Changes only INITAO LGU labels on the already populated OLD pages.
void drawInitaoOmnibusNumbering(PdfDocument document, int firstPage) {
  final labels = <({int page, int number, Rect bounds})>[];
  final extractor = PdfTextExtractor(document);
  for (var offset = 0; offset < 2; offset++) {
    for (final line in extractor.extractTextLines(
        startPageIndex: firstPage + offset, endPageIndex: firstPage + offset)) {
      for (final word in line.wordCollection) {
        final match = RegExp(r'^([1-9])\)$').firstMatch(word.text.trim());
        if (match == null) continue;
        labels.add((
          page: firstPage + offset,
          number: int.parse(match.group(1)!),
          bounds: word.bounds
        ));
      }
    }
  }
  // Validate before drawing, so an unexpected template cannot be misnumbered.
  if (labels.length != 9 ||
      labels.map((label) => label.number).toSet().length != 9) {
    throw StateError('Could not locate the nine original Omnibus labels.');
  }
  final font = PdfStandardFont(PdfFontFamily.timesRoman, 11);
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  for (final label in labels) {
    final graphics = document.pages[label.page].graphics;
    graphics.drawRectangle(brush: white, bounds: label.bounds.inflate(.5));
    // Longer labels extend into the indent, away from the paragraph text.
    graphics.drawString('${label.number + 2}.', font,
        brush: black,
        bounds:
            Rect.fromLTWH(label.bounds.right - 20, label.bounds.top, 20, 16),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
  }
  final labelRight =
      labels.firstWhere((label) => label.number == 1).bounds.right;
  // Match the unchanged OLD renderer's office and authority paragraph tops.
  for (final entry in const [(1, 195.0), (2, 237.0)]) {
    document.pages[firstPage].graphics.drawString('${entry.$1}.', font,
        brush: black,
        bounds: Rect.fromLTWH(labelRight - 20, entry.$2, 20, 16),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
  }
}
