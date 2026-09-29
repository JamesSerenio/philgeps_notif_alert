part of '../pdf_service.dart';

Future<void> _insertInitaoDocumentPages(
  PdfDocument document,
  Map<String, String> values,
) async {
  final data = await rootBundle.load(
    'assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf',
  );

  final template = PdfDocument(
    inputBytes: data.buffer.asUint8List(),
  );

  PdfDocument? snapshot;

  try {
    if (template.pages.count != 6) {
      throw StateError(
        'The INITAO document template must contain six pages.',
      );
    }

    // ================================================================
    // SAVE CURRENT COMPLETE DOCUMENT
    // ================================================================

    snapshot = PdfDocument(
      inputBytes: await document.save(),
    );

    final extractor =
        PdfTextExtractor(snapshot);

    final text = <String>[
      for (var i = 0; i < snapshot.pages.count; i++)
        extractor
            .extractText(
              startPageIndex: i,
              endPageIndex: i,
            )
            .replaceAll('\u0000', '')
            .replaceAll(RegExp(r'\s+'), '')
            .toUpperCase(),
    ];

    // ================================================================
    // SECTION ANCHOR HELPER
    // ================================================================

    int anchor(String title) {
      final index = text.indexWhere(
        (value) =>
            !value.contains(
              'CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS',
            ) &&
            !value.contains(
              'TABLEOFCONTENTS',
            ) &&
            value.contains(title),
      );

      if (index < 0) {
        throw StateError(
          'Cannot organize INITAO PDF: '
          'missing section $title.',
        );
      }

      return index;
    }

    // ================================================================
    // FIND ALL NORMAL SECTIONS
    // ================================================================

    final ongoing =
        anchor('STATEMENTOFALLITSONGOING');

    final philgeps =
        anchor('CERTIFICATEOFPHILGEPSREGISTRATION');

    final nfcc =
        anchor('NETFINANCIALCONTRACTINGCAPACITY');

    final specifications =
        anchor('TECHNICALSPECIFICATIONS');

    final security =
        anchor('BIDSECURINGDECLARATION');

    final schedule =
        anchor('SCHEDULEOFREQUIREMENTS');

    final omnibus =
        anchor('OMNIBUSSWORNSTATEMENT');

    final afterSales =
        anchor('SALESSERVICECERTIFICATE');

    final bidForm =
        anchor('BIDFORM');

    // ================================================================
    // FIND EXACT AFS START + END
    // ================================================================
    //
    // These were inserted by _replaceAfsSection().
    //
    // This means we no longer guess:
    //
    //     afs = nfcc - numberOfAfsPages
    //
    // Instead we know exactly where AFS begins and ends.
    // ================================================================

    final afsStart = text.indexWhere(
      (value) =>
          value.contains(
        'PHILGEPS_AFS_START',
      ),
    );

    final afsEnd = text.indexWhere(
      (value) =>
          value.contains(
        'PHILGEPS_AFS_END',
      ),
    );

    if (afsStart < 0) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'AFS start marker not found.',
      );
    }

    if (afsEnd < 0) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'AFS end marker not found.',
      );
    }

    if (afsEnd < afsStart) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'AFS end occurs before AFS start.',
      );
    }

    if (afsEnd >= nfcc) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'AFS must finish before NFCC. '
        'AFS=$afsStart-$afsEnd, '
        'NFCC=$nfcc.',
      );
    }

    // ================================================================
    // RANGE HELPER
    // ================================================================

    List<int> range(
      int start,
      int end,
    ) {
      return [
        for (var i = start; i < end; i++)
          if (!text[i].contains(
                'CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS',
              ) &&
              !text[i].contains(
                'TABLEOFCONTENTS',
              ))
            i,
      ];
    }

    // ================================================================
    // VALIDATE STRUCTURE
    // ================================================================

    if (!(ongoing < philgeps &&
        philgeps <= afsStart &&
        afsStart <= afsEnd &&
        afsEnd < nfcc &&
        nfcc < specifications &&
        specifications < security &&
        security < schedule &&
        schedule < omnibus &&
        omnibus < afterSales &&
        afterSales < bidForm &&
        bidForm < snapshot.pages.count)) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'unexpected document section order. '
        'ongoing=$ongoing, '
        'philgeps=$philgeps, '
        'afs=$afsStart-$afsEnd, '
        'nfcc=$nfcc, '
        'specifications=$specifications, '
        'security=$security, '
        'schedule=$schedule, '
        'omnibus=$omnibus, '
        'afterSales=$afterSales, '
        'bidForm=$bidForm, '
        'pages=${snapshot.pages.count}.',
      );
    }

    // ================================================================
    // LEGAL DOCUMENTS
    // ================================================================

    final legalDocuments = <int>[
      ...range(
        philgeps,
        afsStart,
      ),
      ...range(
        0,
        ongoing,
      ),
    ];

    // ================================================================
    // TECHNICAL DOCUMENTS
    // ================================================================

    final technicalDocuments = <int>[
      // Ongoing contracts, SLCC and acceptance
      ...range(
        ongoing,
        philgeps,
      ),

      // Bid Security
      ...range(
        security,
        schedule,
      ),

      // Technical Specifications
      ...range(
        specifications,
        security,
      ),

      // Schedule Requirements / Delivery / Manpower
      ...range(
        schedule,
        omnibus,
      ),

      // After-sales and Warranty
      ...range(
        afterSales,
        bidForm,
      ),

      // Omnibus and jurat
      ...range(
        omnibus,
        afterSales,
      ),
    ];

    // ================================================================
    // FINANCIAL DOCUMENTS
    // ================================================================
    //
    // THIS IS THE IMPORTANT FIX.
    //
    // Include EVERY page between:
    //
    // PHILGEPS_AFS_START
    // ...
    // PHILGEPS_AFS_END
    //
    // Then include NFCC until Technical Specifications.
    //
    // If AFS = 15 pages -> all 15 stay together.
    // If AFS = 90 pages -> all 90 stay together.
    // ================================================================

    final financialDocuments = <int>[
      ...range(
        afsStart,
        afsEnd + 1,
      ),

      ...range(
        afsEnd + 1,
        specifications,
      ),
    ];

    // ================================================================
    // FINANCIAL COMPONENT DOCUMENTS
    // ================================================================

    final financialComponentDocuments =
        range(
      bidForm,
      snapshot.pages.count,
    );

    // ================================================================
    // VERIFY THAT EVERY ORIGINAL PAGE IS USED EXACTLY ONCE
    // ================================================================

    final ordered = <int>[
      ...legalDocuments,
      ...technicalDocuments,
      ...financialDocuments,
      ...financialComponentDocuments,
    ];

    final expected = range(
      0,
      snapshot.pages.count,
    );

    final orderedSet =
        ordered.toSet();

    final expectedSet =
        expected.toSet();

    if (ordered.length != expected.length ||
        orderedSet.length != expected.length ||
        !orderedSet.containsAll(expectedSet)) {
      throw StateError(
        'Cannot organize INITAO PDF: '
        'duplicate or missing pages. '
        'ordered=${ordered.length}, '
        'unique=${orderedSet.length}, '
        'expected=${expected.length}.',
      );
    }

    // ================================================================
    // AUTOFILL INITAO CONTENTS PAGE
    // ================================================================

    _drawInitaoContentsFields(
      template.pages[0],
      values,
    );

    // ================================================================
    // FINAL PAGE ORDER
    // ================================================================

    final finalPages = <PdfPage>[
      // Existing INITAO intro
      template.pages[4],
      template.pages[5],

      // Main checklist
      template.pages[0],

      // Legal header
      template.pages[1],

      for (final i in legalDocuments)
        snapshot.pages[i],

      // Technical header
      template.pages[2],

      for (final i in technicalDocuments)
        snapshot.pages[i],

      // Financial header
      template.pages[3],

      // COMPLETE AFS + NFCC
      for (final i in financialDocuments)
        snapshot.pages[i],

      // Bid Form / Price / Summary / other final docs
      for (final i in financialComponentDocuments)
        snapshot.pages[i],
    ];

    // ================================================================
    // REMOVE OLD DOCUMENT
    // ================================================================

    for (var i = document.pages.count - 1;
        i >= 0;
        i--) {
      document.pages.removeAt(i);
    }

    // ================================================================
    // BUILD FINAL DOCUMENT
    // ================================================================

    for (final source in finalPages) {
      final target = document.pages.insert(
        document.pages.count,
        source.size,
        PdfMargins()..all = 0,
      );

      target.graphics.drawPdfTemplate(
        source.createTemplate(),
        Offset.zero,
        source.size,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 1),
      );
    }
  } finally {
    snapshot?.dispose();
    template.dispose();
  }
}

