part of '../pdf_service.dart';

String _pdfSafeText(String value) => value
    .replaceAll(String.fromCharCode(8292), '')
    // Remove invisible direction/isolation characters commonly carried by
    // text copied from web pages and office documents. PdfStandardFont
    // cannot encode these controls (for example U+2064 / decimal 8292),
    // even though they have no visible appearance in the resulting PDF.
    .replaceAll(
      RegExp(
        '[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
      ),
      '',
    )
    // Also handle a JSON payload that contains the escaped form before it
    // is decoded into the individual specification fields.
    .replaceAll(r'\u2064', '')
    .replaceAll('\u00A0', ' ')
    .replaceAll('\u2714', '\u2713')
    // Some previously saved specifications contain U+26F3 in place of the
    // check marker. Standard PDF fonts cannot measure or draw that glyph.
    .replaceAll('\u26F3', '\u2713')
    .replaceAll('\u221A', '\u2713')
    // This function also receives JSON-encoded form values. Use escaped
    // newline sequences so replacing a legacy separator cannot insert a
    // raw control character inside a JSON string literal.
    .replaceAll('\u2029', r'\n\n');

dynamic _pdfSafeDecodedValue(dynamic value) {
  if (value is String) return _pdfSafeText(value);
  if (value is List) {
    return <dynamic>[
      for (final item in value) _pdfSafeDecodedValue(item),
    ];
  }
  if (value is Map) {
    return <dynamic, dynamic>{
      for (final entry in value.entries)
        entry.key: _pdfSafeDecodedValue(entry.value),
    };
  }
  return value;
}

/// PdfStandardFont only supports a Windows-1252-sized character set. This
/// final guard is used immediately before measuring/drawing user content so
/// an invisible or unsupported Unicode rune can never reach Syncfusion.

String _pdfStandardFontSafeText(String value) {
  final result = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x2018:
      case 0x2019:
        result.write("'");
        continue;
      case 0x201C:
      case 0x201D:
        result.write('"');
        continue;
      case 0x2013:
      case 0x2014:
        result.write('-');
        continue;
      case 0x2022:
        result.write('*');
        continue;
      case 0x2713:
      case 0x2714:
        result.write('v');
        continue;
    }
    if (rune == 0x0A ||
        rune == 0x0D ||
        rune == 0x09 ||
        (rune >= 0x20 && rune <= 0x7E) ||
        (rune >= 0xA0 && rune <= 0xFF)) {
      result.writeCharCode(rune);
    }
  }
  return result.toString();
}

String _numericPart(dynamic value) {
  final text = (value ?? '').toString().replaceAll(',', '').trim();
  final match = RegExp(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)').firstMatch(text);
  return match?.group(0) ?? '';
}

double _pdfNumber(dynamic value) => double.tryParse(_numericPart(value)) ?? 0;

void _drawMarkedSpecificationText(
  PdfGraphics graphics,
  String text,
  PdfFont font,
  PdfBrush brush,
  Rect bounds, {
  bool centerVertically = true,
}) {
  text = _pdfSafeText(text);
  final markerPattern = RegExp(r'^\s*(✓|•|○|■|➢)\s*');
  final entries = <({String? marker, String content, double height})>[];
  for (final sourceLine in text.split(RegExp(r'\r?\n'))) {
    final match = markerPattern.firstMatch(sourceLine);
    final marker = match?.group(1);
    final content = _pdfStandardFontSafeText(
      match == null ? sourceLine : sourceLine.substring(match.end),
    );
    final contentWidth = bounds.width - (marker == null ? 0 : 14);
    final measured = font.measureString(
      content.isEmpty ? ' ' : content,
      layoutArea: Size(contentWidth, bounds.height),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
    );
    entries.add((
      marker: marker,
      content: content,
      height: measured.height.clamp(font.size + 2, bounds.height).toDouble(),
    ));
  }
  final totalHeight = entries.fold<double>(0, (sum, row) => sum + row.height);
  var top = bounds.top;
  if (centerVertically) {
    top +=
        ((bounds.height - totalHeight) / 2).clamp(0, bounds.height).toDouble();
  }
  final markerPen = PdfPen(PdfColor(0, 0, 0), width: 1.15);
  final markerBrush = PdfSolidBrush(PdfColor(0, 0, 0));

  for (final entry in entries) {
    final marker = entry.marker;
    var textLeft = bounds.left;
    if (marker != null) {
      final markerTop = top + (entry.height - 9) / 2;
      switch (marker) {
        case '✓':
          graphics.drawLine(
            markerPen,
            Offset(bounds.left + 1, markerTop + 5),
            Offset(bounds.left + 4, markerTop + 8),
          );
          graphics.drawLine(
            markerPen,
            Offset(bounds.left + 4, markerTop + 8),
            Offset(bounds.left + 10, markerTop + 1),
          );
          break;
        case '•':
          graphics.drawEllipse(
            Rect.fromLTWH(bounds.left + 3, markerTop + 3, 5, 5),
            brush: markerBrush,
          );
          break;
        case '○':
          graphics.drawEllipse(
            Rect.fromLTWH(bounds.left + 2, markerTop + 2, 7, 7),
            pen: markerPen,
          );
          break;
        case '■':
          graphics.drawRectangle(
            brush: markerBrush,
            bounds: Rect.fromLTWH(bounds.left + 2, markerTop + 2, 7, 7),
          );
          break;
        case '➢':
          graphics.drawLine(
            markerPen,
            Offset(bounds.left + 1, markerTop + 1),
            Offset(bounds.left + 10, markerTop + 5),
          );
          graphics.drawLine(
            markerPen,
            Offset(bounds.left + 10, markerTop + 5),
            Offset(bounds.left + 1, markerTop + 9),
          );
          break;
      }
      textLeft += 14;
    }
    graphics.drawString(
      entry.content,
      font,
      brush: brush,
      bounds: Rect.fromLTWH(
        textLeft,
        top,
        bounds.right - textLeft,
        entry.height,
      ),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
    );
    top += entry.height;
  }
}

