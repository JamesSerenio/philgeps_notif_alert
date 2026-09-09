part of '../pdf_service.dart';

void _drawSecretaryCertificate(
  PdfDocument document,
  Map<String, String> values,
) {
  final lines = PdfTextExtractor(document).extractTextLines();
  int? pageIndex;
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == "SECRETARY'S CERTIFICATE" ||
        text == 'SECRETARY’S CERTIFICATE') {
      pageIndex = line.pageIndex;
      break;
    }
  }
  if (pageIndex == null) return;

  TextLine? venueLine;
  TextLine? introduction;
  TextLine? itemOne;
  TextLine? itemTwo;
  TextLine? itemThree;
  TextLine? resolved;
  TextLine? resolvedFurther;
  TextLine? resolvedFinally;
  TextLine? itemFour;
  for (final line in lines) {
    if (line.pageIndex != pageIndex) continue;
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('MUNICIPALITY OF')) {
      venueLine ??= line;
    }
    if (text.startsWith('I, ALYSSA LYNN TALINGTING')) introduction ??= line;
    if (text.contains('I AM THE DULY ELECTED AND QUALIFIED')) itemOne ??= line;
    if (text.contains('AS CORPORATE SECRETARY')) itemTwo ??= line;
    if (text.contains('AT THE SPECIAL MEETING OF THE BOARD OF DIRECTORS')) {
      itemThree ??= line;
    }
    if (text.contains('RESOLVED, THAT')) resolved ??= line;
    if (text.contains('RESOLVED FURTHER')) resolvedFurther ??= line;
    if (text.contains('RESOLVED FINALLY')) resolvedFinally ??= line;
    if (text.contains('THE FOREGOING RESOLUTIONS HAVE NOT')) itemFour ??= line;
  }
  if (introduction == null) return;

  final page = document.pages[pageIndex];
  final graphics = page.graphics;
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final bold = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final resolutionItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
    style: PdfFontStyle.italic,
  );
  final resolutionBoldItalic = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
    style: PdfFontStyle.italic,
  );
  const permanentAddress = _permanentBusinessAddress;
  final municipality = (values['municipality'] ?? '').trim();
  final province = (values['province'] ?? '').trim();
  final projectTitle = (values['projectTitle'] ?? '').trim();
  final documentDate = (values['date'] ?? '').trim();
  var meetingDate = documentDate;
  try {
    final parsedDate = DateFormat('MMMM d, yyyy').parseStrict(documentDate);
    meetingDate = DateFormat('MMMM d, yyyy').format(
      parsedDate.subtract(const Duration(days: 3)),
    );
  } on FormatException {
    // Keep the supplied value if it is not in the expected display format.
  }
  final representative =
      (values['submittedByFormalName'] ?? values['submittedBy'] ?? '').trim();

  if (venueLine != null) {
    final venue = venueLine!;
    const venueText = 'Municipality of __________, __________   ) S.S';
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        venue.bounds.left - 2,
        venue.bounds.top - 1,
        page.size.width - venue.bounds.left + 2,
        venue.bounds.height + 4,
      ),
    );
    graphics.drawString(
      venueText,
      regular,
      brush: black,
      bounds: Rect.fromLTWH(
        venue.bounds.left,
        venue.bounds.top,
        page.size.width - venue.bounds.left - 45,
        18,
      ),
    );
  }

  void drawRuns(
    double left,
    double top,
    double width,
    List<(String, PdfFont)> runs, {
    double lineHeight = 15,
  }) {
    var x = left;
    var y = top;
    var pendingSpace = false;
    for (final run in runs) {
      final words = run.$1.trim().split(RegExp(r'\s+'));
      for (final word in words) {
        if (word.isEmpty) continue;
        // Standard PDF fonts can report a zero-width standalone space.
        // Use a visible word gap so mixed-style runs keep natural spacing.
        final measuredSpace =
            run.$2.measureString(' x').width - run.$2.measureString('x').width;
        final spaceWidth = pendingSpace
            ? (measuredSpace > 2.5 ? measuredSpace : run.$2.size * 0.28)
            : 0.0;
        final wordWidth = run.$2.measureString(word).width;
        if (x > left && x + spaceWidth + wordWidth > left + width) {
          x = left;
          y += lineHeight;
        }
        if (pendingSpace && x > left) x += spaceWidth;
        graphics.drawString(
          word,
          run.$2,
          brush: black,
          bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
        );
        x += wordWidth;
        pendingSpace = true;
      }
      pendingSpace = run.$1.endsWith(' ');
    }
  }

  void replaceBlock(
    TextLine? start,
    TextLine? end,
    String text, {
    PdfFont? font,
    double leftInset = 0,
    double rightMargin = 65,
    double bottomPadding = 2,
  }) {
    if (start == null || end == null) return;
    final left = start.bounds.left - leftInset;
    final top = start.bounds.top - 2;
    final bottom = end.bounds.top - bottomPadding;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 3,
        top,
        page.size.width - left + 3,
        bottom - top,
      ),
    );
    graphics.drawString(
      text,
      font ?? regular,
      brush: black,
      bounds: Rect.fromLTWH(
        left,
        start.bounds.top,
        page.size.width - left - rightMargin,
        bottom - start.bounds.top,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.justify,
        wordWrap: PdfWordWrapType.word,
        lineSpacing: 2,
      ),
    );
  }

  replaceBlock(
    introduction,
    itemOne,
    '',
  );
  drawRuns(
    introduction.bounds.left,
    introduction.bounds.top,
    page.size.width - introduction.bounds.left - 65,
    <(String, PdfFont)>[
      ('I, ', regular),
      ('ALYSSA LYNN TALINGTING, ', bold),
      ('of legal age, Filipino, and with office address at ', regular),
      ('$permanentAddress, ', regular),
      (
        'after having been duly sworn in accordance with law, hereby depose and state that:',
        regular,
      ),
    ],
  );
  if (itemOne != null && itemTwo != null) {
    final left = itemOne.bounds.left;
    final top = itemOne.bounds.top - 2;
    final bottom = itemTwo.bounds.top - 2;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 3,
        top,
        page.size.width - left + 3,
        bottom - top,
      ),
    );
    graphics.drawString(
      '1.',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(left, itemOne.bounds.top, 18, 16),
    );
    drawRuns(
      left + 18,
      itemOne.bounds.top,
      page.size.width - left - 83,
      <(String, PdfFont)>[
        (
          'I am the duly elected and qualified Corporate Secretary of ',
          regular,
        ),
        ('MIKATA PRIME CORPORATION, ', bold),
        (
          'a corporation duly organized and existing under and by virtue of the laws of the Republic of the Philippines, with principal office address at ',
          regular,
        ),
        ('$permanentAddress;', regular),
      ],
    );
  }
  if (itemThree != null && resolved != null) {
    final left = itemThree.bounds.left;
    final top = itemThree.bounds.top - 2;
    final bottom = resolved.bounds.top - 2;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 3,
        top,
        page.size.width - left + 3,
        bottom - top,
      ),
    );
    graphics.drawString(
      '3.',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(left, itemThree.bounds.top, 18, 16),
    );
    graphics.drawString(
      'At the special meeting of the Board of Directors of Corporation held '
      'on $meetingDate at its principal office, during which a quorum was '
      'present and acting throughout, the following resolutions were '
      'unanimously passed and approved:',
      regular,
      brush: black,
      bounds: Rect.fromLTWH(
        left + 18,
        itemThree.bounds.top,
        page.size.width - left - 83,
        bottom - itemThree.bounds.top,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.justify,
        wordWrap: PdfWordWrapType.word,
        lineSpacing: 2,
      ),
    );
  }
  if (resolved != null && itemFour != null) {
    final left = resolved.bounds.left;
    final width = page.size.width - left - 35;
    graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 3,
        resolved.bounds.top - 2,
        page.size.width - left + 3,
        itemFour.bounds.top - resolved.bounds.top,
      ),
    );

    double drawResolutionParagraph(
      double top,
      List<(String, PdfFont)> runs,
    ) {
      final words = <(String, PdfFont)>[];
      for (final run in runs) {
        for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
          if (word.isNotEmpty) words.add((word, run.$2));
        }
      }
      final lines = <List<(String, PdfFont)>>[];
      var line = <(String, PdfFont)>[];
      var usedWidth = 0.0;
      final normalSpace = resolutionItalic.measureString(' x').width -
          resolutionItalic.measureString('x').width;
      for (final word in words) {
        final wordWidth = word.$2.measureString(word.$1).width;
        final nextWidth =
            usedWidth + (line.isEmpty ? 0 : normalSpace) + wordWidth;
        if (line.isNotEmpty && nextWidth > width) {
          lines.add(line);
          line = <(String, PdfFont)>[];
          usedWidth = 0;
        }
        if (line.isNotEmpty) usedWidth += normalSpace;
        line.add(word);
        usedWidth += wordWidth;
      }
      if (line.isNotEmpty) lines.add(line);

      const lineHeight = 13.0;
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final currentLine = lines[lineIndex];
        final wordsWidth = currentLine.fold<double>(
          0,
          (total, word) => total + word.$2.measureString(word.$1).width,
        );
        final isLastLine = lineIndex == lines.length - 1;
        final gap = currentLine.length <= 1
            ? 0.0
            : isLastLine
                ? normalSpace
                : (width - wordsWidth) / (currentLine.length - 1);
        var x = left;
        for (final word in currentLine) {
          final wordWidth = word.$2.measureString(word.$1).width;
          graphics.drawString(
            word.$1,
            word.$2,
            brush: black,
            bounds: Rect.fromLTWH(x, top, wordWidth + 2, lineHeight),
          );
          if (identical(word.$2, resolutionBoldItalic)) {
            graphics.drawString(
              word.$1,
              word.$2,
              brush: black,
              bounds: Rect.fromLTWH(x + .3, top, wordWidth + 2, lineHeight),
            );
          }
          x += wordWidth + gap;
        }
        top += lineHeight;
      }
      return top;
    }

    var resolutionTop = resolved.bounds.top;
    resolutionTop = drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
      ('"RESOLVED, ', resolutionItalic),
      ('that ', resolutionItalic),
      ('MIKATA PRIME CORPORATION ', resolutionBoldItalic),
      (
        'is hereby authorized to participate in the public bidding, negotiate, and enter into a contract with the ',
        resolutionItalic
      ),
      ('Municipality of $municipality, $province ', resolutionBoldItalic),
      ('for the project entitled: ', resolutionItalic),
      ('"$projectTitle";', resolutionBoldItalic),
    ]);
    resolutionTop += 7;
    resolutionTop = drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
      ('"RESOLVED FURTHER, ', resolutionItalic),
      ('that the Corporation hereby designates ', resolutionItalic),
      ('${representative.toUpperCase()}, ', resolutionBoldItalic),
      ('as the ', resolutionItalic),
      ('Authorized Representative ', resolutionBoldItalic),
      (
        'of the Corporation, to represent, sign, execute, submit, and deliver any and all documents, agreements, forms, and proposals necessary to effectively participate in the bidding and implement the aforementioned project, granting unto the said representative full power and authority to do and perform any and all acts required;',
        resolutionItalic
      ),
    ]);
    resolutionTop += 7;
    drawResolutionParagraph(resolutionTop, <(String, PdfFont)>[
      ('"RESOLVED FINALLY, ', resolutionItalic),
      (
        'that any and all prior actions taken by the Authorized Representative, as well as the Proprietor/President of the Corporation, ',
        resolutionItalic
      ),
      ('PATRICK CARLO P. DEDEL, ', resolutionBoldItalic),
      (
        'in connection with the foregoing are hereby approved, ratified, and confirmed as the acts of the Corporation."',
        resolutionItalic
      ),
    ]);
  }
  String ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }

  var legalDate = documentDate;
  try {
    final parsedDate = DateFormat('MMMM d, yyyy').parseStrict(documentDate);
    legalDate = '${ordinal(parsedDate.day)} day of '
        '${DateFormat('MMMM yyyy').format(parsedDate)}';
  } on FormatException {
    // Keep the supplied value if it is not in the expected display format.
  }
  const legalLocation = 'Municipality of __________, __________, Philippines';

  // The legal paragraphs belong to the Secretary Certificate continuation
  // page, not to the final page of the generated document. Price Schedule
  // and Summary pages may now follow this section.
  final legalPageIndex =
      pageIndex + 1 < document.pages.count ? pageIndex + 1 : pageIndex;
  TextLine? witnessLine;
  TextLine? subscribedLine;
  for (final line in lines) {
    if (line.pageIndex != legalPageIndex) continue;
    final compactText =
        line.text.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    if (compactText.contains('INWITNESSWHEREOF') ||
        compactText.contains('HEREUNTOSETMYHAND')) {
      witnessLine ??= line;
    }
    if (compactText.contains('SUBSCRIBEDANDSWORN') ||
        compactText.contains('AFFIANTEXHIBITING')) {
      subscribedLine ??= line;
    }
  }

  void replaceLegalParagraph(
    TextLine? sourceLine,
    List<(String, PdfFont)> runs, {
    required double top,
    double height = 36,
  }) {
    final targetPage = document.pages[legalPageIndex];
    final targetGraphics = targetPage.graphics;
    final left = sourceLine?.bounds.left ?? 51.0;
    final paragraphTop = sourceLine?.bounds.top ?? top;
    final width = targetPage.size.width - left - 45;
    targetGraphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(
        left - 4,
        paragraphTop - 2,
        targetPage.size.width - left + 4,
        height + 4,
      ),
    );
    var x = left;
    var y = paragraphTop;
    var hasWord = false;
    const lineHeight = 15.0;
    for (final run in runs) {
      for (final word in run.$1.trim().split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final measuredSpace =
            run.$2.measureString(' x').width - run.$2.measureString('x').width;
        final spaceWidth = hasWord
            ? (measuredSpace > 2.5 ? measuredSpace : run.$2.size * 0.28)
            : 0.0;
        final wordWidth = run.$2.measureString(word).width;
        if (x > left && x + spaceWidth + wordWidth > left + width) {
          x = left;
          y += lineHeight;
          hasWord = false;
        }
        if (hasWord) x += spaceWidth;
        targetGraphics.drawString(
          word,
          run.$2,
          brush: black,
          bounds: Rect.fromLTWH(x, y, wordWidth + 2, lineHeight),
        );
        x += wordWidth;
        hasWord = true;
      }
    }
  }

  replaceLegalParagraph(
      witnessLine,
      <(String, PdfFont)>[
        ('IN WITNESS WHEREOF, ', bold),
        ('I have hereunto set my hand this ', regular),
        ('$legalDate ', bold),
        ('at $legalLocation.', regular),
      ],
      top: 32);
  replaceLegalParagraph(
      subscribedLine,
      <(String, PdfFont)>[
        ('SUBSCRIBED AND SWORN ', bold),
        (
          'to before me this $legalDate at $legalLocation, affiant exhibiting to me their competent evidence of identity.',
          regular
        ),
      ],
      top: 126);
}
