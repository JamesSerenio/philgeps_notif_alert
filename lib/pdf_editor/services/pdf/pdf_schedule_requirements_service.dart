part of '../pdf_service.dart';

int _findScheduleRequirementsStartPage(PdfDocument document) {
  final lines = PdfTextExtractor(document).extractTextLines(
    startPageIndex: 60,
    endPageIndex: 72.clamp(0, document.pages.count - 1).toInt(),
  );
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.contains('SCHEDULE OF REQUIREMENTS')) return line.pageIndex;
  }
  return -1;
}

int _drawScheduleRequirements(
  PdfDocument document,
  Map<String, String> values,
  int startPageIndex,
) {
  const bundledSchedulePages = 3;
  const portraitA4 = Size(595.28, 841.89);
  _replacePagesWithBlankSize(
    document,
    startPageIndex,
    bundledSchedulePages,
    portraitA4,
  );
  List<dynamic> specifications = const [];
  final encoded = values['technicalSpecifications'] ?? '';
  if (encoded.isNotEmpty) {
    final decoded = _pdfSafeDecodedValue(jsonDecode(encoded));
    if (decoded is List) specifications = decoded.take(72).toList();
  }
  final delivery = (values['deliveredWeeksMonths'] ?? '').trim();
  final includeTotal =
      (values['includeScheduleTotal'] ?? '').toLowerCase() == 'true';
  List<dynamic> savedPrices = const [];
  final encodedPrices = values['priceSchedule'] ?? '';
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

  String scheduleDescription(dynamic value) {
    final specification = value is Map ? value : const {};
    final name = _pdfSpecificationText(specification['specification']).trim();
    final details = (specification['parameter'] ?? '').toString().trim();
    if (details.isEmpty) return name;
    if (name.isEmpty || details == name) return details;
    return '$name\n$details';
  }

  final scheduleMeasuringFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final schedulePageWidth =
      document.pages[startPageIndex].getClientSize().width;
  final scheduleSpecificationWidth = (schedulePageWidth - 84) * .37 - 6;
  final scheduleRows = <Map<String, dynamic>>[];
  for (var sourceIndex = 0;
      sourceIndex < specifications.length;
      sourceIndex++) {
    final source = specifications[sourceIndex] is Map
        ? Map<String, dynamic>.from(specifications[sourceIndex] as Map)
        : <String, dynamic>{};
    final logicalLines = scheduleDescription(source)
        .split(RegExp(r'\r?\n\s*\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final rows = logicalLines.isEmpty ? <String>[''] : logicalLines;
    for (var logicalIndex = 0; logicalIndex < rows.length; logicalIndex++) {
      final chunks = _chunkMarkedSpecificationLines(
        rows[logicalIndex].split(RegExp(r'\r?\n')),
        scheduleMeasuringFont,
        scheduleSpecificationWidth,
        220,
      );
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        scheduleRows.add(<String, dynamic>{
          ...source,
          '_sourceIndex': sourceIndex,
          '_itemNumber': sourceIndex + 1,
          '_logicalLineIndex': logicalIndex,
          '_continuation': logicalIndex > 0 || chunkIndex > 0,
          '_description': chunks[chunkIndex].join('\n'),
        });
      }
    }
  }

  final rowHeights = <double>[
    for (final value in scheduleRows)
      (() {
        final description = (value['_description'] ?? '').toString();
        return (_measureMarkedSpecificationTextHeight(
                  description,
                  scheduleMeasuringFont,
                  scheduleSpecificationWidth,
                ) +
                2)
            .clamp(23.0, 240.0)
            .toDouble();
      })(),
  ];
  final pageRowCounts = <int>[];
  var nextRow = 0;
  while (nextRow < scheduleRows.length) {
    // The first sheet has the document heading; continuation sheets have
    // more vertical room. Keep space below the table for the signature.
    final availableHeight = pageRowCounts.isEmpty ? 410.0 : 545.0;
    var usedHeight = 0.0;
    var count = 0;
    while (nextRow + count < scheduleRows.length) {
      final height = rowHeights[nextRow + count];
      if (count > 0 && usedHeight + height > availableHeight) break;
      usedHeight += height;
      count++;
    }
    pageRowCounts.add(count);
    nextRow += count;
  }
  if (pageRowCounts.isEmpty) pageRowCounts.add(0);
  final pageCount = pageRowCounts.length;
  if (pageCount > bundledSchedulePages) {
    for (var extraPage = bundledSchedulePages;
        extraPage < pageCount;
        extraPage++) {
      document.pages.insert(
        startPageIndex + extraPage,
        portraitA4,
        PdfMargins()..all = 0,
      );
    }
  }
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final gridPen = PdfPen(PdfColor(0, 0, 0), width: .55);
  final titleFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    18,
    style: PdfFontStyle.bold,
  );
  final labelFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final valueFont = PdfStandardFont(
    PdfFontFamily.timesRoman,
    13,
    style: PdfFontStyle.bold,
  );
  final rowFont = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  var itemIndex = 0;

  for (var pageNumber = 0; pageNumber < pageCount; pageNumber++) {
    final page = document.pages[startPageIndex + pageNumber];
    final size = page.getClientSize();
    page.graphics.drawRectangle(
      brush: white,
      bounds: Rect.fromLTWH(0, 0, size.width, size.height),
    );
    const left = 42.0;
    final right = size.width - 42;
    final width = right - left;
    final columns = <double>[
      left,
      left + width * .11,
      left + width * .48,
      left + width * .62,
      left + width * .78,
      right,
    ];
    var tableTop = 35.0;
    if (pageNumber == 0) {
      page.graphics.drawString(
        'Schedule of Requirements',
        titleFont,
        brush: black,
        bounds: Rect.fromLTWH(left, 24, width, 24),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
      final procuringEntity =
          (values['procuringEntity'] ?? '').trim().toUpperCase();
      final projectTitle = (values['projectTitle'] ?? '').trim().toUpperCase();
      final reference = (values['referenceNumber'] ?? '').trim();
      const labelLeft = 48.0;
      const colonLeft = 250.0;
      const valueLeft = 280.0;
      void headerRow(String label, String value, double y, double height) {
        page.graphics.drawString(label, labelFont,
            brush: black, bounds: Rect.fromLTWH(labelLeft, y, 190, 14));
        page.graphics.drawString(':', labelFont,
            brush: black, bounds: Rect.fromLTWH(colonLeft, y, 10, 14));
        page.graphics.drawString(
          value,
          valueFont,
          brush: black,
          bounds:
              Rect.fromLTWH(valueLeft, y, size.width - valueLeft - 45, height),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
        );
      }

      headerRow('NAME OF THE PROCURING ENTITY', procuringEntity, 58, 15);
      headerRow('PROJECT TITLE', projectTitle, 76, 34);
      headerRow('REFERENCE NUMBER', reference, 112, 15);
      page.graphics.drawString(
        'The delivery schedule is expressed as weeks/month stipulated share after a delivery date which is the date of delivery to the project site.',
        labelFont,
        brush: black,
        bounds: Rect.fromLTWH(left, 135, width, 28),
        format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
      );
      tableTop = 168;
    }
    const headerHeight = 48.0;
    final rowsOnPage = pageRowCounts[pageNumber];
    final pageStartItem = itemIndex;
    final tableBottom = tableTop +
        headerHeight +
        rowHeights
            .skip(itemIndex)
            .take(rowsOnPage)
            .fold<double>(0, (sum, height) => sum + height);
    for (final x in columns) {
      page.graphics
          .drawLine(gridPen, Offset(x, tableTop), Offset(x, tableBottom));
    }
    page.graphics
        .drawLine(gridPen, Offset(left, tableTop), Offset(right, tableTop));
    page.graphics.drawLine(
      gridPen,
      Offset(left, tableTop + headerHeight),
      Offset(right, tableTop + headerHeight),
    );
    final headers = <String>[
      'Item\nNo.',
      'Specification/s',
      includeTotal ? 'Qty/Unit' : 'Qty',
      includeTotal ? 'Total' : 'Unit',
      'Delivered\nWeeks/Months',
    ];
    for (var column = 0; column < headers.length; column++) {
      page.graphics.drawString(
        headers[column],
        valueFont,
        brush: black,
        bounds: Rect.fromLTWH(
          columns[column] + 2,
          tableTop + 2,
          columns[column + 1] - columns[column] - 4,
          headerHeight - 4,
        ),
        format: PdfStringFormat(
          alignment: PdfTextAlignment.center,
          lineAlignment: PdfVerticalAlignment.middle,
        ),
      );
    }
    var y = tableTop + headerHeight;
    for (var row = 0; row < rowsOnPage; row++, itemIndex++) {
      final rowHeight = rowHeights[itemIndex];
      final specification = scheduleRows[itemIndex];
      final sourceIndex = specification['_sourceIndex'] as int;
      final isContinuation = specification['_continuation'] == true;
      final quantity = _numericPart(specification['quantity']);
      final unit = (specification['unit'] ?? '').toString().trim();
      final saved =
          sourceIndex < savedPrices.length && savedPrices[sourceIndex] is Map
              ? savedPrices[sourceIndex] as Map
              : const {};
      final deliveredTotal =
          _displayedPdfTotal(ItemPricing.fromMaps(specification, saved), saved);
      final texts = <String>[
        isContinuation ? '' : '${specification['_itemNumber']}',
        (specification['_description'] ?? '').toString(),
        isContinuation
            ? ''
            : includeTotal
                ? [quantity, unit].where((value) => value.isNotEmpty).join(' ')
                : quantity,
        isContinuation
            ? ''
            : includeTotal
                ? (deliveredTotal == 0 ? '' : money(deliveredTotal))
                : unit,
        isContinuation ? '' : delivery,
      ];
      var mergedRowHeight = rowHeight;
      if (!isContinuation) {
        for (var next = itemIndex + 1;
            next < pageStartItem + rowsOnPage &&
                scheduleRows[next]['_sourceIndex'] == sourceIndex;
            next++) {
          mergedRowHeight += rowHeights[next];
        }
      }
      for (var column = 0; column < texts.length; column++) {
        final cellBounds = Rect.fromLTWH(
          columns[column] + 3,
          y + 1,
          columns[column + 1] - columns[column] - 6,
          (column == 1 ? rowHeight : mergedRowHeight) - 2,
        );
        if (column == 1) {
          _drawMarkedSpecificationText(
            page.graphics,
            texts[column],
            rowFont,
            black,
            cellBounds,
            centerVertically: false,
          );
        } else {
          page.graphics.drawString(
            texts[column],
            column == 4 ? valueFont : rowFont,
            brush: black,
            bounds: cellBounds,
            format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle,
              wordWrap: PdfWordWrapType.word,
            ),
          );
        }
      }
      y += rowHeight;
      final hasNextRowOnPage = row < rowsOnPage - 1;
      final nextRow = hasNextRowOnPage ? scheduleRows[itemIndex + 1] : null;
      final nextIsSameItem =
          nextRow != null && nextRow['_sourceIndex'] == sourceIndex;
      final nextIsSameLogicalLine = nextIsSameItem &&
          nextRow['_logicalLineIndex'] == specification['_logicalLineIndex'];
      if (!nextIsSameLogicalLine) {
        page.graphics.drawLine(
          gridPen,
          Offset(nextIsSameItem ? columns[1] : left, y),
          Offset(nextIsSameItem ? columns[2] : right, y),
        );
      }
    }
    if (pageNumber == pageCount - 1) {
      _drawTechnicalSpecificationsSignatureAt(page, values, y + 25);
    }
  }
  return pageCount;
}
