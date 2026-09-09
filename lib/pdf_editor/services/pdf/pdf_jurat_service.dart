part of '../pdf_service.dart';

void _drawJuratPlaceholders(
  PdfDocument document,
  Map<String, String> values,
) {
  final date = (values['date'] ?? '').trim();
  final yearMatch = RegExp(r'\b(\d{4})\b').firstMatch(date);
  final year = yearMatch?.group(1) ?? '2026';
  final lines = PdfTextExtractor(document).extractTextLines();
  TextLine? subscribedLine;
  TextLine? witnessLine;
  TextLine? ptrLine;
  TextLine? ibpLine;
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('SUBSCRIBED AND SWORN')) subscribedLine ??= line;
    if (text.contains('WITNESS MY HAND AND SEAL')) witnessLine ??= line;
    if (text.startsWith('PTR NO.')) ptrLine ??= line;
    if (text.startsWith('IBP NO.')) ibpLine ??= line;
  }
  if (subscribedLine == null) return;

  final page = document.pages[subscribedLine.pageIndex];
  final graphics = page.graphics;
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 11.5);
  final boldItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11.5,
    style: PdfFontStyle.italic,
  );
  final left = subscribedLine.bounds.left;
  final right = page.getClientSize().width - left;
  final subscribedTop = subscribedLine.bounds.top - 2;

  graphics.drawRectangle(
    brush: white,
    bounds: Rect.fromLTWH(left - 3, subscribedTop - 2, right - left + 6, 82),
  );
  void drawRuns(
    double top,
    double width,
    List<(String, PdfFont, bool)> runs, {
    double lineHeight = 13.5,
  }) {
    var x = left;
    var y = top;
    var needsSpace = false;
    for (final run in runs) {
      for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final spaceWidth = needsSpace ? 3.0 : 0.0;
        final wordWidth = run.$2.measureString(word).width;
        if (x > left && x + spaceWidth + wordWidth > left + width) {
          x = left;
          y += lineHeight;
        } else if (x > left) {
          x += spaceWidth;
        }
        graphics.drawString(
          word,
          run.$2,
          brush: black,
          bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
        );
        if (run.$3) {
          graphics.drawString(
            word,
            run.$2,
            brush: black,
            bounds: Rect.fromLTWH(x + .3, y, wordWidth + 2, lineHeight),
          );
        }
        x += wordWidth;
        needsSpace = true;
      }
    }
  }

  drawRuns(subscribedTop, right - left, <(String, PdfFont, bool)>[
    (
      'SUBSCRIBED AND SWORN to before me this ______ day of ________',
      regular,
      false
    ),
    (year, boldItalic, true),
    ('at', regular, false),
    ('Municipality of __________, __________, Philippines.', boldItalic, true),
    (
      'Affiant/s is/are personally known to me and was/were '
          'identified by me through competent evidence of identity as defined '
          'in the 2004 Rules on Notarial Practice (A.M. No. 02-8-13-SC). '
          'Affiant/s exhibited to me his/her',
      regular,
      false
    ),
    ('National ID,', boldItalic, true),
    (
      'with his/her photograph and signature appearing thereon, with no. '
          '____________________',
      regular,
      false
    ),
  ]);

  final witnessTop = (witnessLine?.bounds.top ?? subscribedTop + 86) - 2;
  graphics.drawRectangle(
    brush: white,
    bounds: Rect.fromLTWH(left - 3, witnessTop - 2, right - left + 6, 22),
  );
  drawRuns(witnessTop, right - left, <(String, PdfFont, bool)>[
    ('WITNESS MY HAND AND SEAL this ____ day of ________', regular, false),
    ('$year.', boldItalic, true),
  ]);

  void replaceNotaryDate(TextLine? line, String label) {
    if (line == null) return;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        line.bounds.left - 2,
        line.bounds.top - 1,
        line.bounds.width + 30,
        line.bounds.height + 3,
      ),
    );
    final labelWidth = regular.measureString('$label ____, ________').width;
    graphics.drawString(
      '$label ____, ________',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(
        line.bounds.left,
        line.bounds.top,
        line.bounds.width + 30,
        16,
      ),
    );
    final yearLeft = line.bounds.left + labelWidth + 3;
    graphics.drawString(
      year,
      boldItalic,
      brush: black,
      bounds: Rect.fromLTWH(yearLeft, line.bounds.top, 45, 16),
    );
    graphics.drawString(
      year,
      boldItalic,
      brush: black,
      bounds: Rect.fromLTWH(yearLeft + .3, line.bounds.top, 45, 16),
    );
  }

  replaceNotaryDate(ptrLine, 'PTR No.');
  replaceNotaryDate(ibpLine, 'IBP No.');
}
