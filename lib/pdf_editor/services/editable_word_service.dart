import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class EditableWordService {
  static const _portraitSection = '<w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="720" w:right="850" w:bottom="720" w:left="850" '
      'w:header="360" w:footer="360" w:gutter="0"/>';

  static const _landscapeSection =
      '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
      '<w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" '
      'w:header="360" w:footer="360" w:gutter="0"/>';

  static Uint8List generate(
    Map<String, String> values,
    List<Map<String, dynamic>> specs,
    List<Map<String, dynamic>> prices,
  ) {
    final body = StringBuffer();

    String run(String text, {bool bold = false, int size = 20}) {
      final content = _escape(text).replaceAll(
        '\n',
        '</w:t><w:br/><w:t xml:space="preserve">',
      );
      return '<w:r><w:rPr>'
              '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
              '<w:sz w:val="' +
          size.toString() +
          '"/>' +
          (bold ? '<w:b/>' : '') +
          '</w:rPr><w:t xml:space="preserve">' +
          content +
          '</w:t></w:r>';
    }

    void paragraph(
      String text, {
      bool bold = false,
      int size = 20,
      String alignment = 'left',
      int before = 0,
      int after = 90,
    }) {
      body.write('<w:p><w:pPr><w:jc w:val="' +
          alignment +
          '"/>'
              '<w:spacing w:before="' +
          before.toString() +
          '" w:after="' +
          after.toString() +
          '" w:line="230" w:lineRule="auto"/>'
              '</w:pPr>' +
          run(text, bold: bold, size: size) +
          '</w:p>');
    }

    void pageBreak() {
      body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }

    void sectionBreak(bool landscape) {
      body.write('<w:p><w:pPr><w:sectPr>' +
          (landscape ? _landscapeSection : _portraitSection) +
          '</w:sectPr></w:pPr></w:p>');
    }

    String cell(
      String value,
      int width, {
      bool bold = false,
      bool centered = false,
      bool middle = false,
      int size = 18,
    }) {
      return '<w:tc><w:tcPr><w:tcW w:w="' +
          width.toString() +
          '" w:type="dxa"/><w:vAlign w:val="' +
          (middle ? 'center' : 'top') +
          '"/><w:tcMar><w:top w:w="55" w:type="dxa"/>'
              '<w:left w:w="80" w:type="dxa"/><w:bottom w:w="55" w:type="dxa"/>'
              '<w:right w:w="80" w:type="dxa"/></w:tcMar></w:tcPr>'
              '<w:p><w:pPr><w:jc w:val="' +
          (centered ? 'center' : 'left') +
          '"/><w:spacing w:before="0" w:after="0" w:line="210" '
              'w:lineRule="auto"/></w:pPr>' +
          run(value, bold: bold, size: size) +
          '</w:p></w:tc>';
    }

    void table(
      List<List<String>> rows,
      List<int> widths, {
      Set<int> centered = const <int>{},
      Set<int> emphasis = const <int>{},
      int size = 18,
    }) {
      final total = widths.fold<int>(0, (sum, width) => sum + width);
      body.write('<w:tbl><w:tblPr><w:tblW w:w="' +
          total.toString() +
          '" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
              '<w:tblCellMar><w:top w:w="55" w:type="dxa"/>'
              '<w:left w:w="80" w:type="dxa"/><w:bottom w:w="55" w:type="dxa"/>'
              '<w:right w:w="80" w:type="dxa"/></w:tblCellMar>'
              '<w:tblBorders><w:top w:val="single" w:sz="4"/>'
              '<w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>'
              '<w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/>'
              '<w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>'
              '<w:tblGrid>');
      for (final width in widths) {
        body.write('<w:gridCol w:w="' + width.toString() + '"/>');
      }
      body.write('</w:tblGrid>');
      for (var row = 0; row < rows.length; row++) {
        final header = row == 0;
        body.write('<w:tr><w:trPr>' +
            (header ? '<w:tblHeader/>' : '') +
            '<w:cantSplit/></w:trPr>');
        for (var column = 0; column < rows[row].length; column++) {
          body.write(cell(
            rows[row][column],
            widths[column],
            bold: header || emphasis.contains(column),
            centered: centered.contains(column),
            middle: centered.contains(column),
            size: size,
          ));
        }
        body.write('</w:tr>');
      }
      body.write('</w:tbl>');
    }

    void details() {
      paragraph('Republic of the Philippines', alignment: 'center', size: 20);
      paragraph(
        values['procuringEntity'] ?? '',
        bold: true,
        alignment: 'center',
        size: 20,
        after: 180,
      );
      table(<List<String>>[
        <String>['Project Title', values['projectTitle'] ?? ''],
        <String>['Reference Number', values['referenceNumber'] ?? ''],
        <String>['Date', values['date'] ?? ''],
        <String>['Name of Bidder', values['bidderName'] ?? ''],
      ], <int>[
        1900,
        8000
      ], emphasis: <int>{
        0
      });
      paragraph('', after: 80);
    }

    void signature() {
      paragraph('', after: 150);
      table(<List<String>>[
        <String>['Submitted by', values['submittedBy'] ?? ''],
        <String>['Designation', 'Authorized Representative'],
        <String>['Name of Firm', values['bidderName'] ?? ''],
        <String>['Date', values['date'] ?? ''],
      ], <int>[
        1900,
        8000
      ], emphasis: <int>{
        0
      });
    }

    paragraph('TECHNICAL SPECIFICATIONS',
        bold: true, size: 28, alignment: 'center', after: 220);
    details();
    paragraph('Statement of Compliance', bold: true, size: 20, after: 60);
    paragraph(
      'The bidder shall indicate compliance with each specification by writing COMPLY in the corresponding column.',
      size: 18,
      after: 160,
    );
    final technical = <List<String>>[
      <String>[
        'Item No.',
        'Specification/s',
        'Qty',
        'Unit',
        'Statement of Compliance'
      ],
    ];
    for (var item = 0; item < specs.length; item++) {
      final spec = specs[item];
      final blocks = (spec['specification'] ?? '').toString().split('\u2029');
      for (var block = 0; block < blocks.length; block++) {
        technical.add(<String>[
          block == 0 ? (item + 1).toString() : '',
          blocks[block],
          block == 0 ? (spec['quantity'] ?? '').toString() : '',
          block == 0 ? (spec['unit'] ?? '').toString() : '',
          'COMPLY',
        ]);
      }
    }
    table(technical, <int>[650, 4850, 700, 800, 1900],
        centered: <int>{0, 2, 3, 4}, emphasis: <int>{4});
    signature();

    pageBreak();
    paragraph('SCHEDULE OF REQUIREMENTS',
        bold: true, size: 28, alignment: 'center', after: 220);
    details();
    table(<List<String>>[
      <String>[
        'Item No.',
        'Specification/s',
        'Qty',
        'Unit',
        'Delivered Weeks/Months'
      ],
      for (var item = 0; item < specs.length; item++)
        <String>[
          (item + 1).toString(),
          (specs[item]['specification'] ?? '').toString(),
          (specs[item]['quantity'] ?? '').toString(),
          (specs[item]['unit'] ?? '').toString(),
          values['deliveredWeeksMonths'] ?? '',
        ],
    ], <int>[
      650,
      4450,
      700,
      800,
      2300
    ], centered: <int>{
      0,
      2,
      3,
      4
    });
    signature();

    sectionBreak(true);
    paragraph('PRICE SCHEDULE FOR GOODS',
        bold: true, size: 26, alignment: 'center', after: 220);
    details();
    final schedule = <List<String>>[
      <String>[
        'Item No.',
        'Specification/s',
        'Country of Origin',
        'Qty',
        'Unit',
        'Unit Price/Item',
        'Transportation & Insurance',
        'Sales & Other Taxes',
        'Incidental Services',
        'Total Price per Unit',
        'Total Price Delivered'
      ],
    ];
    for (var item = 0; item < specs.length; item++) {
      final price = item < prices.length ? prices[item] : <String, dynamic>{};
      schedule.add(<String>[
        (item + 1).toString(),
        (specs[item]['specification'] ?? '').toString(),
        (price['countryOfOrigin'] ?? '').toString(),
        (specs[item]['quantity'] ?? '').toString(),
        (specs[item]['unit'] ?? '').toString(),
        (price['unitPrice'] ?? '').toString(),
        (price['transportationCost'] ?? '').toString(),
        (price['salesTax'] ?? '').toString(),
        (price['incidentalServices'] ?? '').toString(),
        (price['totalPricePerUnit'] ?? '').toString(),
        (price['manualTotal'] ?? price['totalDeliveredPrice'] ?? '').toString(),
      ]);
    }
    table(schedule,
        <int>[450, 3000, 950, 450, 500, 900, 1150, 900, 900, 950, 1100],
        centered: <int>{0, 2, 3, 4, 5, 6, 7, 8, 9, 10}, size: 16);
    signature();

    pageBreak();
    paragraph('SUMMARY OF BID PRICES',
        bold: true, size: 26, alignment: 'center', after: 220);
    details();
    table(<List<String>>[
      <String>[
        'Item No.',
        'Description/s',
        'Qty',
        'Unit',
        'Total Price Delivered'
      ],
      for (var item = 0; item < specs.length; item++)
        <String>[
          (item + 1).toString(),
          (specs[item]['specification'] ?? '').toString(),
          (specs[item]['quantity'] ?? '').toString(),
          (specs[item]['unit'] ?? '').toString(),
          item < prices.length
              ? (prices[item]['manualTotal'] ??
                      prices[item]['totalDeliveredPrice'] ??
                      '')
                  .toString()
              : '',
        ],
    ], <int>[
      700,
      6000,
      800,
      900,
      2500
    ], centered: <int>{
      0,
      2,
      3,
      4
    });
    signature();

    sectionBreak(false);
    void form(String title, String text) {
      pageBreak();
      paragraph(title, bold: true, size: 28, alignment: 'center', after: 220);
      details();
      paragraph(text, size: 20, after: 180);
      signature();
    }

    form(
      'BID SECURING DECLARATION',
      'I/We, ' +
          (values['bidderName'] ?? '') +
          ', submit this Bid Securing Declaration for ' +
          (values['projectTitle'] ?? '') +
          '.',
    );
    form(
      'OMNIBUS SWORN STATEMENT',
      'I/We, ' +
          (values['submittedBy'] ?? '') +
          ', the authorized representative of ' +
          (values['bidderName'] ?? '') +
          ', make this sworn statement in connection with ' +
          (values['projectTitle'] ?? '') +
          '.',
    );
    form('STATEMENT OF SINGLE LARGEST COMPLETED CONTRACTS (SLCC)',
        'Bidder: ' + (values['bidderName'] ?? ''));
    form(
        'AFTER-SALES SERVICE CERTIFICATE',
        (values['bidderName'] ?? '') +
            ' certifies that after-sales service will be provided for ' +
            (values['projectTitle'] ?? '') +
            '.');
    form(
        'CERTIFICATE OF PRODUCT WARRANTY',
        (values['bidderName'] ?? '') +
            ' certifies the product warranty for ' +
            (values['projectTitle'] ?? '') +
            '.');

    final xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            '<w:body>' +
        body.toString() +
        '<w:sectPr>' +
        _portraitSection +
        '</w:sectPr></w:body></w:document>';
    return _package(xml);
  }

  static Uint8List _package(String documentXml) {
    final archive = Archive();
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
    add('word/document.xml', documentXml);
    add('word/_rels/document.xml.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>');
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
