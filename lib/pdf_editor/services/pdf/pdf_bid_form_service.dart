part of '../pdf_service.dart';

void _drawBidForm(
  PdfDocument document,
  Map<String, String> values,
) {
  final lines = PdfTextExtractor(document).extractTextLines();
  int? bidFormPageIndex;
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == 'BID FORM') {
      bidFormPageIndex = line.pageIndex;
      break;
    }
  }
  if (bidFormPageIndex == null) return;
  TextLine? idLine;
  TextLine? toLine;
  TextLine? itemA;
  TextLine? itemB;
  TextLine? itemC;
  TextLine? itemD;
  TextLine? authorizedLine;
  TextLine? acknowledgeLine;
  for (final line in lines) {
    if (line.pageIndex != bidFormPageIndex) continue;
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('PROJECT IDENTIFICATION NO.')) idLine ??= line;
    if (text.startsWith('TO:')) toLine ??= line;
    if (text.contains('I/WE HAVE NO RESERVATION')) itemA ??= line;
    if (text.contains('I/WE OFFER TO EXECUTE')) itemB ??= line;
    if (text.contains('THE TOTAL PRICE OF OUR BID IN WORDS')) itemC ??= line;
    if (text.contains('THE DISCOUNTS OFFERED')) itemD ??= line;
    if (text.contains('THE UNDERSIGNED IS AUTHORIZED')) {
      authorizedLine ??= line;
    }
    if (text.contains('I/WE ACKNOWLEDGE THAT FAILURE')) {
      acknowledgeLine ??= line;
    }
  }
  if (idLine == null) return;

  List<dynamic> specifications = const [];
  List<dynamic> prices = const [];
  final encodedSpecifications = values['technicalSpecifications'] ?? '';
  final encodedPrices = values['priceSchedule'] ?? '';
  if (encodedSpecifications.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encodedSpecifications));
    if (decoded is List) specifications = decoded;
  }
  if (encodedPrices.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encodedPrices));
    if (decoded is List) prices = decoded;
  }
  double number(dynamic value) => _pdfNumber(value);
  var total = 0.0;
  for (var index = 0; index < specifications.length; index++) {
    final specification =
        specifications[index] is Map ? specifications[index] as Map : const {};
    final price = index < prices.length && prices[index] is Map
        ? prices[index] as Map
        : const {};
    final adjustedUnitPrice =
        (number(price['totalPricePerUnit']) - number(price['deduction']))
            .clamp(0, double.infinity)
            .toDouble();
    total +=
        (number(specification['quantity']) * adjustedUnitPrice).roundToDouble();
  }

  final page = document.pages[idLine.pageIndex];
  final graphics = page.graphics;
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 10.5);
  final italic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10.5,
    style: PdfFontStyle.italic,
  );
  final boldItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    10.5,
    style: PdfFontStyle.italic,
  );
  final headingRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final headingItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.italic,
  );
  final itemCRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final itemCBoldItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.italic,
  );
  final authorizedRegular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final authorizedItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.italic,
  );
  final reference = (values['referenceNumber'] ?? '').trim();
  final municipality = (values['municipality'] ?? '').trim();
  final province = (values['province'] ?? '').trim();
  final projectTitle = (values['projectTitle'] ?? '').trim();
  final selected =
      (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();
  final bidderName = (values['bidderName'] ?? '').trim();
  final bidDate = (values['date'] ?? '').trim();
  final location = 'Municipality of $municipality, $province';
  final money = _formatBidAmount(total);
  final amountWords = _bidAmountInWords(total);

  void replaceStyledLine(
    TextLine? line,
    List<(String, PdfFont)> parts, {
    double extraWidth = 20,
  }) {
    if (line == null) return;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(line.bounds.left - 3, line.bounds.top - 2,
          line.bounds.width + extraWidth + 6, line.bounds.height + 5),
    );
    var x = line.bounds.left;
    for (final part in parts) {
      final width = part.$2.measureString(part.$1).width;
      graphics.drawString(
        part.$1,
        part.$2,
        brush: black,
        bounds: Rect.fromLTWH(
            x, line.bounds.top, width + 2, line.bounds.height + 4),
      );
      if (identical(part.$2, boldItalic) || identical(part.$2, headingItalic)) {
        graphics.drawString(
          part.$1,
          part.$2,
          brush: black,
          bounds: Rect.fromLTWH(
              x + .2, line.bounds.top, width + 2, line.bounds.height + 4),
        );
      }
      x += width;
    }
  }

  replaceStyledLine(
      idLine,
      <(String, PdfFont)>[
        ('Project Identification No.: ', headingRegular),
        (reference, headingItalic),
      ],
      extraWidth: 80);
  replaceStyledLine(
      toLine,
      <(String, PdfFont)>[
        ('To: ', headingItalic),
        (location, headingItalic),
      ],
      extraWidth: 120);

  void replaceParagraph(
    TextLine? start,
    TextLine? next,
    String text, {
    PdfFont? font,
  }) {
    if (start == null) return;
    final left = start.bounds.left;
    final right = page.getClientSize().width - 70;
    final top = start.bounds.top - 2;
    final height = next == null
        ? 54.0
        : (next.bounds.top - top - 2).clamp(36, 78).toDouble();
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(left - 3, top - 2, right - left + 6, height + 4),
    );
    graphics.drawString(text, font ?? regular,
        brush: black,
        bounds: Rect.fromLTWH(left, top, right - left, height),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
  }

  void drawStyledParagraph(
    TextLine? start,
    TextLine? next,
    List<(String, PdfFont, bool)> parts, {
    double hangingIndent = 0,
    double labelColumnWidth = 0,
    double lineHeight = 12.5,
  }) {
    if (start == null) return;
    final left = start.bounds.left;
    final right = page.getClientSize().width - 70;
    final top = start.bounds.top - 2;
    final height = next == null
        ? 54.0
        : (next.bounds.top - top - 2).clamp(36, 78).toDouble();
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(left - 3, top - 2, right - left + 6, height + 4),
    );
    var x = left;
    var y = top;
    var pendingSpace = false;
    var isFirstWord = true;
    for (final part in parts) {
      for (final match in RegExp(r'\S+').allMatches(part.$1)) {
        final word = match.group(0)!;
        final hasLeadingSpace = pendingSpace ||
            (match.start > 0 &&
                RegExp(r'\s').hasMatch(part.$1[match.start - 1]));
        pendingSpace = false;
        final spaceWidth = hasLeadingSpace ? 2.7 : 0.0;
        final width = part.$2.measureString(word).width;
        if (x + spaceWidth + width > right && x > left) {
          y += lineHeight;
          x = left + hangingIndent;
        }
        if (x > left) x += spaceWidth;
        graphics.drawString(word, part.$2,
            brush: black, bounds: Rect.fromLTWH(x, y, width + 1, lineHeight));
        if (part.$3) {
          // Match the template's clean bold-italic weight without making
          // the glyphs look doubled or excessively heavy.
          graphics.drawString(
            word,
            part.$2,
            brush: black,
            bounds: Rect.fromLTWH(x + .25, y, width + 1, lineHeight),
          );
        }
        x += width;
        if (isFirstWord && labelColumnWidth > 0) {
          x = left + labelColumnWidth;
        }
        isFirstWord = false;
      }
      pendingSpace = RegExp(r'\s$').hasMatch(part.$1);
    }
  }

  replaceParagraph(
    itemA,
    itemB,
    'a)  I/We have no reservation to the PBD, including the Supplemental Bid '
    'Bulletins, for the Procurement $projectTitle.',
  );
  replaceParagraph(
    itemC,
    itemD,
    'c)  The total price of our Bid in words and figures, excluding any '
    'discount offered below, is $amountWords Only (PHP $money).',
    font: italic,
  );
  replaceParagraph(
    authorizedLine,
    acknowledgeLine,
    'The undersigned is authorized to submit the bid on behalf of $selected '
    'as evidenced by the attached Secretary’s Certificate.',
  );

  // Restore the source BID FORM's mixed regular and bold-italic emphasis.
  drawStyledParagraph(
    itemA,
    itemB,
    <(String, PdfFont, bool)>[
      (
        'a)  I/We have no reservation to the PBD, including the Supplemental '
            'Bid Bulletins, for the ',
        regular,
        false
      ),
      (projectTitle, italic, true),
      ('.', regular, false),
    ],
    hangingIndent: 16,
    labelColumnWidth: 16,
  );
  drawStyledParagraph(
    itemC,
    itemD,
    <(String, PdfFont, bool)>[
      (
        'c)  The total price of our Bid in words and figures, excluding any '
            'discount offered below, is ',
        itemCRegular,
        false
      ),
      ('$amountWords Only (PHP $money).', itemCBoldItalic, true),
    ],
    hangingIndent: 16,
    labelColumnWidth: 16,
    lineHeight: 14.5,
  );
  drawStyledParagraph(
      authorizedLine,
      acknowledgeLine,
      <(String, PdfFont, bool)>[
        (
          'The undersigned is authorized to submit the bid on behalf of ',
          authorizedRegular,
          false
        ),
        (selected, authorizedItalic, true),
        (' as evidenced by the attached ', authorizedRegular, false),
        ("Secretary's Certificate.", authorizedItalic, true),
      ],
      lineHeight: 14.5);

  // The BID FORM signature is on the following template page. Replace that
  // block separately so it always follows the current sidebar values.
  TextLine? continuationSignature;
  for (final line in lines) {
    if (line.pageIndex <= bidFormPageIndex) continue;
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('DULY AUTHORIZED TO SIGN THE BID FOR AND BEHALF OF')) {
      continuationSignature = line;
      break;
    }
  }
  if (continuationSignature != null) {
    final signaturePage = document.pages[continuationSignature.pageIndex];
    final signatureGraphics = signaturePage.graphics;
    final left = continuationSignature.bounds.left;
    final top = continuationSignature.bounds.top;
    final availableWidth = signaturePage.size.width - left - 42;

    signatureGraphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 4,
        top - 3,
        availableWidth + 8,
        132,
      ),
    );
    signatureGraphics.drawString(
      'Duly authorized to sign the Bid for and behalf of:',
      PdfStandardFont(PdfFontFamily.timesRoman, 12),
      brush: black,
      bounds: Rect.fromLTWH(left, top, availableWidth, 17),
    );

    void drawEmphasized(String text, double y, {bool italicText = true}) {
      final font = PdfStandardFont(
        PdfFontFamily.timesRoman,
        12,
        style: italicText ? PdfFontStyle.italic : PdfFontStyle.regular,
      );
      signatureGraphics.drawString(
        text,
        font,
        brush: black,
        bounds: Rect.fromLTWH(left, y, availableWidth, 17),
      );
      signatureGraphics.drawString(
        text,
        font,
        brush: black,
        bounds: Rect.fromLTWH(left + .2, y, availableWidth, 17),
      );
    }

    drawEmphasized(bidderName, top + 30);
    drawEmphasized(selected, top + 72);
    signatureGraphics.drawString(
      'Authorized Representative',
      PdfStandardFont(
        PdfFontFamily.timesRoman,
        12,
        style: PdfFontStyle.italic,
      ),
      brush: black,
      bounds: Rect.fromLTWH(left, top + 91, availableWidth, 17),
    );
    drawEmphasized(bidDate, top + 110);
  }
}

