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
    data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ),
    size,
  );
}

/// Width reserved before specification text.
///
/// IMPORTANT:
/// ✓ uses the built-in PDF Zapf Dingbats font.
/// The other Unicode markers continue using Segoe UI Symbol.
double _pdfSpecificationMarkerWidth(
  PdfFont textFont,
  String? marker,
) {
  if (marker == null || marker.isEmpty) {
    return 0;
  }

  var actualMarker = marker;

  if (actualMarker == 'v' || actualMarker == '✔') {
    actualMarker = '✓';
  }

  // ------------------------------------------------------------
  // CHECKMARK
  // Character code 51 / "3" in Zapf Dingbats renders as ✓.
  // ------------------------------------------------------------
  if (actualMarker == '✓') {
    final checkFont = PdfStandardFont(
      PdfFontFamily.zapfDingbats,
      textFont.size + 1,
    );

    return checkFont.measureString('3').width + 4.0;
  }

  final markerFont = _pdfUnicodeMarkerFont(textFont.size);

  return markerFont.measureString(actualMarker).width + 4.0;
}

/// Converts older incorrectly encoded marker sequences back to the
/// intended Unicode symbols.
String _pdfNormalizeSpecificationMarkerEncoding(String value) {
  return value
      .replaceAll(
        String.fromCharCodes(
          const [0xE2, 0x153, 0x201C],
        ),
        '✓',
      )
      .replaceAll(
        String.fromCharCodes(
          const [0xE2, 0x20AC, 0xA2],
        ),
        '•',
      )
      .replaceAll(
        String.fromCharCodes(
          const [0xE2, 0x2014, 0x2039],
        ),
        '○',
      )
      .replaceAll(
        String.fromCharCodes(
          const [0xE2, 0x2013, 0xA0],
        ),
        '■',
      )
      .replaceAll(
        String.fromCharCodes(
          const [0xE2, 0x17E, 0xA2],
        ),
        '➢',
      );
}

/// Produces a display line without duplicating a marker.
String _pdfSpecificationDisplayLine({
  String marker = '',
  required String text,
}) {
  var normalizedMarker =
      _pdfNormalizeSpecificationMarkerEncoding(marker).trim();

  var normalizedText =
      _pdfNormalizeSpecificationMarkerEncoding(text).trim();

  // Previously saved fake check marker.
  if (normalizedText.startsWith('v ')) {
    normalizedText = '✓ ${normalizedText.substring(2)}';
  }

  if (normalizedText.startsWith('✔')) {
    normalizedText = '✓${normalizedText.substring(1)}';
  }

  if (normalizedMarker == 'v' || normalizedMarker == '✔') {
    normalizedMarker = '✓';
  }

  if (normalizedMarker.isEmpty ||
      normalizedText.startsWith(normalizedMarker)) {
    return normalizedText;
  }

  return '$normalizedMarker $normalizedText';
}

/// Parse the first actual Unicode character.
///
/// Supported markers:
/// •
/// ○
/// ■
/// ➢
/// ✓
///
/// No marker regex is used here so ✓ cannot accidentally be removed
/// by the standard-font sanitizer.
({String marker, String text}) _pdfParseSpecificationDisplayLine(
  String value,
) {
  var line = _pdfNormalizeSpecificationMarkerEncoding(value).trimLeft();

  // Legacy fake check.
  if (line.startsWith('v ')) {
    line = '✓ ${line.substring(2)}';
  }

  // Heavy check becomes normal check.
  if (line.startsWith('✔')) {
    line = '✓${line.substring(1)}';
  }

  if (line.isEmpty) {
    return (
      marker: '',
      text: '',
    );
  }

  final firstRune = line.runes.first;
  final firstCharacter = String.fromCharCode(firstRune);

  const supportedMarkers = <String>{
    '✓',
    '•',
    '○',
    '■',
    '➢',
  };

  if (supportedMarkers.contains(firstCharacter)) {
    final markerLength = firstCharacter.length;

    return (
      marker: firstCharacter,
      text: line.substring(markerLength).trimLeft(),
    );
  }

  return (
    marker: '',
    text: line,
  );
}

