import 'dart:ui';

import '../models/pdf_field.dart';

const List<PdfField> bidDocsFields = [
  // Header: PROVINCE OF ______
  PdfField(
    key: 'province',
    label: 'Province',
    fontSize: 10,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(
          190,
          54,
          220,
          17,
        ),
      ),
    ],
  ),

  // Header: Municipality of ______
  PdfField(
    key: 'municipality',
    label: 'Municipality',
    fontSize: 9,
    isBold: false,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(
          190,
          72,
          220,
          17,
        ),
      ),
    ],
  ),

  // Project value on Page 1
  PdfField(
    key: 'projectTitle',
    label: 'Project Title',
    fontSize: 8,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(
          285,
          150,
          270,
          38,
        ),
      ),
    ],
  ),

  // Date value on Page 1
  PdfField(
    key: 'date',
    label: 'Date',
    fontSize: 9,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(
          285,
          190,
          180,
          18,
        ),
      ),
    ],
  ),

  // Bidder value on Page 1
  PdfField(
    key: 'bidderName',
    label: 'Bidder Name',
    fontSize: 9,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(
          285,
          210,
          260,
          18,
        ),
      ),
    ],
  ),

  // Wala pa ni sa Page 1.
  // I-map nato later sa exact pages nga adunay Reference Number.
  PdfField(
    key: 'referenceNumber',
    label: 'Reference Number',
    fontSize: 9,
    isBold: true,
    positions: [],
  ),

  // Wala pud visible nga slot sa Page 1.
  PdfField(
    key: 'procuringEntity',
    label: 'Procuring Entity',
    fontSize: 9,
    isBold: true,
    positions: [],
  ),
];