double _measureMarkedSpecificationTextHeight(
  String text,
  PdfFont font,
  double width,
) {
  text = _pdfSafeText(text);
  final markerPattern = RegExp(
    r'^\s*(✓|✔|⛳|•|○|■|➢|-|\[x\])\s*',
    caseSensitive: false,
  );
  var totalHeight = 0.0;

  for (final rawLine in text.replaceAll('\u2029', '\n').split('\n')) {
    final match = markerPattern.firstMatch(rawLine);
    final content = _pdfStandardFontSafeText(
      match == null ? rawLine.trim() : rawLine.substring(match.end).trim(),
    );
    final rawContentWidth = width - (match == null ? 0 : 14);
    final contentWidth = rawContentWidth < 1.0 ? 1.0 : rawContentWidth;
    final measured = font.measureString(
      content.isEmpty ? ' ' : content,
      layoutArea: Size(contentWidth, 10000),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
    );
    final minimumLineHeight = font.size + 2;
    totalHeight += measured.height > minimumLineHeight
        ? measured.height
        : minimumLineHeight;
  }

  return totalHeight;
}

List<List<String>> _chunkMarkedSpecificationLines(
  List<String> sourceLines,
  PdfFont font,
  double width,
  double maximumHeight,
) {
  sourceLines = <String>[
    for (final line in sourceLines) _pdfSafeText(line),
  ];
  final markerPattern = RegExp(
    r'^\s*(✓|✔|⛳|•|○|■|➢|-|\[x\])\s*',
    caseSensitive: false,
  );
  final visualLines = <String>[];
  for (final sourceLine in sourceLines) {
    final match = markerPattern.firstMatch(sourceLine);
    final marker = match?.group(1);
    final content = _pdfStandardFontSafeText(
      match == null
          ? sourceLine.trim()
          : sourceLine.substring(match.end).trim(),
    );
    final contentWidth = (width - (marker == null ? 0 : 14))
        .clamp(1.0, double.infinity)
        .toDouble();
    final wrapped = <String>[];
    var currentLine = '';
    for (final word in content.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final candidate = _pdfStandardFontSafeText(
        currentLine.isEmpty ? word : '$currentLine $word',
      );
      if (currentLine.isNotEmpty &&
          font.measureString(candidate).width > contentWidth) {
        wrapped.add(currentLine);
        currentLine = word;
      } else {
        currentLine = candidate;
      }
    }
    if (currentLine.isNotEmpty) wrapped.add(currentLine);
    if (wrapped.isEmpty) wrapped.add('');
    if (marker != null) wrapped[0] = '$marker ${wrapped[0]}'.trimRight();
    visualLines.addAll(wrapped);
  }

  final chunks = <List<String>>[];
  var current = <String>[];

  for (final line in visualLines) {
    final candidate = <String>[...current, line];
    final candidateHeight = _measureMarkedSpecificationTextHeight(
      candidate.join('\n'),
      font,
      width,
    );
    if (current.isNotEmpty && candidateHeight > maximumHeight) {
      chunks.add(current);
      current = <String>[line];
    } else {
      current = candidate;
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}
