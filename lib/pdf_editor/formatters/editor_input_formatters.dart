part of '../screens/pdf_editor_screen.dart';

class _SpecificationListFormatter extends TextInputFormatter {
  const _SpecificationListFormatter();

  static final RegExp markerPattern = RegExp(
    r'^\s*(?:✓|•|○|■|➢|-|\[x\])\s*',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.selection.isValid ||
        newValue.text.length != oldValue.text.length + 1) {
      return newValue;
    }
    final insertedAt = newValue.selection.baseOffset - 1;
    if (insertedAt < 0 || newValue.text[insertedAt] != '\n') return newValue;

    final previousLineStart =
        newValue.text.lastIndexOf('\n', insertedAt - 1) + 1;
    final previousLine = newValue.text.substring(previousLineStart, insertedAt);
    final match = markerPattern.firstMatch(previousLine);
    if (match == null) return newValue;

    final markerText = match.group(0)!.trim();
    final previousContent = previousLine.substring(match.end).trim();
    if (previousContent.isEmpty) {
      final cleaned = newValue.text.replaceRange(
        previousLineStart,
        insertedAt,
        '',
      );
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: previousLineStart + 1),
      );
    }

    final continuation = '$markerText ';
    final continuedText = newValue.text.replaceRange(
      insertedAt + 1,
      insertedAt + 1,
      continuation,
    );
    return TextEditingValue(
      text: continuedText,
      selection: TextSelection.collapsed(
        offset: insertedAt + 1 + continuation.length,
      ),
    );
  }
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const _ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw =
        newValue.text.replaceAll('\u20b1', '').replaceAll(',', '').trim();
    if (raw.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(raw)) return oldValue;

    final parts = raw.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length == 2 ? '$grouped.${parts[1]}' : grouped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
