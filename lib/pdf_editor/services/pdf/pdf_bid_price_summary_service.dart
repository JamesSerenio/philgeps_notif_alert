part of '../pdf_service.dart';

int _findBidPriceSummaryStartPage(PdfDocument document) {
  final lines = PdfTextExtractor(document).extractTextLines(
    // Earlier optional-page removals can shift this generated section from
    // its bundled-template position (page 56+) down into the low 50s.
    // Search from page 41 so the final move-to-end pass can always find it.
    startPageIndex: 40,
    endPageIndex: 66.clamp(0, document.pages.count - 1).toInt(),
  );
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('SUMMARY OF BID PRICES')) return line.pageIndex;
  }
  return -1;
}

int _drawBidPriceSummary(
  PdfDocument document,
  Map<String, String> values,
  int startPageIndex,
) {
  const bundledSummaryPages = 3;
  const landscapeA4 = Size(841.89, 595.28);
  _replacePagesWithBlankSize(
    document,
    startPageIndex,
    bundledSummaryPages,
    landscapeA4,
  );
  List<dynamic> specifications = const [];
  List<dynamic> savedPrices = const [];
  final encodedSpecifications = values['technicalSpecifications'] ?? '';
  final encodedPrices = values['priceSchedule'] ?? '';
  if (encodedSpecifications.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encodedSpecifications));
    if (decoded is List) specifications = decoded.take(72).toList();
  }
  if (encodedPrices.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encodedPrices));
    if (decoded is List) savedPrices = decoded.take(72).toList();
  }

  String money(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  final firstPageSize = document.pages[startPageIndex].getClientSize();
  const summaryLeft = 42.0;
  final summaryRight = firstPageSize.width - summaryLeft;
  final summaryItemRight = summaryLeft + 48;
  final summaryDescriptionRight =
      summaryLeft + (summaryRight - summaryLeft) * .67;
  final summaryDescriptionWidth =
      summaryDescriptionRight - summaryItemRight - 8;
  final summaryMeasuringFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);

  List<String> wrapSummaryLine(String sourceLine) {
    final markerMatch = RegExp(
      r'^\s*(✓|✔|⛳|•|○|■|➢|-|\[x\])\s*',
      caseSensitive: false,
    ).firstMatch(sourceLine);
    final marker = markerMatch?.group(1);
    final content = _pdfStandardFontSafeText(
      markerMatch == null
          ? sourceLine.trim()
          : sourceLine.substring(markerMatch.end).trim(),
    );
    final words = content.split(RegExp(r'\s+'));
    if (words.isEmpty || (words.length == 1 && words.first.isEmpty)) {
      return <String>[marker ?? ''];
    }
    final wrapped = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = _pdfStandardFontSafeText(
        current.isEmpty ? word : '$current $word',
      );
      if (current.isNotEmpty &&
          summaryMeasuringFont.measureString(candidate).width >
              summaryDescriptionWidth) {
        wrapped.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) wrapped.add(current);
    if (marker != null && wrapped.isNotEmpty) {
      final safeMarker = marker == '✔' || marker == '⛳' ? '✓' : marker;
      wrapped[0] = '$safeMarker ${wrapped[0]}';
    }
    return wrapped.isEmpty ? <String>[''] : wrapped;
  }

  final summaryRows = <Map<String, dynamic>>[];
  for (var sourceIndex = 0;
      sourceIndex < specifications.length;
      sourceIndex++) {
    final source = specifications[sourceIndex] is Map
        ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
        : <String, dynamic>{};
    const linesPerSummaryRow = 16;
    final visualLines = <String>[];
    final explicitLines = _pdfSpecificationText(source['specification'])
        .replaceAll('\u2029', '\n')
        .split(RegExp(r'\r?\n'));
    for (final explicitLine in explicitLines) {
      visualLines.addAll(wrapSummaryLine(explicitLine));
    }
    if (visualLines.isEmpty) visualLines.add('');
    for (var start = 0;
        start < visualLines.length;
        start += linesPerSummaryRow) {
      summaryRows.add(<String, dynamic>{
        ...source,
        '_sourceIndex': sourceIndex,
        '_itemNumber': sourceIndex + 1,
        '_continuation': start > 0,
        '_descriptionLines':
            visualLines.skip(start).take(linesPerSummaryRow).toList(),
      });
    }
  }
  final summaryRowHeights = <double>[
    for (final row in summaryRows)
      ((row['_descriptionLines'] as List).length * 17.0 + 8.0)
          .clamp(34.0, 260.0)
          .toDouble(),
  ];
  final pageRowCounts = <int>[];
  var nextRow = 0;
  while (nextRow < summaryRows.length) {
    var usedHeight = 0.0;
    var count = 0;
    while (nextRow + count < summaryRows.length) {
      final height = summaryRowHeights[nextRow + count];
      if (count > 0 && usedHeight + height > 320) break;
      usedHeight += height;
      count++;
    }
    pageRowCounts.add(count);
    nextRow += count;
  }
  if (pageRowCounts.isEmpty) pageRowCounts.add(0);
  final pageCount = pageRowCounts.length;
  // The template bundles three Summary sheets. Insert clean continuation
  // pages if wrapped specifications need more than those available sheets.
  if (pageCount > bundledSummaryPages) {
    for (var extraPage = bundledSummaryPages;
        extraPage < pageCount;
        extraPage++) {
      document.pages.insert(
        startPageIndex + extraPage,
        landscapeA4,
        PdfMargins()..all = 0,
      );
    }
  }
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final red = PdfSolidBrush(PdfColor(220, 0, 0));
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
  final titleFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    18,
    style: PdfFontStyle.bold,
  );
  final headerFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final priceFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final instructionFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    14,
    style: PdfFontStyle.italic,
  );
  final signatureBold = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  var itemIndex = 0;
  var grandTotal = 0.0;

  for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
    final page = document.pages[startPageIndex + pageNumber];
    final size = page.getClientSize();
    page.graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(0, 0, size.width, size.height),
    );
    const left = 42.0;
    final right = size.width - 42;
    final itemRight = left + 48;
    final descriptionRight = left + (right - left) * .67;
    var tableTop = 38.0;
    if (pageNumber == 0) {
      page.graphics.drawString(
        'SUMMARY OF BID PRICES',
        titleFont,
        brush: black,
        bounds: Rect.fromLTWH(left, 25, right - left, 26),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      page.graphics.drawString(
        'The Procuring Entity may modify the table below as necessary to comply with the requirements of the Procurement Project',
        instructionFont,
        brush: black,
        bounds: Rect.fromLTWH(left, 51, right - left, 24),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      tableTop = 76;
    }
    const headerHeight = 40.0;
    const sectionHeight = 22.0;
    final visibleSectionHeight = pageNumber == 0 ? sectionHeight : 0.0;
    final rowsOnPage = pageRowCounts[pageNumber];
    final pageStartRow = itemIndex;
    final rowsHeight = summaryRowHeights
        .skip(pageStartRow)
        .take(rowsOnPage)
        .fold<double>(0, (sum, height) => sum + height);
    final dataBottom =
        tableTop + headerHeight + visibleSectionHeight + rowsHeight;
    // Outer borders span the whole table. Internal column dividers skip the
    // merged "Specifications:" row, matching the source template.
    for (final x in <double>[left, right]) {
      page.graphics
          .drawLine(gridPen, Offset(x, tableTop), Offset(x, dataBottom));
    }
    final sectionBottom = tableTop + headerHeight + visibleSectionHeight;
    for (final x in <double>[itemRight, descriptionRight]) {
      page.graphics.drawLine(
        gridPen,
        Offset(x, tableTop),
        Offset(x, tableTop + headerHeight),
      );
      page.graphics.drawLine(
        gridPen,
        Offset(x, sectionBottom),
        Offset(x, dataBottom),
      );
    }
    page.graphics
        .drawLine(gridPen, Offset(left, tableTop), Offset(right, tableTop));
    page.graphics.drawLine(
      gridPen,
      Offset(left, tableTop + headerHeight),
      Offset(right, tableTop + headerHeight),
    );
    const headers = <String>['Item\nNo.', 'Description/s', ''];
    final bounds = <Rect>[
      Rect.fromLTWH(left, tableTop, itemRight - left, headerHeight),
      Rect.fromLTWH(
          itemRight, tableTop, descriptionRight - itemRight, headerHeight),
      Rect.fromLTWH(
          descriptionRight, tableTop, right - descriptionRight, headerHeight),
    ];
    for (var column = 0; column < headers.length; column++) {
      page.graphics.drawString(
        headers[column],
        headerFont,
        brush: black,
        bounds: bounds[column],
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
    }
    var y = tableTop + headerHeight;
    if (pageNumber == 0) {
      page.graphics.drawString(
        'Specifications:',
        headerFont,
        brush: black,
        bounds: Rect.fromLTWH(
            left + 4, y, descriptionRight - left - 8, sectionHeight),
        format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle),
      );
      y += sectionHeight;
      page.graphics.drawLine(gridPen, Offset(left, y), Offset(right, y));
    }
    for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
      final specification = summaryRows[itemIndex];
      final sourceIndex = specification['_sourceIndex'] as int;
      final isContinuation = specification['_continuation'] == true;
      final saved =
          sourceIndex < savedPrices.length && savedPrices[sourceIndex] is Map
              ? savedPrices[sourceIndex] as Map
              : const {};
      final delivered =
          _displayedPdfTotal(ItemPricing.fromMaps(specification, saved), saved);
      if (!isContinuation) grandTotal += delivered;
      final rowHeight = summaryRowHeights[itemIndex];
      final valuesForRow = <String>[
        isContinuation ? '' : '${specification['_itemNumber']}',
        (specification['_descriptionLines'] as List).join('\n'),
        isContinuation ? '' : money(delivered),
      ];
      var mergedRowHeight = rowHeight;
      if (!isContinuation) {
        for (var next = itemIndex + 1;
            next < pageStartRow + rowsOnPage &&
                summaryRows[next]['_sourceIndex'] == sourceIndex;
            next++) {
          mergedRowHeight += summaryRowHeights[next];
        }
      }
      final rowBounds = <Rect>[
        Rect.fromLTWH(
            left + 2, y + 1, itemRight - left - 4, mergedRowHeight - 2),
        Rect.fromLTWH(itemRight + 4, y + 1, descriptionRight - itemRight - 8,
            rowHeight - 2),
        Rect.fromLTWH(descriptionRight + 4, y + 1, right - descriptionRight - 8,
            mergedRowHeight - 2),
      ];
      for (var column = 0; column < valuesForRow.length; column++) {
        if (column == 1) {
          _drawMarkedSpecificationText(
            page.graphics,
            valuesForRow[column],
            rowFont,
            black,
            rowBounds[column],
          );
        } else {
          page.graphics.drawString(
            valuesForRow[column],
            column == 2 ? priceFont : rowFont,
            brush: column == 2 ? red : black,
            bounds: rowBounds[column],
            format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
        }
      }
      y += rowHeight;
      final nextIsSameItem = row < rowsOnPage - 1 &&
          itemIndex + 1 < summaryRows.length &&
          summaryRows[itemIndex + 1]['_sourceIndex'] == sourceIndex;
      if (!nextIsSameItem) {
        page.graphics.drawLine(
          gridPen,
          Offset(left, y),
          Offset(right, y),
        );
      }
    }

    if (pageNumber == pageCount - 1) {
      const totalHeight = 24.0;
      final totalBottom = y + totalHeight;
      page.graphics.drawLine(
          gridPen, Offset(left, totalBottom), Offset(right, totalBottom));
      for (final x in <double>[left, descriptionRight, right]) {
        page.graphics.drawLine(gridPen, Offset(x, y), Offset(x, totalBottom));
      }
      page.graphics.drawString(
        'TOTAL',
        headerFont,
        brush: black,
        bounds: Rect.fromLTWH(left, y, descriptionRight - left, totalHeight),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
      page.graphics.drawString(
        money(grandTotal),
        headerFont,
        brush: red,
        bounds: Rect.fromLTWH(
            descriptionRight, y, right - descriptionRight, totalHeight),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );

      final submittedBy = (values['submittedBy'] ?? '').trim().toUpperCase();
      final bidderName = (values['bidderName'] ?? '').trim().toUpperCase();
      final signatureTop = totalBottom + 20;
      final nameValueLeft = left + 44;
      final submittedWidth = signatureBold.measureString(submittedBy).width;
      final nameLineRight =
          nameValueLeft + (submittedWidth + 32).clamp(150.0, 230.0).toDouble();
      page.graphics.drawString('Name:', signatureBold,
          brush: black, bounds: Rect.fromLTWH(left, signatureTop, 55, 18));
      page.graphics.drawString(submittedBy, signatureBold,
          brush: black,
          bounds: Rect.fromLTWH(
            nameValueLeft,
            signatureTop,
            nameLineRight - nameValueLeft,
            18,
          ));
      page.graphics.drawLine(
        gridPen,
        Offset(nameValueLeft, signatureTop + 16),
        Offset(nameLineRight, signatureTop + 16),
      );
      page.graphics.drawString('Signature:', signatureBold,
          brush: black, bounds: Rect.fromLTWH(left, signatureTop + 18, 72, 18));
      page.graphics.drawLine(
        gridPen,
        Offset(left + 62, signatureTop + 34),
        Offset(left + 300, signatureTop + 34),
      );
      const authorizationText =
          'Duly authorized to sign the Bid for and behalf of:';
      page.graphics.drawString(
        authorizationText,
        signatureBold,
        brush: black,
        bounds: Rect.fromLTWH(left, signatureTop + 36, 360, 18),
      );
      final authorizationWidth =
          signatureBold.measureString(authorizationText).width;
      final bidderLeft = left + authorizationWidth + 4;
      final bidderWidth = signatureBold.measureString(bidderName).width;
      final bidderLineRight =
          bidderLeft + (bidderWidth + 32).clamp(170.0, 260.0).toDouble();
      page.graphics.drawString(
        bidderName,
        signatureBold,
        brush: black,
        bounds: Rect.fromLTWH(
          bidderLeft,
          signatureTop + 36,
          bidderLineRight - bidderLeft,
          18,
        ),
      );
      page.graphics.drawLine(
        gridPen,
        Offset(bidderLeft, signatureTop + 52),
        Offset(bidderLineRight, signatureTop + 52),
      );
    }
  }
  return pageCount;
}
