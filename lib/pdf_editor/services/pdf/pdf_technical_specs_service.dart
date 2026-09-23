part of '../pdf_service.dart';

void _drawTechnicalSpecificationsHeader(
  PdfPage page,
  Map<String, String> values,
) {
  final procuringEntity =
      (values['procuringEntity'] ?? '').trim().toUpperCase();
  final projectTitle = (values['projectTitle'] ?? '').trim().toUpperCase();
  final referenceNumber = (values['referenceNumber'] ?? '').trim();

  String wrapText(String text, int maximumCharactersPerLine) {
    final lines = <String>[];
    var currentLine = '';
    for (final word in text.split(RegExp(r'\s+'))) {
      final candidate = currentLine.isEmpty ? word : '$currentLine $word';
      if (currentLine.isNotEmpty &&
          candidate.length > maximumCharactersPerLine) {
        lines.add(currentLine);
        currentLine = word;
      } else {
        currentLine = candidate;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);
    return lines.join('\n');
  }

  final wrappedTitle = wrapText(projectTitle, 42);
  final titleLineCount =
      wrappedTitle.isEmpty ? 1 : wrappedTitle.split('\n').length;
  final graphics = page.graphics;
  final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
  final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
  final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
  final valueFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    11,
    style: PdfFontStyle.bold,
  );
  final lineHeight = valueFont.measureString('Ag').height;
  final titleHeight = titleLineCount * lineHeight;
  const projectTop = 88.0;
  final referenceTop = projectTop + titleHeight + 4;
  final format = PdfStringFormat(
    alignment: PdfTextAlignment.left,
    lineAlignment: PdfVerticalAlignment.top,
    wordWrap: PdfWordWrapType.word,
  );

  // Clear the bundled heading first. Otherwise the original template title
  // remains underneath this updated heading and appears as doubled text.
  graphics.drawRectangle(
    brush: whiteBrush,
    bounds: const Rect.fromLTWH(30, 34, 545, 34),
  );
  graphics.drawString(
    'TECHNICAL SPECIFICATIONS',
    PdfStandardFont(
      PdfFontFamily.timesRoman,
      14,
      style: PdfFontStyle.bold,
    ),
    brush: blackBrush,
    bounds: const Rect.fromLTWH(30, 42, 545, 20),
    format: PdfStringFormat(alignment: PdfTextAlignment.center),
  );

  // Redraw the complete block so old Sumilao values cannot remain visible.
  graphics.drawRectangle(
    brush: whiteBrush,
    bounds: const Rect.fromLTWH(30, 68, 545, 98),
  );

  void drawRow(
    String label,
    String value,
    double top,
    double height,
  ) {
    graphics.drawString(
      label,
      labelFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(36, top, 195, 16),
    );
    graphics.drawString(
      ':',
      labelFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(245, top, 10, 16),
    );
    graphics.drawString(
      value,
      valueFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(280, top, 285, height),
      format: format,
    );
  }

  drawRow('NAME OF THE PROCURING ENTITY', procuringEntity, 74, 16);
  drawRow('PROJECT TITLE', wrappedTitle, projectTop, titleHeight + 1);
  drawRow('REFERENCE NUMBER', referenceNumber, referenceTop, 16);
}

