part of '../pdf_service.dart';

ByteData? _pdfUnicodeMarkerFontData;

Future<void> _ensurePdfUnicodeMarkerFont() async {
  _pdfUnicodeMarkerFontData ??=
      await rootBundle.load('assets/fonts/seguisym.ttf');
}

PdfFont _pdfUnicodeMarkerFont(double size) {
  final data = _pdfUnicodeMarkerFontData;
  if (data == null) {
    throw StateError('Unicode marker font was not initialized.');
  }
  return PdfTrueTypeFont(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    size,
  );
}

double _pdfSpecificationMarkerWidth(PdfFont textFont, String? marker) {
  if (marker == null || marker.isEmpty) return 0;
  // Reserve the actual symbol width. A fixed 14-point cell can be narrower
  // than Segoe UI Symbol's checkmark, which makes Syncfusion wrap the glyph
  // out of the visible cell.
  return _pdfUnicodeMarkerFont(textFont.size).measureString(marker).width + 3;
}

final RegExp _pdfSpecificationMarkerPattern = RegExp(
  '^\\s*(\\u2713|\\u2022|\\u25CB|\\u25A0|\\u27A2)\\s*',
);

/// Converts marker sequences saved by older Windows-1252/UTF-8 editor builds
/// back to their original Unicode symbols before layout or PDF drawing.
String _pdfNormalizeSpecificationMarkerEncoding(String value) => value
    .replaceAll(String.fromCharCodes(const [0xE2, 0x153, 0x201C]), '\u2713')
    .replaceAll(String.fromCharCodes(const [0xE2, 0x20AC, 0xA2]), '\u2022')
    .replaceAll(String.fromCharCodes(const [0xE2, 0x2014, 0x2039]), '\u25CB')
    .replaceAll(String.fromCharCodes(const [0xE2, 0x2013, 0xA0]), '\u25A0')
    .replaceAll(String.fromCharCodes(const [0xE2, 0x17E, 0xA2]), '\u27A2');

/// Produces one display line while avoiding duplicate markers if a saved line
/// already includes the selected marker.
String _pdfSpecificationDisplayLine(
    {String marker = '', required String text}) {
  final normalizedMarker =
      _pdfNormalizeSpecificationMarkerEncoding(marker).trim();
  var normalizedText = _pdfNormalizeSpecificationMarkerEncoding(text).trim();
  // A prior PDF-only workaround stored its checkmark marker as a standalone
  // leading `v`. Migrate that marker token here, at the specification-line
  // boundary, without changing ordinary v characters in body text.
  normalizedText = normalizedText.replaceFirstMapped(
    RegExp(r'^v(?=\s)'),
    (_) => '\u2713',
  );
  final effectiveMarker = normalizedMarker == 'v' ? '\u2713' : normalizedMarker;
  if (effectiveMarker.isEmpty || normalizedText.startsWith(effectiveMarker)) {
    return normalizedText;
  }
  return '$effectiveMarker $normalizedText';
}

({String marker, String text}) _pdfParseSpecificationDisplayLine(
  String value,
) {
  assert(() {
    print('RAW SPEC LINE = "$value"');
    print(
      'RAW CODEPOINTS = ${value.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase()}').join(' ')}',
    );
    return true;
  }());
  final line = _pdfSpecificationDisplayLine(text: value);
  assert(() {
    print('NORMALIZED SPEC LINE = "$line"');
    return true;
  }());
  final match = _pdfSpecificationMarkerPattern.firstMatch(line);
  final parsed = (
    marker: match?.group(1) ?? '',
    text: match == null ? line : line.substring(match.end),
  );
  assert(() {
    print('PARSED MARKER = "${parsed.marker}"');
    print('PARSED TEXT = "${parsed.text}"');
    return true;
  }());
  return parsed;
}

