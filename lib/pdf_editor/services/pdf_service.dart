import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'page_mapper.dart';

class PdfService {
  const PdfService._();

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
    final ByteData templateData = await rootBundle.load(
      'assets/pdf/bidocs_template.pdf',
    );

    final Uint8List templateBytes = templateData.buffer.asUint8List();

    final PdfDocument document = PdfDocument(
      inputBytes: templateBytes,
    );

    // Clean replacement for Page 1.
    if (document.pages.count > 0) {
      _drawPageOne(
        document.pages[0],
        values,
      );
    }

    // Other mapped pages, excluding Page 1.
    final mappedFields = PageMapper.mapValuesToPages(values);

    for (final pageEntry in mappedFields.entries) {
      final int pageIndex = pageEntry.key;

      // Page 1 is already handled above.
      if (pageIndex == 0) continue;

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        continue;
      }

      final PdfPage page = document.pages[pageIndex];

      for (final mappedField in pageEntry.value) {
        final Rect bounds = mappedField.position.bounds;

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
            alignment: PdfTextAlignment.left,
            lineAlignment: PdfVerticalAlignment.top,
            wordWrap: PdfWordWrapType.word,
          ),
        );
      }
    }

    final List<int> outputBytes = await document.save();
    document.dispose();

    return Uint8List.fromList(outputBytes);
  }

  static void _drawPageOne(
    PdfPage page,
    Map<String, String> values,
  ) {
    final String province = (values['province'] ?? '').trim().toUpperCase();

    final String municipality = (values['municipality'] ?? '').trim();

    final String projectTitle = (values['projectTitle'] ?? '').trim();

    final String date = (values['date'] ?? '').trim();

    final String bidderName = (values['bidderName'] ?? '').trim();

    final PdfGraphics graphics = page.graphics;

    final PdfBrush whiteBrush = PdfSolidBrush(
      PdfColor(255, 255, 255),
    );

    final PdfBrush blackBrush = PdfSolidBrush(
      PdfColor(0, 0, 0),
    );

    /*
     * Cover the complete original header.
     * Includes:
     * Republic of the Philippines
     * Province
     * Municipality
     */
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(
        100,
        25,
        395,
        70,
      ),
    );

    /*
     * Cover the complete original project information.
     * Includes old Project, Date and Bidder values.
     */
    graphics.drawRectangle(
      brush: whiteBrush,
      bounds: const Rect.fromLTWH(
        175,
        125,
        390,
        115,
      ),
    );

    final PdfFont republicFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
    );

    final PdfFont headerBoldFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      10,
      style: PdfFontStyle.bold,
    );

    final PdfFont municipalityFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
    );

    final PdfFont labelFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
    );

    final PdfFont valueFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      9,
      style: PdfFontStyle.bold,
    );

    final PdfStringFormat centerFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    );

    /*
     * Redraw the header.
     */
    graphics.drawString(
      'Republic of the Philippines',
      republicFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        30,
        395,
        15,
      ),
      format: centerFormat,
    );

    graphics.drawString(
      'PROVINCE OF $province',
      headerBoldFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        45,
        395,
        17,
      ),
      format: centerFormat,
    );

    graphics.drawString(
      'Municipality of $municipality',
      municipalityFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        100,
        62,
        395,
        16,
      ),
      format: centerFormat,
    );

    /*
     * Redraw labels.
     */
    graphics.drawString(
      'Project',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        65,
        140,
        85,
        18,
      ),
    );

    graphics.drawString(
      ':',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        155,
        140,
        15,
        18,
      ),
    );

    graphics.drawString(
      'Date',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        65,
        192,
        85,
        18,
      ),
    );

    graphics.drawString(
      ':',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        155,
        192,
        15,
        18,
      ),
    );

    graphics.drawString(
      'Name of Bidder',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        65,
        212,
        90,
        18,
      ),
    );

    graphics.drawString(
      ':',
      labelFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        155,
        212,
        15,
        18,
      ),
    );

    /*
     * Redraw values.
     */
    graphics.drawString(
      projectTitle,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        175,
        137,
        360,
        50,
      ),
      format: PdfStringFormat(
        alignment: PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.top,
        wordWrap: PdfWordWrapType.word,
      ),
    );

    graphics.drawString(
      date,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        175,
        192,
        220,
        18,
      ),
    );

    graphics.drawString(
      bidderName,
      valueFont,
      brush: blackBrush,
      bounds: const Rect.fromLTWH(
        175,
        212,
        330,
        18,
      ),
    );
  }
}