void _drawInitaoContentsFields(
  PdfPage page,
  Map<String, String> values,
) {
  final graphics = page.graphics;

  final white = PdfSolidBrush(
    PdfColor(
      255,
      255,
      255,
    ),
  );

  final black = PdfSolidBrush(
    PdfColor(
      0,
      0,
      0,
    ),
  );

  final regular = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
  );

  final bold = PdfStandardFont(
    PdfFontFamily.timesRoman,
    12,
    style: PdfFontStyle.bold,
  );

  // Only cover variable header areas.
  graphics.drawRectangle(
    brush: white,
    bounds: const Rect.fromLTWH(
      150,
      51,
      295,
      29,
    ),
  );

  graphics.drawRectangle(
    brush: white,
    bounds: const Rect.fromLTWH(
      178,
      107,
      385,
      58,
    ),
  );

  final center = PdfStringFormat(
    alignment: PdfTextAlignment.center,
  );

  graphics.drawString(
    'Province Of ${(values['province'] ?? '').trim()}',
    regular,
    brush: black,
    bounds: const Rect.fromLTWH(
      150,
      52.6,
      295,
      14,
    ),
    format: center,
  );

  graphics.drawString(
    'Municipality of ${(values['municipality'] ?? '').trim()}',
    regular,
    brush: black,
    bounds: const Rect.fromLTWH(
      150,
      66.1,
      295,
      14,
    ),
    format: center,
  );

  graphics.drawString(
    (values['projectTitle'] ?? '').trim(),
    bold,
    brush: black,
    bounds: const Rect.fromLTWH(
      180.2,
      108.9,
      379,
      27.7,
    ),
    format: PdfStringFormat(
      wordWrap: PdfWordWrapType.word,
    ),
  );

  graphics.drawString(
    (values['date'] ?? '').trim(),
    bold,
    brush: black,
    bounds: const Rect.fromLTWH(
      180.2,
      136.6,
      379,
      14,
    ),
  );

  graphics.drawString(
    (values['bidderName'] ?? '').trim(),
    bold,
    brush: black,
    bounds: const Rect.fromLTWH(
      180.2,
      150.9,
      379,
      14,
    ),
  );
}