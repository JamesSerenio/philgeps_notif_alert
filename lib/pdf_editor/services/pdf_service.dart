import '../models/item_pricing.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'page_mapper.dart';
import 'initao_omnibus_numbering.dart';

part 'pdf/pdf_page_service.dart';
part 'pdf/pdf_document_template_service.dart';
part 'pdf/pdf_financial_service.dart';
part 'pdf/pdf_slcc_service.dart';
part 'pdf/pdf_text_service.dart';
part 'pdf/pdf_field_service.dart';
part 'pdf/pdf_bid_security_service.dart';
part 'pdf/pdf_bid_security_legacy_service.dart';
part 'pdf/pdf_technical_specs_service.dart';
part 'pdf/pdf_price_schedule_service.dart';
part 'pdf/pdf_omnibus_service.dart';
part 'pdf/pdf_certificate_service.dart';
part 'pdf/pdf_jurat_service.dart';
part 'pdf/pdf_bid_form_service.dart';
part 'pdf/pdf_secretary_certificate_service.dart';
part 'pdf/pdf_schedule_requirements_service.dart';
part 'pdf/pdf_bid_price_summary_service.dart';

/// Structural location of the inserted AFS block.
///
/// IMPORTANT:
/// [startIndex] is valid only while no page before the AFS block is
/// inserted, removed, or moved.
///
/// Therefore the production generation flow captures this placement only
/// after all earlier structural changes have completed.
class _AfsPlacement {
  const _AfsPlacement({
    required this.startIndex,
    required this.pageCount,
  });

  final int startIndex;
  final int pageCount;

  int get endExclusive => startIndex + pageCount;

  bool isValidFor(PdfDocument document) =>
      startIndex >= 0 &&
      pageCount > 0 &&
      endExclusive <= document.pages.count;
}

/// Public entry point; feature parts retain the original drawing operations.
class PdfService {
  const PdfService._();

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
    Future<void> yieldToBrowser() =>
        Future<void>.delayed(const Duration(milliseconds: 1));

    await _ensurePdfUnicodeMarkerFont();

    values = values.map(
      (key, value) => MapEntry(
        key,
        _pdfSafeText(value),
      ),
    );

    // Explicit global modes take precedence over stale per-section
    // preferences. Calls without a global mode retain the existing
    // section-level API.
    if (values.containsKey('documentTemplateMode')) {
      final initao = values['documentTemplateMode'] == 'initao';

      values['omnibusTemplateType'] =
          initao ? 'initao_lgu' : 'old';

      values['bidSecuringDeclarationTemplate'] = initao
          ? 'initao_lgu'
          : values['bidSecuringDeclarationTemplate'] == 'without_table'
              ? 'without_table'
              : 'old';
    }

    final ByteData templateData = await rootBundle.load(
      'assets/pdf/bidocs_template.pdf',
    );

    final Uint8List templateBytes =
        templateData.buffer.asUint8List();

    final PdfDocument document = PdfDocument(
      inputBytes: templateBytes,
    );

    // PDF work on Flutter Web shares the UI thread.
    await yieldToBrowser();

    // ============================================================
    // PAGE 1
    // ============================================================

    if (document.pages.count > 0) {
      _drawPageOne(
        document.pages[0],
        values,
      );
    }

    // ============================================================
    // ONGOING CONTRACTS
    // ============================================================

    // Original Page 20.
    if (document.pages.count > 19) {
      _drawContractStatementPage(
        document.pages[19],
        values,
        signatureTop: 428,
        signatureClearTop: 410,
        businessAddressClearTop: 210,
        businessAddressTop: 212,
      );
    }

    // Original Page 21.
    if (document.pages.count > 20) {
      _drawContractStatementPage(
        document.pages[20],
        values,
        signatureTop: 485,
        signatureClearTop: 478,
        businessAddressClearTop: 174,
        businessAddressTop: 176,
      );

      _drawSlccPrivateRow(
        document.pages[20],
        values,
      );
    }

    // ============================================================
    // TECHNICAL SPECIFICATIONS
    // ============================================================

    // Rebuild editable Technical Specifications sheets on blank pages.
    //
    // Painting white over bundled rows can leave old PDF stream content
    // visible in external PDF readers.
    if (document.pages.count > 46) {
      _drawTechnicalSpecificationsHeader(
        document.pages[46],
        values,
      );
    }

    var technicalSpecificationPageCount = 3;