/// Draw one specification marker.
///
/// ✓ IS NOT drawn using PdfTrueTypeFont.
/// ✓ IS NOT drawn using graphics.drawLine().
///
/// Instead it uses the built-in PDF Zapf Dingbats checkmark.
///
/// In Zapf Dingbats:
///
/// "3" = ✓
///
/// This is much more reliable in generated PDF files and Chrome PDF viewer.
void _drawSpecificationMarkerGlyph({
  required PdfGraphics graphics,
  required String marker,
  required PdfBrush brush,
  required double x,
  required double y,
  required double lineHeight,
  required PdfFont textFont,
}) {
  if (marker.isEmpty) {
    return;
  }

  var actualMarker = marker;

  if (actualMarker == 'v' || actualMarker == '✔') {
    actualMarker = '✓';
  }

  // ============================================================
  // REAL CHECKMARK
  // ============================================================
  if (actualMarker == '✓') {
    final checkFont = PdfStandardFont(
      PdfFontFamily.zapfDingbats,
      textFont.size + 1,
    );

    final markerWidth =
        checkFont.measureString('3').width + 4.0;

    graphics.drawString(
      '3',
      checkFont,
      brush: PdfSolidBrush(
        PdfColor(0, 0, 0),
      ),
      bounds: Rect.fromLTWH(
        x,
        y,
        markerWidth,
        lineHeight,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.middle,
        wordWrap: PdfWordWrapType.none,
      ),
    );

    return;
  }

  // ============================================================
  // OTHER MARKERS
  // • ○ ■ ➢
  // ============================================================
  final markerFont =
      _pdfUnicodeMarkerFont(textFont.size);

  final markerWidth =
      _pdfSpecificationMarkerWidth(
    textFont,
    actualMarker,
  );

  graphics.drawString(
    actualMarker,
    markerFont,
    brush: brush,
    bounds: Rect.fromLTWH(
      x,
      y,
      markerWidth,
      lineHeight,
    ),
    format: PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
      wordWrap: PdfWordWrapType.none,
    ),
  );
}

String _pdfSafeText(String value) {
  value =
      _pdfNormalizeSpecificationMarkerEncoding(value);

  return value
      .replaceAll(
        String.fromCharCode(8292),
        '',
      )
      .replaceAll(
        RegExp(
          '[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
        ),
        '',
      )
      .replaceAll(
        r'\u2064',
        '',
      )
      .replaceAll(
        '\u00A0',
        ' ',
      )
      .replaceAll(
        '✔',
        '✓',
      )
      .replaceAll(
        '\u26F3',
        '✓',
      )
      .replaceAll(
        '\u221A',
        '✓',
      );
}

/// Explicit Add line records.
List<String> _pdfSpecificationBlocks(
  dynamic value,
) {
  return (value ?? '')
      .toString()
      .replaceAll(
        'minified:Gc.specificationLineSeparator',
        '',
      )
      .replaceAll(
        'minified:Gc.specificationLineSeparator?',
        '',
      )
      .split('\u2029');
}

String _pdfSpecificationText(
  dynamic value,
) {
  return _pdfSpecificationBlocks(value)
      .join('\n\n');
}

dynamic _pdfSafeDecodedValue(
  dynamic value,
) {
  if (value is String) {
    return _pdfSafeText(value);
  }

  if (value is List) {
    return <dynamic>[
      for (final item in value)
        _pdfSafeDecodedValue(item),
    ];
  }

  if (value is Map) {
    return <dynamic, dynamic>{
      for (final entry in value.entries)
        entry.key:
            _pdfSafeDecodedValue(entry.value),
    };
  }

  return value;
}

/// PdfStandardFont does not support all Unicode.
///
/// IMPORTANT:
///
/// Markers MUST be removed from body text before body text reaches
/// this function.
///
/// ✓ / • / ○ / ■ / ➢ are rendered separately.
String _pdfStandardFontSafeText(
  String value,
) {
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

String _numericPart(
  dynamic value,
) {
  final text = (value ?? '')
      .toString()
      .replaceAll(',', '')
      .trim();

  final match = RegExp(
    r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)',
  ).firstMatch(text);

  return match?.group(0) ?? '';
}