int _drawTechnicalSpecifications(
  PdfDocument document,
  Map<String, String> values,
) {
  List<dynamic> specifications = const [];
  final encodedSpecifications = values['technicalSpecifications'] ?? '';
  if (encodedSpecifications.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encodedSpecifications));
    if (decoded is List) specifications = decoded.take(72).toList();
  }

  // One editor item is one table item. Blank lines and added lines belong in
  // the same specification cell; they must not create extra bordered rows.
  final logicalRows = <Map<String, dynamic>>[];
  for (var sourceIndex = 0;
      sourceIndex < specifications.length;
      sourceIndex++) {
    final source = specifications[sourceIndex] is Map
        ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
        : <String, dynamic>{};
    logicalRows.add(<String, dynamic>{
      ...source,
      '_sourceIndex': sourceIndex,
      '_itemNumber': sourceIndex + 1,
      '_continuation': false,
    });
  }

  final hasAnyParameter = logicalRows.any(
    (row) => (row['parameter'] ?? '').toString().trim().isNotEmpty,
  );
  // When no item has an optional parameter, remove that column completely
  // and share its width between Specification and Statement of Compliance.
  final columns = hasAnyParameter
      ? <double>[36, 94, 270, 335, 400, 490, 576]
      : <double>[36, 94, 325, 390, 455, 576];
  final projectTitle = (values['projectTitle'] ?? '').trim().toUpperCase();
  var currentTitleLine = '';
  var titleLineCount = 0;
  for (final word in projectTitle.split(RegExp(r'\s+'))) {
    final candidate =
        currentTitleLine.isEmpty ? word : '$currentTitleLine $word';
    if (currentTitleLine.isNotEmpty && candidate.length > 42) {
      titleLineCount++;
      currentTitleLine = word;
    } else {
      currentTitleLine = candidate;
    }
  }
  if (currentTitleLine.isNotEmpty) titleLineCount++;
  if (titleLineCount == 0) titleLineCount = 1;
  final technicalHeaderFont = PdfStandardFont(PdfFontFamily.timesRoman, 9);
  final technicalHeaderLineHeight =
      technicalHeaderFont.measureString('Ag').height;
  final referenceTop = 88 + titleLineCount * technicalHeaderLineHeight + 4;
  final statementTop = (referenceTop + 30).clamp(125.0, 180.0).toDouble();
  const statementTitleHeight = 24.0;
  const statementBodyHeight = 165.0;
  final firstTableTop =
      statementTop + statementTitleHeight + statementBodyHeight;
  const headerHeight = 50.0;
  const minimumRowHeight = 18.0;
  const signatureSpace = 125.0;
  final firstPage = document.pages[46];
  final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
  final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
  final gridPen = PdfPen(PdfColor(0, 0, 0), width: 0.5);
  // Match the clearly readable body-text size used by the source template.
  // The compliance value keeps its existing bold styling and size below.
  final regularFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final boldFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final statementTitleFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final statementBodyFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final statementEmphasisFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final specificationWidth = columns[2] - columns[1] - 6;
  final parameterWidth = hasAnyParameter ? columns[5] - columns[4] - 6 : 0.0;
  // A logical Add line can still wrap into many visual lines. Split it by
  // measured PDF height before calculating pages so no row can draw outside
  // its border or overlap the signature block.
  final renderRows = <Map<String, dynamic>>[];
  for (final logicalRow in logicalRows) {
    final specificationBlocks = _pdfSpecificationBlocks(
      logicalRow['specification'],
    );
    final parameterText = (logicalRow['parameter'] ?? '').toString();
    for (var blockIndex = 0;
        blockIndex < specificationBlocks.length;
        blockIndex++) {
      final chunks = _chunkMarkedSpecificationLines(
        specificationBlocks[blockIndex].split(RegExp(r'\r?\n')),
        regularFont,
        specificationWidth,
        220,
      );
      final parameterChunks =
          blockIndex != 0 || !hasAnyParameter || parameterText.trim().isEmpty
              ? <List<String>>[]
              : _chunkMarkedSpecificationLines(
                  parameterText.split(RegExp(r'\r?\n')),
                  regularFont,
                  parameterWidth,
                  220,
                );
      final chunkCount = chunks.length > parameterChunks.length
          ? chunks.length
          : parameterChunks.length;
      for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
        final continuation = logicalRow['_continuation'] == true ||
            blockIndex > 0 ||
            chunkIndex > 0;
        renderRows.add(<String, dynamic>{
          ...logicalRow,
          '_logicalLineIndex': blockIndex,
          'specification':
              chunkIndex < chunks.length ? chunks[chunkIndex].join('\n') : '',
          'parameter': chunkIndex < parameterChunks.length
              ? parameterChunks[chunkIndex].join('\n')
              : '',
          '_continuation': continuation,
          if (continuation) 'quantity': '',
          if (continuation) 'unit': '',
        });
      }
    }
  }
  final rowHeights = <double>[
    for (final value in renderRows)
      (() {
        final specification =
            value is Map ? (value['specification'] ?? '').toString() : '';
        final parameter =
            value is Map ? (value['parameter'] ?? '').toString() : '';
        final specificationHeight = _measureMarkedSpecificationTextHeight(
          specification,
          regularFont,
          specificationWidth,
        );
        final parameterHeight = hasAnyParameter
            ? _measureMarkedSpecificationTextHeight(
                parameter,
                regularFont,
                parameterWidth,
              )
            : 0.0;
        final contentHeight = specificationHeight > parameterHeight
            ? specificationHeight
            : parameterHeight;
        return (contentHeight + 14).clamp(minimumRowHeight, 240).toDouble();
      })(),
  ];
  final pageRowCounts = <int>[];
  var nextRow = 0;
  while (nextRow < rowHeights.length) {
    final tableTop = pageRowCounts.isEmpty ? firstTableTop : 28.0;
    final availableHeight = firstPage.getClientSize().height -
        tableTop -
        headerHeight -
        signatureSpace;
    var usedHeight = 0.0;
    var rowsOnPage = 0;
    while (nextRow + rowsOnPage < rowHeights.length) {
      final height = rowHeights[nextRow + rowsOnPage];
      if (rowsOnPage > 0 && usedHeight + height > availableHeight) break;
      usedHeight += height;
      rowsOnPage++;
    }
    pageRowCounts.add(rowsOnPage);
    nextRow += rowsOnPage;
  }
  if (pageRowCounts.isEmpty) pageRowCounts.add(0);
  final pageCount = pageRowCounts.length;
  const bundledTechnicalPages = 3;
  if (pageCount > bundledTechnicalPages) {
    final sourceSize = document.pages[46].size;
    for (var extraPage = bundledTechnicalPages;
        extraPage < pageCount;
        extraPage++) {
      document.pages.insert(
        46 + extraPage,
        sourceSize,
        PdfMargins()..all = 0,
      );
    }
  }
  var itemIndex = 0;

  const statementText =
      'Bidders must state here either ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œComplyÃƒÂ¢Ã¢â€šÂ¬Ã‚Â or ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œNot ComplyÃƒÂ¢Ã¢â€šÂ¬Ã‚Â against each '
      'of the individual parameters of each Specification stating the '
      'corresponding performance parameter of the equipment offered. '
      'Statements of ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œComplyÃƒÂ¢Ã¢â€šÂ¬Ã‚Â or ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œNot ComplyÃƒÂ¢Ã¢â€šÂ¬Ã‚Â must be supported by evidence '
      'in a Bidders Bid and cross-referenced to that evidence. Evidence shall '
      'be in the form of manufacturersÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ un-amended sales literature, '
      'unconditional statements of specification and compliance issued by '
      'the manufacturer, samples, independent test data etc. as appropriate. '
      'A statement that is not supported by evidence or is subsequently '
      'found to be contradicted by the evidence presented will render the Bid '
      'under evaluation liable for rejection. A statement either in the '
      'Bidders statement of compliance or the supporting evidence that is '
      'found to be false either during Bid evaluation, post qualification or '
      'the execution of the Contract may be regarded as fraudulent and render '
      'the Bidder or supplier liable for prosecution subject to the provisions of';
  const statementBoldItb = 'ITB';
  const statementRegularClause = 'Clause';
  const statementFirstBoldText = 'Error! Reference source not found';
  const statementRegularConnector = 'and/or GCC Clause';
  const statementSecondBoldText = 'Error! Reference source not found.';

  // Rebuild the statement and table as one shared bordered structure.
  firstPage.graphics.drawRectangle(
    brush: whiteBrush,
    bounds: Rect.fromLTWH(
      columns.first - 2,
      statementTop - 2,
      columns.last - columns.first + 4,
      firstPage.getClientSize().height - statementTop + 2,
    ),
  );
  firstPage.graphics.drawRectangle(
    pen: gridPen,
    bounds: Rect.fromLTWH(
      columns.first,
      statementTop,
      columns.last - columns.first,
      statementTitleHeight + statementBodyHeight,
    ),
  );
  firstPage.graphics.drawLine(
    gridPen,
    Offset(columns.first, statementTop + statementTitleHeight),
    Offset(columns.last, statementTop + statementTitleHeight),
  );
  firstPage.graphics.drawString(
    'Statement of Compliance',
    statementTitleFont,
    brush: blackBrush,
    bounds: Rect.fromLTWH(
      columns.first + 6,
      statementTop + 4,
      columns.last - columns.first - 12,
      statementTitleHeight - 8,
    ),
    format: PdfStringFormat(
      alignment: PdfTextAlignment.left,
      lineAlignment: PdfVerticalAlignment.middle,
    ),
  );
  // Lay out the regular paragraph and bold clause as one continuous flow.
  // Separate drawString boxes introduce a visible gap and can split the GCC
  // phrase, so words are wrapped together while retaining their own fonts.
  final statementWords = <({String text, PdfFont font})>[
    for (final word in statementText.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementBodyFont),
    for (final word in statementBoldItb.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementEmphasisFont),
    for (final word in statementRegularClause.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementBodyFont),
    for (final word in statementFirstBoldText.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementEmphasisFont),
    for (final word in statementRegularConnector.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementBodyFont),
    for (final word in statementSecondBoldText.split(RegExp(r'\s+')))
      (text: _pdfStandardFontSafeText(word), font: statementEmphasisFont),
  ];
  final statementLines = <List<({String text, PdfFont font})>>[];
  var currentLine = <({String text, PdfFont font})>[];
  var currentWidth = 0.0;
  final statementLeft = columns.first + 6;
  final statementWidth = columns.last - columns.first - 12;
  // Syncfusion's standard-font measurement can report a zero-width string
  // for a standalone space. Use the Times Roman 12pt visual space width so
  // individually rendered words never touch each other.
  const spaceWidth = 3.4;

  for (final word in statementWords) {
    final wordWidth = word.font.measureString(word.text).width;
    final candidateWidth =
        currentWidth + (currentLine.isEmpty ? 0 : spaceWidth) + wordWidth;
    if (currentLine.isNotEmpty && candidateWidth > statementWidth) {
      statementLines.add(currentLine);
      currentLine = <({String text, PdfFont font})>[word];
      currentWidth = wordWidth;
    } else {
      currentLine.add(word);
      currentWidth = candidateWidth;
    }
  }
  if (currentLine.isNotEmpty) statementLines.add(currentLine);

  final lineHeight = statementBodyFont.measureString('Ag').height + 0.6;
  var statementY = statementTop + statementTitleHeight + 7;
  for (var lineIndex = 0; lineIndex < statementLines.length; lineIndex++) {
    final line = statementLines[lineIndex];
    final wordsWidth = line.fold<double>(
      0,
      (total, word) => total + word.font.measureString(word.text).width,
    );
    final isLastLine = lineIndex == statementLines.length - 1;
    final calculatedGap = line.length <= 1
        ? 0.0
        : isLastLine
            ? spaceWidth
            : (statementWidth - wordsWidth) / (line.length - 1);
    final gapWidth = line.length <= 1
        ? 0.0
        : calculatedGap.clamp(spaceWidth, spaceWidth * 2.5).toDouble();
    var statementX = statementLeft;
    for (var wordIndex = 0; wordIndex < line.length; wordIndex++) {
      final word = line[wordIndex];
      final wordWidth = word.font.measureString(word.text).width;
      firstPage.graphics.drawString(
        word.text,
        word.font,
        brush: blackBrush,
        bounds:
            Rect.fromLTWH(statementX, statementY, wordWidth + 4, lineHeight),
      );
      statementX += wordWidth;
      if (wordIndex < line.length - 1) statementX += gapWidth;
    }
    statementY += lineHeight;
  }

  for (var technicalPage = 0; technicalPage < pageCount; technicalPage++) {
    final page = document.pages[46 + technicalPage];
    final pageSize = page.getClientSize();
    final tableTop = technicalPage == 0 ? firstTableTop : 28.0;
    final rowsOnPage = pageRowCounts[technicalPage];
    final pageStartItemIndex = itemIndex;
    final tableRowsHeight = rowHeights
        .skip(pageStartItemIndex)
        .take(rowsOnPage)
        .fold<double>(0, (total, height) => total + height);
    final tableBottom = tableTop + headerHeight + tableRowsHeight;

    if (technicalPage > 0) {
      // Bundled continuation templates contain old sample rows near the top.
      // Clear the complete page first so no stale fragments (for example
      // "(Frame)") remain above or behind the rebuilt continuation table.
      page.graphics.drawRectangle(
        brush: whiteBrush,
        bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      );
    }

    // Remove the fixed template rows and its old signature block.
    page.graphics.drawRectangle(
      brush: whiteBrush,
      bounds: Rect.fromLTWH(
        28,
        tableTop,
        pageSize.width - 56,
        pageSize.height - tableTop,
      ),
    );

    for (final x in columns) {
      page.graphics.drawLine(
        gridPen,
        Offset(x, tableTop),
        Offset(x, tableBottom),
      );
    }
    var horizontalY = tableTop;
    page.graphics.drawLine(
      gridPen,
      Offset(columns.first, horizontalY),
      Offset(columns.last, horizontalY),
    );
    horizontalY += headerHeight;
    page.graphics.drawLine(
      gridPen,
      Offset(columns.first, horizontalY),
      Offset(columns.last, horizontalY),
    );
    for (var row = 0; row < rowsOnPage; row++) {
      horizontalY += rowHeights[pageStartItemIndex + row];
      final currentIndex = pageStartItemIndex + row;
      final currentItem = '${renderRows[currentIndex]['_itemNumber']}';
      final nextItem = currentIndex + 1 < renderRows.length
          ? '${renderRows[currentIndex + 1]['_itemNumber']}'
          : null;
      final isPageBottom = row == rowsOnPage - 1;
      final nextLogicalLine = currentIndex + 1 < renderRows.length
          ? renderRows[currentIndex + 1]['_logicalLineIndex']
          : null;
      final isInternalItemLine = !isPageBottom &&
          currentItem == nextItem &&
          renderRows[currentIndex]['_logicalLineIndex'] == nextLogicalLine;
      if (!isInternalItemLine) {
        final isBlockDivider = !isPageBottom && currentItem == nextItem;
        if (isBlockDivider) {
          // Added-line dividers belong only to Specification/s and Statement
          // of Compliance. Item No., Qty, Unit, and Parameter remain merged.
          page.graphics.drawLine(
            gridPen,
            Offset(columns[1], horizontalY),
            Offset(columns[2], horizontalY),
          );
          page.graphics.drawLine(
            gridPen,
            Offset(columns[columns.length - 2], horizontalY),
            Offset(columns.last, horizontalY),
          );
        } else {
          page.graphics.drawLine(
            gridPen,
            Offset(columns.first, horizontalY),
            Offset(columns.last, horizontalY),
          );
        }
      }
    }

    final headers = <String>[
      'Item\nNo.',
      'Specification/s',
      'Qty',
      'Unit',
      if (hasAnyParameter) 'Parameter',
      'Statement\nof\nCompliance',
    ];
    for (var column = 0; column < headers.length; column++) {
      page.graphics.drawString(
        headers[column],
        boldFont,
        brush: blackBrush,
        bounds: Rect.fromLTWH(
          columns[column] + 3,
          tableTop + 2,
          columns[column + 1] - columns[column] - 6,
          headerHeight - 4,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
          wordWrap: PdfWordWrapType.word,
        ),
      );
    }

    var rowTop = tableTop + headerHeight;
    for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
      final specification = renderRows[itemIndex];
      final isContinuation = specification['_continuation'] == true;
      final itemNumber = '${specification['_itemNumber']}';
      final previousItemNumber =
          row == 0 ? null : '${renderRows[itemIndex - 1]['_itemNumber']}';
      final startsContinuationPage = row == 0 && isContinuation;
      final sourceIndex = specification['_sourceIndex'] as int;
      final original = sourceIndex < specifications.length &&
              specifications[sourceIndex] is Map
          ? specifications[sourceIndex] as Map
          : const {};
      final texts = <String>[
        itemNumber == previousItemNumber ? '' : itemNumber,
        (specification['specification'] ?? '').toString(),
        startsContinuationPage
            ? (original['quantity'] ?? '').toString()
            : (specification['quantity'] ?? '').toString(),
        startsContinuationPage
            ? (original['unit'] ?? '').toString()
            : (specification['unit'] ?? '').toString(),
        if (hasAnyParameter) (specification['parameter'] ?? '').toString(),
        'COMPLY',
      ];
      final rowHeight = rowHeights[itemIndex];
      for (var column = 0; column < texts.length; column++) {
        final isMergedColumn = column == 0 || column == 2 || column == 3;
        if (isMergedColumn && itemNumber == previousItemNumber) continue;
        var cellHeight = rowHeight - 2;
        if (isMergedColumn) {
          for (var next = itemIndex + 1;
              next < pageStartItemIndex + rowsOnPage &&
                  '${renderRows[next]['_itemNumber']}' == itemNumber;
              next++) {
            cellHeight += rowHeights[next];
          }
        }
        final cellBounds = Rect.fromLTWH(
          columns[column] + 3,
          rowTop + 1,
          columns[column + 1] - columns[column] - 6,
          cellHeight,
        );
        if (column == 1) {
          _drawMarkedSpecificationText(
            page.graphics,
            texts[column],
            regularFont,
            blackBrush,
            cellBounds,
          );
        } else {
          page.graphics.drawString(
            texts[column],
            column == texts.length - 1 ? boldFont : regularFont,
            brush: blackBrush,
            bounds: cellBounds,
            format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
        }
      }
      rowTop += rowHeight;
    }

    if (technicalPage == pageCount - 1) {
      _drawTechnicalSpecificationsSignatureAt(
        page,
        values,
        tableBottom + 22,
      );
    }
  }

  return pageCount;
}