String _formatBidAmount(double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$whole.${parts.last}';
}

String _bidAmountInWords(double amount) {
  final centavosTotal = (amount * 100).round();
  final pesos = centavosTotal ~/ 100;
  final centavos = centavosTotal % 100;
  final pesoWords = _integerInWords(pesos);
  if (centavos == 0) return '$pesoWords Pesos';
  return '$pesoWords Pesos and ${_integerInWords(centavos)} Centavos';
}

String _integerInWords(int value) {
  if (value == 0) return 'Zero';
  const ones = <String>[
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  const tens = <String>[
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];
  String underThousand(int number) {
    final words = <String>[];
    if (number >= 100) {
      words.add('${ones[number ~/ 100]} Hundred');
      number %= 100;
    }
    if (number >= 20) {
      words.add(tens[number ~/ 10]);
      number %= 10;
    }
    if (number > 0) words.add(ones[number]);
    return words.join(' ');
  }

  final groups = <(int, String)>[
    (1000000000, 'Billion'),
    (1000000, 'Million'),
    (1000, 'Thousand'),
    (1, ''),
  ];
  final words = <String>[];
  var remaining = value;
  for (final group in groups) {
    final part = remaining ~/ group.$1;
    if (part == 0) continue;
    words.add(underThousand(part));
    if (group.$2.isNotEmpty) words.add(group.$2);
    remaining %= group.$1;
  }
  return words.join(' ');
}
