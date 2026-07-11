import 'dart:ui';

class PdfFieldPosition {
  final int pageIndex;
  final Rect bounds;

  const PdfFieldPosition({
    required this.pageIndex,
    required this.bounds,
  });
}

class PdfField {
  final String key;
  final String label;
  final List<PdfFieldPosition> positions;
  final double fontSize;
  final bool isBold;

  const PdfField({
    required this.key,
    required this.label,
    required this.positions,
    this.fontSize = 11,
    this.isBold = false,
  });
}