    if (document.pages.count > 48) {
      technicalSpecificationPageCount =
          _drawTechnicalSpecifications(
        document,
        values,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // PRICE SCHEDULE
    // ============================================================

    final priceScheduleStartPage =
        _findPriceScheduleStartPage(document);

    var priceSchedulePageCount = 1;

    if (priceScheduleStartPage >= 0) {
      priceSchedulePageCount = _drawPriceSchedule(
        document,
        values,
        priceScheduleStartPage,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // SUMMARY OF BID PRICES
    // ============================================================

    final bidPriceSummaryStartPage =
        _findBidPriceSummaryStartPage(document);

    var bidPriceSummaryPageCount = 1;

    if (bidPriceSummaryStartPage >= 0) {
      bidPriceSummaryPageCount = _drawBidPriceSummary(
        document,
        values,
        bidPriceSummaryStartPage,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // SCHEDULE OF REQUIREMENTS
    // ============================================================

    final scheduleRequirementsStartPage =
        _findScheduleRequirementsStartPage(document);

    var scheduleRequirementsPageCount = 1;

    if (scheduleRequirementsStartPage >= 0) {
      scheduleRequirementsPageCount =
          _drawScheduleRequirements(
        document,
        values,
        scheduleRequirementsStartPage,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // OTHER MAPPED FIELDS
    // ============================================================

    final mappedFields =
        PageMapper.mapValuesToPages(values);

    for (final pageEntry in mappedFields.entries) {
      final int pageIndex = pageEntry.key;

      // Page 1 is already handled above.
      if (pageIndex == 0) {
        continue;
      }

      if (pageIndex < 0 ||
          pageIndex >= document.pages.count) {
        continue;
      }

      final PdfPage page =
          document.pages[pageIndex];

      for (final mappedField in pageEntry.value) {
        final Rect bounds =
            mappedField.position.bounds;

        page.graphics.drawRectangle(
          brush: PdfSolidBrush(
            PdfColor(255, 255, 255),
          ),
          bounds: Rect.fromLTWH(
            bounds.left - 3,
            bounds.top - 2,
            bounds.width + 6,
            bounds.height + 4,
          ),
        );

        final PdfFont font = PdfStandardFont(
          PdfFontFamily.timesRoman,
          mappedField.field.fontSize,
          style: mappedField.field.isBold
              ? PdfFontStyle.bold
              : PdfFontStyle.regular,
        );

        page.graphics.drawString(
          mappedField.value,
          font,
          bounds: bounds,
          format: PdfStringFormat(
            alignment:
                PdfTextAlignment.left,
            lineAlignment:
                PdfVerticalAlignment.top,
            wordWrap:
                PdfWordWrapType.word,
          ),
        );
      }

      // Large bid documents map many pages.
      await yieldToBrowser();
    }

    await yieldToBrowser();

    // ============================================================
    // REMOVE UNUSED CONTINUATION TEMPLATE PAGES
    // ============================================================

    if (scheduleRequirementsStartPage >= 0) {
      for (var pageIndex =
              (scheduleRequirementsStartPage + 2)
                  .clamp(
                    0,
                    document.pages.count - 1,
                  )
                  .toInt();
          pageIndex >=
              scheduleRequirementsStartPage +
                  scheduleRequirementsPageCount;
          pageIndex--) {
        document.pages.removeAt(
          pageIndex,
        );
      }
    }

    if (bidPriceSummaryStartPage >= 0) {
      for (var pageIndex =
              (bidPriceSummaryStartPage + 2)
                  .clamp(
                    0,
                    document.pages.count - 1,
                  )
                  .toInt();
          pageIndex >=
              bidPriceSummaryStartPage +
                  bidPriceSummaryPageCount;
          pageIndex--) {
        document.pages.removeAt(
          pageIndex,
        );
      }
    }

    if (priceScheduleStartPage >= 0) {
      for (var pageIndex =
              (priceScheduleStartPage + 7)
                  .clamp(
                    0,
                    document.pages.count - 1,
                  )
                  .toInt();
          pageIndex >=
              priceScheduleStartPage +
                  priceSchedulePageCount;
          pageIndex--) {
        document.pages.removeAt(
          pageIndex,
        );
      }

      // Keep the two Bid Securing Declaration sheets immediately
      // before Price Schedule.
    }

    if (technicalSpecificationPageCount < 3 &&
        document.pages.count > 48) {
      document.pages.removeAt(48);
    }

    if (technicalSpecificationPageCount < 2 &&
        document.pages.count > 47) {
      document.pages.removeAt(47);
    }

    await yieldToBrowser();

    // ============================================================
    // BID SECURING DECLARATION
    // ============================================================

    final useDeclarationWithTable =
        switch (
          values['bidSecuringDeclarationTemplate']
        ) {
      'old' => true,
      'without_table' || 'initao_lgu' =>
        false,
      _ =>
        values['bidSecuringDeclarationWithTable'] !=
            'false',
    };

    if (useDeclarationWithTable) {
      // Locate actual form by text because optional Technical Spec
      // pages can move its final page index.
      _drawBidSecuringDeclarationDetails(
        document,
        values,
      );
    } else {
      await _replaceBidSecuringDeclarationWithoutTable(
        document,
        values,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // REMOVE SAMPLE OFFICIAL RECEIPT
    // ============================================================

    // This remains an existing template-specific operation.
    if (document.pages.count > 45) {
      document.pages.removeAt(45);
    }

    await yieldToBrowser();

    // ============================================================
    // OMNIBUS
    // ============================================================

    final omnibusPageIndex =
        _findOmnibusSwornStatementPage(
      document,
    );

    if (omnibusPageIndex >= 0) {
      _drawOmnibusSwornStatementIdentity(
        document,
        values,
        pageIndex: omnibusPageIndex,
      );

      _drawOmnibusSwornStatementLastPage(
        document,
        values,
        pageIndex: omnibusPageIndex + 1,
      );

      if (values['omnibusTemplateType'] ==
          'initao_lgu') {
        drawInitaoOmnibusNumbering(
          document,
          omnibusPageIndex,
        );
      }
    }

    await yieldToBrowser();

    // ============================================================
    // OTHER DYNAMIC SECTIONS
    // ============================================================

    _drawManpowerSignature(
      document,
      values,
    );

    await yieldToBrowser();

    _drawAfterSalesServiceCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    _drawProductWarrantyCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    _drawJuratPlaceholders(
      document,
      values,
    );

    await yieldToBrowser();

    _drawBidForm(
      document,
      values,
    );

    await yieldToBrowser();

    _drawSecretaryCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    // ============================================================
    // FINAL STRUCTURAL PHASE
    //
    // IMPORTANT:
    // Everything that can change page indexes BEFORE AFS must finish
    // BEFORE we capture the AFS placement.
    // ============================================================

    // Replace the legacy SLCC section.
    await _replaceSlccSection(
      document,
      values,
    );

    await yieldToBrowser();

    // If the user selected NO SLCC, remove it now.
    //
    // This MUST happen before AFS placement is captured because removing
    // pages before AFS changes all following page indexes.
    if (values['slccTemplateType']
            ?.trim()
            .toLowerCase() ==
        'none') {
      _removeSlccSection(
        document,
      );

      await yieldToBrowser();
    }

    // ============================================================
    // NFCC
    // ============================================================

    // Resolve and replace NFCC AFTER optional SLCC changes.
    //
    // NFCC is located structurally using Technical Specifications,
    // not using a fixed final page number.
    await _replaceNfccPage(
      document,
      values,
    );

    await yieldToBrowser();

    // ============================================================
    // BUSINESS PERMIT / TAX CLEARANCE
    // ============================================================

    // This operation may change page positions.
    // Therefore it MUST happen before AFS placement is captured.
    await _moveBusinessPermitBeforeTaxClearance(
      document,
    );

    await yieldToBrowser();

    // ============================================================
    // PHILGEPS CERTIFICATE
    // ============================================================

    // This replacement can also affect the page structure before AFS.
    await _replacePhilgepsCertificateSection(
      document,
    );

    await yieldToBrowser();

    // ============================================================
    // AFS
    // ============================================================

    // CRITICAL:
    //
    // AFS replacement is deliberately LAST among all operations that
    // can move pages before the AFS block.
    //
    // The placement returned here therefore points at the REAL final
    // AFS location.
    //
    // For the current source:
    //
    // pageCount = 15
    //
    // and those 15 pages must remain one atomic block.
    final afsPlacement =
        _validateAfsPlacement(
      document,
      await _replaceAfsSection(
        document,
      ),
    );

    await yieldToBrowser();

    // ============================================================
    // INITAO FINAL REORDERING
    // ============================================================

    if (values['documentTemplateMode'] ==
        'initao') {
      // No page-changing operation may occur between AFS placement
      // capture and this INITAO reorder.
      await _insertInitaoDocumentPages(
        document,
        values,
        afsPlacement,
      );

      await yieldToBrowser();
    } else {
      // OLD mode does not perform the INITAO rearrangement.
      //
      // Revalidate the structural placement immediately before save
      // so a broken block cannot silently reach the final PDF.
      _validateAfsPlacement(
        document,
        afsPlacement,
      );
    }

    // ============================================================
    // FINAL SAVE
    // ============================================================

    // Keep Syncfusion's normal incremental output.
    final List<int> outputBytes =
        await document.save();

    document.dispose();

    return Uint8List.fromList(
      outputBytes,
    );
  }
}

/// Validate the structural AFS placement.
///
/// NOTE:
/// This validates the numeric structural range. INITAO performs additional
/// exact ordering checks inside _insertInitaoDocumentPages().
_AfsPlacement _validateAfsPlacement(
  PdfDocument document,
  _AfsPlacement? placement,
) {
  if (placement == null ||
      !placement.isValidFor(document)) {
    throw StateError(
      'AFS replacement failed or returned invalid placement.',
    );
  }

  final afsStart =
      placement.startIndex;

  final afsEndExclusive =
      placement.endExclusive;

  final firstAfsPageMissing =
      afsStart >= document.pages.count;

  final secondAfsPageMissing =
      afsStart + 1 >= document.pages.count;

  if (placement.pageCount != 15 ||
      firstAfsPageMissing ||
      secondAfsPageMissing ||
      afsEndExclusive >
          document.pages.count) {
    throw StateError(
      'AFS integrity failure: '
      'expected=15 '
      'actual=${placement.pageCount} '
      'missing first AFS page=$firstAfsPageMissing '
      'missing second AFS page=$secondAfsPageMissing '
      'start=$afsStart '
      'end=$afsEndExclusive '
      'documentPages=${document.pages.count}.',
    );
  }

  return placement;
}