void _drawTechnicalSpecificationsSignatureAt(
  PdfPage page,
  Map<String, String> values,
  double top,
) {
  final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
  final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
  final date = (values['date'] ?? '').trim();
  final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
  final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 14);
  final valueFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    14,
    style: PdfFontStyle.bold,
  );
  final captionFont = PdfStandardFont(PdfFontFamily.timesRoman, 11);
  // Match the formal signature grid used by the contract-statement pages.
  const labelLeft = 36.0;
  const colonLeft = 130.0;
  const valueLeft = 165.0;

  void drawRow(String label, String value, double y) {
    page.graphics.drawString(
      label,
      labelFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(labelLeft, y, 90, 22),
    );
    page.graphics.drawString(
      ':',
      labelFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(colonLeft, y, 10, 22),
    );
    page.graphics.drawString(
      value,
      valueFont,
      brush: blackBrush,
      bounds: Rect.fromLTWH(valueLeft, y, 360, 22),
    );
  }

  drawRow('Submitted by', submittedBy, top);
  final nameWidth =
      valueFont.measureString(submittedBy).width.clamp(0, 360).toDouble();
  page.graphics.drawLine(
    PdfPen(PdfColor(0, 0, 0), width: 0.5),
    Offset(valueLeft, top + 18),
    Offset(valueLeft + nameWidth, top + 18),
  );
  page.graphics.drawString(
    '(Printed Name & Signature)',
    captionFont,
    brush: blackBrush,
    bounds: Rect.fromLTWH(valueLeft, top + 22, 230, 17),
  );
  drawRow('Designation', 'Authorized Representative', top + 45);
  drawRow('Name of Firm', bidderName, top + 70);
  drawRow('Date', date, top + 95);
}
