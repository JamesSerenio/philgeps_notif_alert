import 'dart:ui';

import '../models/pdf_field.dart';

const List<PdfField> bidDocsFields = [
  PdfField(
    key: 'province',
    label: 'Province',
    fontSize: 12,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(250, 92, 220, 22),
      ),
    ],
  ),
  PdfField(
    key: 'municipality',
    label: 'Municipality',
    fontSize: 12,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(250, 112, 220, 22),
      ),
    ],
  ),
  PdfField(
    key: 'projectTitle',
    label: 'Project Title',
    fontSize: 11,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(285, 205, 260, 45),
      ),
      PdfFieldPosition(
        pageIndex: 19,
        bounds: Rect.fromLTWH(275, 42, 390, 45),
      ),
      PdfFieldPosition(
        pageIndex: 20,
        bounds: Rect.fromLTWH(275, 42, 390, 45),
      ),
    ],
  ),
  PdfField(
    key: 'referenceNumber',
    label: 'Reference Number',
    fontSize: 11,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 19,
        bounds: Rect.fromLTWH(275, 88, 180, 22),
      ),
      PdfFieldPosition(
        pageIndex: 20,
        bounds: Rect.fromLTWH(275, 88, 180, 22),
      ),
    ],
  ),
  PdfField(
    key: 'date',
    label: 'Date',
    fontSize: 11,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(285, 250, 180, 22),
      ),
      PdfFieldPosition(
        pageIndex: 19,
        bounds: Rect.fromLTWH(145, 505, 170, 22),
      ),
      PdfFieldPosition(
        pageIndex: 20,
        bounds: Rect.fromLTWH(145, 555, 170, 22),
      ),
    ],
  ),
  PdfField(
    key: 'bidderName',
    label: 'Bidder Name',
    fontSize: 11,
    isBold: true,
    positions: [
      PdfFieldPosition(
        pageIndex: 0,
        bounds: Rect.fromLTWH(285, 275, 260, 22),
      ),
    ],
  ),
];