double _displayedPdfTotal(
  ItemPricing pricing,
  Map price,
) {
  return price['isManualTotalOverride'] == true
      ? parseCurrency(
          price['manualTotal'],
        )
      : pricing.calculatedTotal;
}

/// Draws specification text with per-line markers.
///
/// Example:
///
/// ✓ MODEL: ABC
///
/// becomes internally:
///
/// marker = ✓
/// content = MODEL: ABC
///
/// The checkmark is then drawn separately using Zapf Dingbats.
/// The specification text continues using the supplied normal PDF font.
void _drawMarkedSpecificationText(
  PdfGraphics graphics,
  String text,
  PdfFont font,
  PdfBrush brush,
  Rect bounds, {
  bool centerVertically = true,
}) {
  text = _pdfSafeText(text);

  final entries =
      <({
        String? marker,
        String content,
        double height,
      })>[];

  for (final rawSourceLine
      in text.split(RegExp(r'\r?\n'))) {
    final parsed =
        _pdfParseSpecificationDisplayLine(
      rawSourceLine,
    );

    var marker = parsed.marker;

    if (marker == 'v' || marker == '✔') {
      marker = '✓';
    }

    final content =
        _pdfStandardFontSafeText(
      parsed.text,
    );

    final markerWidth =
        _pdfSpecificationMarkerWidth(
      font,
      marker,
    );

    final rawContentWidth =
        bounds.width - markerWidth;

    final contentWidth =
        rawContentWidth < 1
            ? 1.0
            : rawContentWidth;

    final measured =
        font.measureString(
      content.isEmpty ? ' ' : content,
      layoutArea: Size(
        contentWidth,
        bounds.height,
      ),
      format: PdfStringFormat(
        wordWrap:
            PdfWordWrapType.word,
      ),
    );

    final minimumHeight =
        font.size + 2;

    final measuredHeight =
        measured.height > minimumHeight
            ? measured.height
            : minimumHeight;

    entries.add(
      (
        marker:
            marker.isEmpty
                ? null
                : marker,
        content: content,
        height: measuredHeight
            .clamp(
              minimumHeight,
              bounds.height,
            )
            .toDouble(),
      ),
    );
  }

  final totalHeight =
      entries.fold<double>(
    0,
    (sum, row) =>
        sum + row.height,
  );

  var top = bounds.top;

  if (centerVertically) {
    top +=
        ((bounds.height - totalHeight) / 2)
            .clamp(
              0,
              bounds.height,
            )
            .toDouble();
  }

  for (final entry in entries) {
    final marker = entry.marker;

    var textLeft = bounds.left;

    if (marker != null) {
      final markerWidth =
          _pdfSpecificationMarkerWidth(
        font,
        marker,
      );

      _drawSpecificationMarkerGlyph(
        graphics: graphics,
        marker: marker,
        brush: brush,
        x: bounds.left,
        y: top,
        lineHeight: entry.height,
        textFont: font,
      );

      textLeft += markerWidth;
    }

    final remainingWidth =
        bounds.right - textLeft;

    graphics.drawString(
      entry.content,
      font,
      brush: brush,
      bounds: Rect.fromLTWH(
        textLeft,
        top,
        remainingWidth > 1
            ? remainingWidth
            : 1,
        entry.height,
      ),
      format: PdfStringFormat(
        alignment:
            PdfTextAlignment.left,
        lineAlignment:
            PdfVerticalAlignment.top,
        wordWrap:
            PdfWordWrapType.word,
      ),
    );

    top += entry.height;
  }
}

