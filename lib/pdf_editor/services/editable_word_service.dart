import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class EditableWordService {
  static Uint8List generate(
    Map<String, String> values,
    List<Map<String, dynamic>> specs,
    List<Map<String, dynamic>> prices,
  ) {
    final body = StringBuffer();
    void paragraph(String text, [bool bold = false]) {
      final properties = bold ? '<w:rPr><w:b/></w:rPr>' : '';
      final formattedText = _escape(text)
          .replaceAll("\\n", '</w:t><w:br/><w:t xml:space="preserve">');
      body.write(
          '<w:p><w:r>$properties<w:t xml:space="preserve">$formattedText</w:t></w:r></w:p>');
    }

    void table(List<List<String>> rows) {
      body.write(
          '<w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>');
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        body.write('<w:tr>');
        for (final cell in rows[rowIndex]) {
          final properties = rowIndex == 0 ? '<w:rPr><w:b/></w:rPr>' : '';
          final formattedCell = _escape(cell)
              .replaceAll("\\n", '</w:t><w:br/><w:t xml:space="preserve">');
          body.write(
              '<w:tc><w:p><w:r>$properties<w:t xml:space="preserve">$formattedCell</w:t></w:r></w:p></w:tc>');
        }
        body.write('</w:tr>');
      }
      body.write('</w:tbl>');
    }

    paragraph('BID DOCUMENTS', true);
    for (final pair in <List<String>>[
      ['Project Title', values['projectTitle'] ?? ''],
      ['Province', values['province'] ?? ''],
      ['Municipality', values['municipality'] ?? ''],
      ['Reference Number', values['referenceNumber'] ?? ''],
      ['Procuring Entity', values['procuringEntity'] ?? ''],
      ['Date', values['date'] ?? ''],
      ['Bidder Name', values['bidderName'] ?? ''],
      ['Submitted By', values['submittedBy'] ?? ''],
    ]) {
      paragraph('${pair[0]}: ${pair[1]}');
    }

    paragraph('TECHNICAL SPECIFICATIONS', true);
    final technical = <List<String>>[
      ['Item No.', 'Specification/s', 'Qty', 'Unit', 'Statement of Compliance'],
    ];
    for (var itemIndex = 0; itemIndex < specs.length; itemIndex++) {
      final spec = specs[itemIndex];
      final blocks = (spec['specification'] ?? '').toString().split('\u2029');
      for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
        technical.add([
          blockIndex == 0 ? '${itemIndex + 1}' : '',
          blocks[blockIndex],
          blockIndex == 0 ? (spec['quantity'] ?? '').toString() : '',
          blockIndex == 0 ? (spec['unit'] ?? '').toString() : '',
          'COMPLY',
        ]);
      }
    }
    table(technical);

    paragraph('SCHEDULE OF REQUIREMENTS', true);
    table(<List<String>>[
      ['Item No.', 'Specification/s', 'Delivery Period'],
      for (var i = 0; i < specs.length; i++)
        [
          '${i + 1}',
          (specs[i]['specification'] ?? '').toString(),
          values['deliveredWeeksMonths'] ?? '',
        ],
    ]);

    paragraph('PRICE SCHEDULE FOR GOODS', true);
    final priceSchedule = <List<String>>[
      [
        'Item No.',
        'Specification/s',
        'Qty',
        'Unit',
        'Total Price per Unit',
        'Total Price Delivered'
      ],
    ];
    for (var i = 0; i < specs.length; i++) {
      final price = i < prices.length ? prices[i] : <String, dynamic>{};
      priceSchedule.add([
        '${i + 1}',
        (specs[i]['specification'] ?? '').toString(),
        (specs[i]['quantity'] ?? '').toString(),
        (specs[i]['unit'] ?? '').toString(),
        (price['totalPricePerUnit'] ?? '').toString(),
        (price['manualTotal'] ?? price['totalDeliveredPrice'] ?? '').toString(),
      ]);
    }
    table(priceSchedule);

    paragraph('SUMMARY OF BID PRICES', true);
    table(<List<String>>[
      ['Item No.', 'Description/s', 'Total Price Delivered'],
      for (var i = 0; i < specs.length; i++)
        [
          '${i + 1}',
          (specs[i]['specification'] ?? '').toString(),
          i < prices.length
              ? (prices[i]['manualTotal'] ??
                      prices[i]['totalDeliveredPrice'] ??
                      '')
                  .toString()
              : '',
        ],
    ]);

    paragraph('BID SECURING DECLARATION', true);
    paragraph(
        'I/We, ${values['bidderName'] ?? ''}, submit this Bid Securing Declaration for ${values['projectTitle'] ?? ''}.');
    paragraph('OMNIBUS SWORN STATEMENT', true);
    paragraph(
        'I/We, ${values['submittedBy'] ?? ''}, the authorized representative of ${values['bidderName'] ?? ''}, make this sworn statement in connection with ${values['projectTitle'] ?? ''}.');
    paragraph('STATEMENT OF SINGLE LARGEST COMPLETED CONTRACTS (SLCC)', true);
    paragraph('Bidder: ${values['bidderName'] ?? ''}');
    paragraph('AFTER-SALES SERVICE CERTIFICATE', true);
    paragraph(
        '${values['bidderName'] ?? ''} certifies that after-sales service will be provided for ${values['projectTitle'] ?? ''}.');
    paragraph('CERTIFICATE OF PRODUCT WARRANTY', true);
    paragraph(
        '${values['bidderName'] ?? ''} certifies the product warranty for ${values['projectTitle'] ?? ''}.');

    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body.toString()}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr></w:body></w:document>';
    final archive = Archive();
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
    add('word/document.xml', document);
    add('word/_rels/document.xml.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>');
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