void _drawSpecificationMarkerGlyph({
  required PdfGraphics graphics,
  required String marker,
  required PdfBrush brush,
  required double x,
  required double y,
  required double lineHeight,
  required PdfFont textFont,
}) {
  if (marker.isEmpty) return;
  assert(marker != 'v', 'BUG: legacy v marker reached PDF renderer.');
  final markerFont = _pdfUnicodeMarkerFont(textFont.size);
  final markerWidth = _pdfSpecificationMarkerWidth(textFont, marker);
  assert(() {
    print(
      'FINAL PDF MARKER = "$marker" U+${marker.runes.first.toRadixString(16).toUpperCase()} '
      'markerWidth=$markerWidth x=$x y=$y',
    );
    return true;
  }());
  graphics.drawString(
    marker,
    markerFont,
    brush: brush,
    bounds: Rect.fromLTWH(x, y, markerWidth, lineHeight),
    format: PdfStringFormat(
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.none,
    ),
  );
}

String _pdfSafeText(String value) {
  value = _pdfNormalizeSpecificationMarkerEncoding(value);
  return value
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
      .replaceAll('\u221A', '\u2713');
}

/// Returns explicit editor Add line records while preserving normal newlines.
List<String> _pdfSpecificationBlocks(dynamic value) => (value ?? '')
    .toString()
    .replaceAll('minified:Gc.specificationLineSeparator', '')
    .replaceAll('minified:Gc.specificationLineSeparator?', '')
    .split('\u2029');

/// Converts explicit Add line records into paragraphs for plain-text consumers.
String _pdfSpecificationText(dynamic value) =>
    _pdfSpecificationBlocks(value).join('\n\n');

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

double _displayedPdfTotal(ItemPricing pricing, Map price) =>
    price['isManualTotalOverride'] == true
        ? parseCurrency(price['manualTotal'])
        : pricing.calculatedTotal;

void _drawMarkedSpecificationText(
  PdfGraphics graphics,
  String text,
  PdfFont font,
  PdfBrush brush,
  Rect bounds, {
  bool centerVertically = true,
}) {
  text = _pdfSafeText(text);
  final entries = <({String? marker, String content, double height})>[];
  for (final rawSourceLine in text.split(RegExp(r'\r?\n'))) {
    final parsed = _pdfParseSpecificationDisplayLine(rawSourceLine);
    final marker = parsed.marker;
    final content = _pdfStandardFontSafeText(
      parsed.text,
    );
    final contentWidth =
        bounds.width - _pdfSpecificationMarkerWidth(font, marker);
    final measured = font.measureString(
      content.isEmpty ? ' ' : content,
      layoutArea: Size(contentWidth, bounds.height),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
    );
    entries.add((
      marker: marker.isEmpty ? null : marker,
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
  final markerBrush = PdfSolidBrush(PdfColor(0, 0, 0));

  for (final entry in entries) {
    final marker = entry.marker;
    var textLeft = bounds.left;
    if (marker != null) {
      final markerWidth = _pdfSpecificationMarkerWidth(font, marker);
      _drawSpecificationMarkerGlyph(
        graphics: graphics,
        marker: marker,
        brush: markerBrush,
        x: bounds.left,
        y: top,
        lineHeight: entry.height,
        textFont: font,
      );
      textLeft += markerWidth;
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
  var totalHeight = 0.0;

  for (final rawLine in text.replaceAll('\u2029', '\n').split('\n')) {
    final parsed = _pdfParseSpecificationDisplayLine(rawLine);
    final content = _pdfStandardFontSafeText(
      parsed.text.trim(),
    );
    final rawContentWidth =
        width - _pdfSpecificationMarkerWidth(font, parsed.marker);
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
  final visualLines = <String>[];
  for (final rawSourceLine in sourceLines) {
    final parsed = _pdfParseSpecificationDisplayLine(rawSourceLine);
    final marker = parsed.marker;
    final content = _pdfStandardFontSafeText(
      parsed.text.trim(),
    );
    final contentWidth = (width - _pdfSpecificationMarkerWidth(font, marker))
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
    if (marker.isNotEmpty) wrapped[0] = '$marker ${wrapped[0]}'.trimRight();
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