/// Measures specification text using exactly the same marker width
/// that is used when the PDF is drawn.
double _measureMarkedSpecificationTextHeight(
  String text,
  PdfFont font,
  double width,
) {
  text = _pdfSafeText(text);

  var totalHeight = 0.0;

  for (final rawLine
      in text
          .replaceAll(
            '\u2029',
            '\n',
          )
          .split('\n')) {
    final parsed =
        _pdfParseSpecificationDisplayLine(
      rawLine,
    );

    var marker = parsed.marker;

    if (marker == 'v' || marker == '✔') {
      marker = '✓';
    }

    final content =
        _pdfStandardFontSafeText(
      parsed.text.trim(),
    );

    final rawContentWidth =
        width -
            _pdfSpecificationMarkerWidth(
              font,
              marker,
            );

    final contentWidth =
        rawContentWidth < 1
            ? 1.0
            : rawContentWidth;

    final measured =
        font.measureString(
      content.isEmpty ? ' ' : content,
      layoutArea: Size(
        contentWidth,
        10000,
      ),
      format: PdfStringFormat(
        wordWrap:
            PdfWordWrapType.word,
      ),
    );

    final minimumLineHeight =
        font.size + 2;

    totalHeight +=
        measured.height >
                minimumLineHeight
            ? measured.height
            : minimumLineHeight;
  }

  return totalHeight;
}

/// Wraps specification lines while preserving a marker on the
/// FIRST visual line only.
///
/// Example:
///
/// ✓ VOLTAGE/CAPACITY: 3.2V/70 (+5) Ah LIFEPO4 BATTERY
///
/// may become:
///
/// ✓ VOLTAGE/CAPACITY: 3.2V/70 (+5) Ah
///   LIFEPO4 BATTERY
///
/// The second visual line intentionally does not receive another check.
List<List<String>> _chunkMarkedSpecificationLines(
  List<String> sourceLines,
  PdfFont font,
  double width,
  double maximumHeight,
) {
  sourceLines = <String>[
    for (final line in sourceLines)
      _pdfSafeText(line),
  ];

  final visualLines = <String>[];

  for (final rawSourceLine
      in sourceLines) {
    final parsed =
        _pdfParseSpecificationDisplayLine(
      rawSourceLine,
    );

    var marker = parsed.marker;

    if (marker == 'v' || marker == '✔') {
      marker = '✓';
    }

    final content =
        _pdfStandardFontSafeText(
      parsed.text.trim(),
    );

    final markerWidth =
        _pdfSpecificationMarkerWidth(
      font,
      marker,
    );

    final contentWidth =
        (width - markerWidth)
            .clamp(
              1.0,
              double.infinity,
            )
            .toDouble();

    final wrapped = <String>[];

    var currentLine = '';

    for (final word
        in content.split(
      RegExp(r'\s+'),
    )) {
      if (word.isEmpty) {
        continue;
      }

      final candidate =
          _pdfStandardFontSafeText(
        currentLine.isEmpty
            ? word
            : '$currentLine $word',
      );

      if (currentLine.isNotEmpty &&
          font
                  .measureString(
                    candidate,
                  )
                  .width >
              contentWidth) {
        wrapped.add(
          currentLine,
        );

        currentLine = word;
      } else {
        currentLine = candidate;
      }
    }

    if (currentLine.isNotEmpty) {
      wrapped.add(
        currentLine,
      );
    }

    if (wrapped.isEmpty) {
      wrapped.add('');
    }

    // Put marker back ONLY on first visual line.
    // Later _drawMarkedSpecificationText() will parse it and draw the
    // marker separately.
    if (marker.isNotEmpty) {
      wrapped[0] =
          '$marker ${wrapped[0]}'
              .trimRight();
    }

    visualLines.addAll(
      wrapped,
    );
  }

  final chunks =
      <List<String>>[];

  var current =
      <String>[];

  for (final line in visualLines) {
    final candidate =
        <String>[
      ...current,
      line,
    ];

    final candidateHeight =
        _measureMarkedSpecificationTextHeight(
      candidate.join('\n'),
      font,
      width,
    );

    if (current.isNotEmpty &&
        candidateHeight >
            maximumHeight) {
      chunks.add(
        current,
      );

      current =
          <String>[line];
    } else {
      current = candidate;
    }
  }

  if (current.isNotEmpty) {
    chunks.add(
      current,
    );
  }

  return chunks;
}