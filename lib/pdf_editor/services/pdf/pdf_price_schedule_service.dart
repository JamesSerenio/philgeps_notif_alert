part of '../pdf_service.dart';

int _drawPriceSchedule(
  PdfDocument document,
  Map<String, String> values,
  int startPageIndex,
) {
  const bundledPriceSchedulePages = 8;
  const landscapeA4 = Size(841.89, 595.28);
  _replacePagesWithBlankSize(
    document,
    startPageIndex,
    bundledPriceSchedulePages,
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

  // The specification column is narrow. Counting only explicit newlines
  // underestimates rows whose individual lines wrap, which used to let the
  // text run past its cell and get clipped. Convert the input into the same
  // visual lines that fit in the PDF column before paginating it.
  final firstPageSize = document.pages[startPageIndex].getClientSize();
  const horizontalMargin = 36.0;
  const baseSpecificationWidth = 158.0 - 52.0;
  const baseTableWidth = 582.0 - 24.0;
  final specificationWidth = (firstPageSize.width - horizontalMargin * 2) *
          baseSpecificationWidth /
          baseTableWidth -
      6;
  final measuringFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);

  List<String> wrapPriceSpecificationLine(String sourceLine) {
    final markerMatch = RegExp(
      r'^\s*(âœ“|âœ”|â›³|â€¢|â—‹|â– |âž¢|-|\[x\])\s*',
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
          measuringFont.measureString(candidate).width > specificationWidth) {
        wrapped.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) wrapped.add(current);
    if (marker != null && wrapped.isNotEmpty) {
      final safeMarker = marker == 'âœ”' || marker == 'â›³' ? 'âœ“' : marker;
      wrapped[0] = '$safeMarker ${wrapped[0]}';
    }
    return wrapped.isEmpty ? <String>[''] : wrapped;
  }

  final priceRows = <Map<String, dynamic>>[];
  for (var sourceIndex = 0;
      sourceIndex < specifications.length;
      sourceIndex++) {
    final source = specifications[sourceIndex] is Map
        ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
        : <String, dynamic>{};
    // Keep each continuation short enough to leave a safe bottom margin.
    // The marked-text renderer can use taller baselines than measureString
    // on Web, so packing too many visual lines can clip the last details.
    const linesPerPriceRow = 16;
    final specificationBlocks =
        _pdfSpecificationBlocks(source['specification']);
    for (var blockIndex = 0;
        blockIndex < specificationBlocks.length;
        blockIndex++) {
      final visualLines = <String>[];
      for (final explicitLine
          in specificationBlocks[blockIndex].split(RegExp(r'\r?\n'))) {
        visualLines.addAll(wrapPriceSpecificationLine(explicitLine));
      }
      if (visualLines.isEmpty) visualLines.add('');
      for (var start = 0;
          start < visualLines.length;
          start += linesPerPriceRow) {
        final continuation = blockIndex > 0 || start > 0;
        priceRows.add(<String, dynamic>{
          ...source,
          '_sourceIndex': sourceIndex,
          '_itemNumber': sourceIndex + 1,
          '_logicalLineIndex': blockIndex,
          '_continuation': continuation,
          '_descriptionLines':
              visualLines.skip(start).take(linesPerPriceRow).toList(),
          if (continuation) 'quantity': '',
          if (continuation) 'unit': '',
        });
      }
    }
  }
  final itemHeights = <double>[
    for (final row in priceRows)
      (_measureMarkedSpecificationTextHeight(
                (row['_descriptionLines'] as List).join('\n'),
                measuringFont,
                specificationWidth,
              ) +
              2)
          .clamp(30.0, 600.0)
          .toDouble(),
  ];
  final pageRowCounts = <int>[];
  var nextItem = 0;
  while (nextItem < priceRows.length) {
    final isFirstPage = pageRowCounts.isEmpty;
    // Only the final page needs to reserve room for TOTAL and the complete
    // signature block. Continuation pages can use the lower part of the
    // sheet, avoiding a tiny table followed by a large empty area.
    // The final sheet must also fit TOTAL and the full signature block.
    // When the remaining rows exceed this reserved capacity, keep a row for
    // a new page instead of squeezing it below the printable table area.
    final finalPageCapacity = isFirstPage ? 220.0 : 280.0;
    final regularPageCapacity = isFirstPage ? 360.0 : 420.0;
    final remainingHeight = itemHeights
        .skip(nextItem)
        .fold<double>(0, (sum, height) => sum + height);
    final availableHeight = remainingHeight <= finalPageCapacity
        ? finalPageCapacity
        : regularPageCapacity;
    final mustLeaveFinalPage = remainingHeight > finalPageCapacity;
    var usedHeight = 0.0;
    var count = 0;
    while (nextItem + count < priceRows.length) {
      final isLastRemainingRow = nextItem + count == priceRows.length - 1;
      // A regular page must not consume the final row. Otherwise TOTAL and
      // the signature block are appended to a page that was filled using
      // the larger non-final capacity and get clipped below the page.
      if (mustLeaveFinalPage && count > 0 && isLastRemainingRow) break;
      final height = itemHeights[nextItem + count];
      if (count > 0 && usedHeight + height > availableHeight) break;
      usedHeight += height;
      count++;
    }
    pageRowCounts.add(count);
    nextItem += count;
  }
  if (pageRowCounts.isEmpty) pageRowCounts.add(0);
  final pageCount = pageRowCounts.length;

  // The source document provides eight Price Schedule sheets. When the
  // entered specifications need more than those templates, insert clean
  // continuation pages immediately after them instead of clipping rows or
  // drawing over the total/signature block.
  if (pageCount > bundledPriceSchedulePages) {
    for (var extraPage = bundledPriceSchedulePages;
        extraPage < pageCount;
        extraPage++) {
      document.pages.insert(
        startPageIndex + extraPage,
        landscapeA4,
        PdfMargins()..all = 0,
      );
    }
  }
  const baseColumns = <double>[
    24,
    52,
    158,
    195,
    226,
    258,
    306,
    365,
    422,
    470,
    526,
    582
  ];
  final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final red = PdfSolidBrush(PdfColor(220, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final priceDescriptionFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final priceBold = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final bold = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final detailFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final detailBoldFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );
  final titleFont =
      PdfStandardFont(PdfFontFamily.timesRoman, 13, style: PdfFontStyle.bold);
  var itemIndex = 0;
  var grandTotal = 0.0;

  for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
    final page = document.pages[startPageIndex + pageNumber];
    final size = page.getClientSize();
    final tableWidth = size.width - horizontalMargin * 2;
    final baseWidth = baseColumns.last - baseColumns.first;
    final columns = <double>[
      for (final baseX in baseColumns)
        horizontalMargin +
            ((baseX - baseColumns.first) / baseWidth) * tableWidth,
    ];
    page.graphics.drawRectangle(
        brush: white, bounds: Rect.fromLTWH(0, 0, size.width, size.height));
    var tableTop = 35.0;
    if (pageNumber == 0) {
      page.graphics.drawString('PRICE SCHEDULE FOR GOODS', titleFont,
          brush: black,
          bounds: Rect.fromLTWH(
            horizontalMargin,
            25,
            tableWidth,
            22,
          ),
          format: PdfStringFormat(alignment: PdfTextAlignment.center));
      page.graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: .7),
        const Offset(horizontalMargin, 50),
        Offset(size.width - horizontalMargin, 50),
      );
      final bidder = (values['bidderName'] ?? '').trim().toUpperCase();
      final reference = (values['referenceNumber'] ?? '').trim();
      const bidderLabel = 'Name of Bidder:';
      final bidderValueLeft =
          horizontalMargin + detailFont.measureString(bidderLabel).width + 3;
      page.graphics.drawString(
        bidderLabel,
        detailFont,
        brush: black,
        bounds: Rect.fromLTWH(horizontalMargin, 58, 120, 17),
      );
      page.graphics.drawString(
        bidder,
        detailBoldFont,
        brush: black,
        bounds: Rect.fromLTWH(bidderValueLeft, 58, tableWidth * .35, 17),
      );
      final bidderWidth =
          detailBoldFont.measureString(bidder).width.clamp(0, 220).toDouble();
      page.graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: 0.5),
        Offset(bidderValueLeft, 73),
        Offset(bidderValueLeft + bidderWidth, 73),
      );

      final projectLabelLeft = horizontalMargin + tableWidth * .53;
      const projectLabel = 'Project ID No.:';
      final projectValueLeft =
          projectLabelLeft + detailFont.measureString(projectLabel).width + 3;
      page.graphics.drawString(
        projectLabel,
        detailFont,
        brush: black,
        bounds: Rect.fromLTWH(projectLabelLeft, 58, 120, 17),
      );
      page.graphics.drawString(
        reference,
        detailBoldFont,
        brush: black,
        bounds: Rect.fromLTWH(projectValueLeft, 58, 100, 17),
      );
      final referenceWidth = detailBoldFont
          .measureString(reference)
          .width
          .clamp(0, 100)
          .toDouble();
      page.graphics.drawLine(
        PdfPen(PdfColor(0, 0, 0), width: 0.5),
        Offset(projectValueLeft, 73),
        Offset(projectValueLeft + referenceWidth, 73),
      );
      page.graphics.drawString(
          'Pricing Details for Goods Offered from Within the Philippines',
          detailFont,
          brush: black,
          bounds: Rect.fromLTWH(
            horizontalMargin,
            77,
            tableWidth * .70,
            17,
          ));
      tableTop = 96;
    }
    const headerHeight = 92.0;
    final rowCount = pageRowCounts[pageNumber];
    final pageStartItem = itemIndex;
    final contentHeight = rowCount == 0
        ? 30.0
        : itemHeights
            .skip(pageStartItem)
            .take(rowCount)
            .fold<double>(0, (sum, height) => sum + height);
    final tableBottom = tableTop + headerHeight + contentHeight;
    for (final x in columns) {
      page.graphics
          .drawLine(gridPen, Offset(x, tableTop), Offset(x, tableBottom));
    }
    page.graphics.drawLine(gridPen, Offset(columns.first, tableTop),
        Offset(columns.last, tableTop));
    page.graphics.drawLine(
        gridPen,
        Offset(columns.first, tableTop + headerHeight),
        Offset(columns.last, tableTop + headerHeight));
    const headers = <String>[
      'Item\nNo.',
      'Specification/s',
      'Country\nof Origin',
      'Qty',
      'Unit',
      'Unit\nPrice/Item',
      'Transportation &\nInsurance and All Other\nCosts Incidental to\ndelivery per Item',
      'Sales & Other\nTaxes Payable if\nContract is Awarded\nper Item',
      'Cost of Incidental\nServices, if applicable,\nper Item',
      'Total Price per Unit\n(columns 5+6+7+8)\n(100%)',
      'Total Price Delivered\nFinal Destination'
    ];
    for (var column = 0; column < headers.length; column++) {
      page.graphics.drawString(headers[column], bold,
          brush: black,
          bounds: Rect.fromLTWH(columns[column] + 2, tableTop + 2,
              columns[column + 1] - columns[column] - 4, headerHeight - 4),
          format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word));
    }
    var y = tableTop + headerHeight;
    for (var row = 0; row < rowCount; row++, itemIndex++) {
      final rowHeight = itemHeights[itemIndex];
      final specification = priceRows[itemIndex];
      final sourceIndex = specification['_sourceIndex'] as int;
      final isContinuation = specification['_continuation'] == true;
      final saved =
          sourceIndex < savedPrices.length && savedPrices[sourceIndex] is Map
              ? savedPrices[sourceIndex] as Map
              : const {};
      final pricing = ItemPricing.fromMaps(specification, saved);
      final total = pricing.adjustedUnitPrice;
      final rawQuantity = (specification['quantity'] ?? '').toString();
      final parsedQuantityText = _numericPart(rawQuantity);
      final quantityText = isContinuation
          ? ''
          : pricing.quantity.type == PricingType.equipmentDaily
              ? '${pricing.quantity.quantity.toString().replaceAll(RegExp(r"\.0$"), "")} x ${pricing.quantity.numberOfDays.toString().replaceAll(RegExp(r"\.0$"), "")} days'
              : parsedQuantityText.isEmpty
                  ? '1'
                  : parsedQuantityText;
      final unitText = isContinuation
          ? ''
          : (specification['unit'] ?? '').toString().trim().isEmpty
              ? 'unit'
              : specification['unit'].toString();
      final delivered = _displayedPdfTotal(pricing, saved);
      if (!isContinuation) grandTotal += delivered;
      final texts = <String>[
        isContinuation ? '' : '${specification['_itemNumber']}',
        '',
        isContinuation ? '' : 'PHL',
        quantityText,
        unitText,
        isContinuation ? '' : money(pricing.unitPriceComponent),
        isContinuation ? '' : money(pricing.transportInsuranceComponent),
        isContinuation ? '' : money(pricing.taxComponent),
        '',
        isContinuation ? '' : money(total),
        isContinuation ? '' : money(delivered),
      ];
      var mergedRowHeight = rowHeight;
      if (!isContinuation) {
        for (var next = itemIndex + 1;
            next < pageStartItem + rowCount &&
                priceRows[next]['_sourceIndex'] == sourceIndex;
            next++) {
          mergedRowHeight += itemHeights[next];
        }
      }
      for (var column = 0; column < texts.length; column++) {
        if (column == 1) continue;
        final isPriceColumn = column >= 5;
        page.graphics.drawString(
            texts[column], isPriceColumn ? priceBold : regular,
            brush: column == 2 || column == 10 ? red : black,
            bounds: Rect.fromLTWH(
                columns[column] + 2,
                y + 1,
                columns[column + 1] - columns[column] - 4,
                (column == 1 ? rowHeight : mergedRowHeight) - 2),
            format: PdfStringFormat(
                alignment: column == 1
                    ? PdfTextAlignment.left
                    : PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle,
                wordWrap: PdfWordWrapType.word));
      }

      final descriptionLines =
          (specification['_descriptionLines'] as List).cast<String>();
      _drawMarkedSpecificationText(
        page.graphics,
        descriptionLines.join('\n'),
        priceDescriptionFont,
        black,
        Rect.fromLTWH(
          columns[1] + 3,
          y + 1,
          columns[2] - columns[1] - 6,
          rowHeight - 2,
        ),
        centerVertically: false,
      );
      y += rowHeight;
      final hasNextRowOnPage = row < rowCount - 1;
      final nextRow = hasNextRowOnPage ? priceRows[itemIndex + 1] : null;
      final nextIsSameItem =
          nextRow != null && nextRow['_sourceIndex'] == sourceIndex;
      final nextIsSameLogicalLine = nextIsSameItem &&
          nextRow['_logicalLineIndex'] == specification['_logicalLineIndex'];
      if (!nextIsSameLogicalLine) {
        page.graphics.drawLine(
          gridPen,
          Offset(nextIsSameItem ? columns[1] : columns.first, y),
          Offset(nextIsSameItem ? columns[2] : columns.last, y),
        );
      }
    }
    if (pageNumber == pageCount - 1) {
      const totalRowHeight = 18.0;
      final totalBottom = y + totalRowHeight;
      page.graphics.drawLine(
        gridPen,
        Offset(columns.first, totalBottom),
        Offset(columns.last, totalBottom),
      );
      for (final x in <double>[
        columns.first,
        columns[9],
        columns[10],
        columns.last
      ]) {
        page.graphics.drawLine(gridPen, Offset(x, y), Offset(x, totalBottom));
      }
      page.graphics.drawString(
        'TOTAL',
        bold,
        brush: black,
        bounds: Rect.fromLTWH(
          columns[9] + 2,
          y + 1,
          columns[10] - columns[9] - 4,
          totalRowHeight - 2,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
      page.graphics.drawString(
        money(grandTotal),
        bold,
        brush: red,
        bounds: Rect.fromLTWH(
          columns[10] + 2,
          y + 1,
          columns[11] - columns[10] - 4,
          totalRowHeight - 2,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
      _drawTechnicalSpecificationsSignatureAt(
        page,
        values,
        totalBottom + 28,
      );
    }
  }
  return pageCount;
}

int _findPriceScheduleStartPage(PdfDocument document) {
  final lines = PdfTextExtractor(document).extractTextLines(
    startPageIndex: 46,
    endPageIndex: 61.clamp(0, document.pages.count - 1).toInt(),
  );
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('PRICE SCHEDULE FOR GOODS') ||
        text.contains('PAGE 1 OF 8')) {
      return line.pageIndex;
    }
  }
  return document.pages.count > 49 ? 49 : -1;
}
