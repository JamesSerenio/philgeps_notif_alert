part of '../pdf_editor_screen.dart';

extension _SpecificationEditing on _PdfEditorScreenState {
  void _addTechnicalSpecification({
    String specification = '',
    String quantity = '1',
    String unit = 'unit',
    String parameter = '',
    bool rebuild = true,
  }) {
    if (technicalSpecifications.length >= 72) return;
    final entry = _TechnicalSpecificationEntry(
      specification: specification,
      quantity: quantity,
      unit: unit,
      parameter: parameter,
    );
    for (final controller in entry.controllers) {
      controller.addListener(_scheduleTechnicalSpecificationsSave);
    }
    technicalSpecifications.add(entry);
    final priceEntry = _PriceScheduleEntry();
    priceEntry.totalPricePerUnit.addListener(_schedulePriceScheduleSave);
    priceEntry.deduction.addListener(_schedulePriceScheduleSave);
    priceScheduleEntries.add(priceEntry);
    if (rebuild && mounted) _updateState(() {});
  }

  void _removeTechnicalSpecification(int index) {
    final entry = technicalSpecifications.removeAt(index);
    for (final controller in entry.controllers) {
      controller.removeListener(_scheduleTechnicalSpecificationsSave);
    }
    entry.dispose();
    final priceEntry = priceScheduleEntries.removeAt(index);
    priceEntry.totalPricePerUnit.removeListener(_schedulePriceScheduleSave);
    priceEntry.deduction.removeListener(_schedulePriceScheduleSave);
    priceEntry.dispose();
    _updateState(() {});
    _scheduleTechnicalSpecificationsSave();
  }

  void _addTechnicalSpecificationParameter(int index) {
    _updateState(() => technicalSpecifications[index].hasParameter = true);
  }

  void _removeTechnicalSpecificationParameter(int index) {
    final entry = technicalSpecifications[index];
    entry.parameter.clear();
    _updateState(() => entry.hasParameter = false);
    _scheduleTechnicalSpecificationsSave();
  }

  void _applySpecificationMarker(
    _TechnicalSpecificationEntry entry,
    String marker,
  ) {
    final controller = entry.specification;
    final text = controller.text;
    final caret = controller.selection.isValid
        ? controller.selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final lineStart = text.lastIndexOf('\n', caret == 0 ? 0 : caret - 1) + 1;
    final lineEndIndex = text.indexOf('\n', caret);
    final lineEnd = lineEndIndex < 0 ? text.length : lineEndIndex;
    final line = text.substring(lineStart, lineEnd);
    final markerMatch =
        _SpecificationListFormatter.markerPattern.firstMatch(line);
    final content =
        markerMatch == null ? line : line.substring(markerMatch.end);
    final replacement = marker.isEmpty ? content : '$marker $content';
    controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection.collapsed(
        offset: lineStart + replacement.length,
      ),
    );
  }

  void _removeSpecificationLine(
    _TechnicalSpecificationEntry entry,
    int lineIndex,
  ) {
    final lines = entry.specification.text
        .replaceAll('\u2029', _PdfEditorScreenState.specificationLineSeparator)
        .split(_PdfEditorScreenState.specificationLineSeparator);
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    lines.removeAt(lineIndex);
    entry.specification.text =
        lines.join(_PdfEditorScreenState.specificationLineSeparator);
    entry.specification.selection = TextSelection.collapsed(
      offset: entry.specification.text.length,
    );
  }
}
