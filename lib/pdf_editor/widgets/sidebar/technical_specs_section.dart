part of '../../screens/pdf_editor_screen.dart';

extension _TechnicalSpecsSection on _PdfEditorScreenState {
  static const List<(String, String)> _specificationMarkers = [
    ('', 'None'),
    ('•', '•'),
    ('○', '○'),
    ('■', '■'),
    ('➢', '➢'),
    ('✓', '✓'),
  ];

  static final RegExp _markerRegex =
      RegExp(r'^(?:•|○|■|➢|✓)\s*');

  // ================================================================
  // NORMALIZE OLD SAVED TEXT
  // ================================================================

  String _normalizeSpecText(String text) {
    final separator =
        _PdfEditorScreenState.specificationLineSeparator;

    var result = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u2029', '\n');

    // Backward compatibility if old saved data used
    // a custom logical separator instead of \n.
    if (separator.isNotEmpty && separator != '\n') {
      result = result.replaceAll(separator, '\n');
    }

    return result;
  }

  void _setSpecificationText(
    dynamic entry,
    String text, {
    int? cursorOffset,
  }) {
    final offset =
        (cursorOffset ?? text.length).clamp(0, text.length);

    entry.specification.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: offset,
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ================================================================
  // + ADD LINE
  // ================================================================

  void _addSpecificationLineFixed(dynamic entry) {
    final current =
        _normalizeSpecText(entry.specification.text);

    if (current.isEmpty) {
      return;
    }

    // Do not keep adding blank lines repeatedly.
    if (current.endsWith('\n')) {
      _setSpecificationText(
        entry,
        current,
        cursorOffset: current.length,
      );
      return;
    }

    final updated = '$current\n';

    _setSpecificationText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // DELETE ONE LINE
  // ================================================================

  void _removeSpecificationLineFixed(
    dynamic entry,
    int lineIndex,
  ) {
    final current =
        _normalizeSpecText(entry.specification.text);

    final lines = current.split('\n');

    if (lineIndex < 0 || lineIndex >= lines.length) {
      return;
    }

    lines.removeAt(lineIndex);

    // Remove unnecessary blank lines at the end.
    while (lines.length > 1 && lines.last.isEmpty) {
      lines.removeLast();
    }

    final updated = lines.join('\n');

    _setSpecificationText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // APPLY MARKER TO CURRENT / LAST LINE
  // ================================================================

  void _applySpecificationMarkerFixed(
    dynamic entry,
    String marker,
  ) {
    final current =
        _normalizeSpecText(entry.specification.text);

    var lines = current.split('\n');

    if (lines.isEmpty) {
      lines = [''];
    }

    // Cursor position.
    final selection = entry.specification.selection;
    final cursor =
        selection.isValid ? selection.baseOffset : current.length;

    // Determine which line the cursor is currently on.
    var targetLine = 0;
    var consumed = 0;

    for (var i = 0; i < lines.length; i++) {
      final lineEnd = consumed + lines[i].length;

      if (cursor <= lineEnd || i == lines.length - 1) {
        targetLine = i;
        break;
      }

      consumed = lineEnd + 1;
    }

    final oldLine = lines[targetLine];

    // Remove existing marker first.
    final clean =
        oldLine.replaceFirst(_markerRegex, '').trimLeft();

    if (marker.isEmpty) {
      // NONE
      lines[targetLine] = clean;
    } else {
      // Actual Unicode marker.
      lines[targetLine] =
          clean.isEmpty ? '$marker ' : '$marker $clean';
    }

    final updated = lines.join('\n');

    // Put cursor at end of edited line.
    var newCursor = 0;

    for (var i = 0; i <= targetLine; i++) {
      newCursor += lines[i].length;

      if (i < targetLine) {
        newCursor++;
      }
    }

    _setSpecificationText(
      entry,
      updated,
      cursorOffset: newCursor,
    );
  }

  // ================================================================
  // MARKER BUTTON
  // ================================================================

  Widget _buildSpecMarkerButton({
    required dynamic entry,
    required String value,
    required String label,
  }) {
    final isCheck = value == '✓';

    return OutlinedButton(
      onPressed: () {
        _applySpecificationMarkerFixed(
          entry,
          value,
        );
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(38, 32),
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
        ),
        foregroundColor: const Color(0xFF0B5D3B),
        visualDensity: VisualDensity.compact,
      ),

      // Visually use Flutter's proper check icon.
      child: isCheck
          ? const Icon(
              Icons.check,
              size: 18,
              color: Color(0xFF0B5D3B),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }

  // ================================================================
  // MAIN TECHNICAL SPECIFICATIONS
  // ================================================================

  Widget technicalSpecificationsFields() {
    return _SidebarAccordion(
      leading: const Icon(
        Icons.fact_check_outlined,
        color: Color(0xFF0B5D3B),
      ),

      title: const Text(
        'TECHNICAL SPECIFICATIONS',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),

      subtitle: Text(
        isLoadingTechnicalSpecifications
            ? 'Loading saved values...'
            : isSavingTechnicalSpecifications
                ? 'Saving...'
                : 'Saved automatically',
      ),

      children: [
        for (
          var index = 0;
          index < technicalSpecifications.length;
          index++
        )
          Card(
            elevation: 0,
            color: const Color(0xFFF7FAF8),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xFFDCE5DF),
              ),
            ),

            margin: const EdgeInsets.only(
              bottom: 12,
            ),

            child: Padding(
              padding: const EdgeInsets.all(12),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [
                  // ==================================================
                  // ITEM HEADER
                  // ==================================================

                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 17,
                              color: Color(0xFF0B5D3B),
                            ),

                            const SizedBox(width: 7),

                            Text(
                              'Item ${index + 1}',
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Color(0xFF234B38),
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        tooltip:
                            'Remove specification',
                        visualDensity:
                            VisualDensity.compact,

                        onPressed: () {
                          _removeTechnicalSpecification(
                            index,
                          );
                        },

                        icon: const Icon(
                          Icons.delete_outline,
                        ),
                      ),
                    ],
                  ),

                  // ==================================================
                  // SPECIFICATION TEXTAREA
                  //
                  // IMPORTANT:
                  // Normal ENTER automatically creates a new line.
                  // ==================================================

                  TextField(
                    controller:
                        technicalSpecifications[index]
                            .specification,

                    keyboardType:
                        TextInputType.multiline,

                    textInputAction:
                        TextInputAction.newline,

                    minLines: 4,
                    maxLines: 8,

                    decoration: InputDecoration(
                      labelText: 'Specification',
                      alignLabelWithHint: true,

                      filled: true,
                      fillColor: Colors.white,

                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),

                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),

                        borderSide:
                            const BorderSide(
                          color:
                              Color(0xFFDCE5DF),
                        ),
                      ),

                      enabledBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),

                        borderSide:
                            const BorderSide(
                          color:
                              Color(0xFFDCE5DF),
                        ),
                      ),

                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),

                        borderSide:
                            const BorderSide(
                          color:
                              Color(0xFF0B5D3B),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // + ADD LINE
                  // ==================================================

                  Align(
                    alignment: Alignment.centerLeft,

                    child: TextButton.icon(
                      onPressed: () {
                        _addSpecificationLineFixed(
                          technicalSpecifications[
                              index],
                        );
                      },

                      icon: const Icon(
                        Icons.add,
                        size: 18,
                      ),

                      label: const Text(
                        'Add line',
                      ),

                      style: TextButton.styleFrom(
                        foregroundColor:
                            const Color(0xFF0B5D3B),

                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // LINE LIST
                  // ==================================================

                  Builder(
                    builder: (context) {
                      final entry =
                          technicalSpecifications[
                              index];

                      final text =
                          _normalizeSpecText(
                        entry.specification.text,
                      );

                      final lines =
                          text.split('\n');

                      final hasLines =
                          lines.any(
                        (line) =>
                            line.trim().isNotEmpty,
                      );

                      if (!hasLines) {
                        return const SizedBox.shrink();
                      }

                      return Container(
                        margin:
                            const EdgeInsets.only(
                          bottom: 8,
                        ),

                        padding:
                            const EdgeInsets.all(8),

                        decoration:
                            BoxDecoration(
                          color: Colors.white,

                          borderRadius:
                              BorderRadius.circular(
                            8,
                          ),

                          border: Border.all(
                            color: const Color(
                              0xFFDCE5DF,
                            ),
                          ),
                        ),

                        child: Column(
                          children: [
                            for (
                              var lineIndex = 0;
                              lineIndex <
                                  lines.length;
                              lineIndex++
                            )
                              if (lines[lineIndex]
                                  .trim()
                                  .isNotEmpty)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Line ${lineIndex + 1}: ${lines[lineIndex]}',

                                        style:
                                            const TextStyle(
                                          fontSize:
                                              12,
                                        ),
                                      ),
                                    ),

                                    IconButton(
                                      tooltip:
                                          'Delete this line',

                                      visualDensity:
                                          VisualDensity
                                              .compact,

                                      icon:
                                          const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors
                                            .redAccent,
                                      ),

                                      onPressed: () {
                                        _removeSpecificationLineFixed(
                                          entry,
                                          lineIndex,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                          ],
                        ),
                      );
                    },
                  ),

                  // ==================================================
                  // MARKERS
                  //
                  // None • ○ ■ ➢ ✓
                  // ==================================================

                  Wrap(
                    spacing: 4,
                    runSpacing: 4,

                    children: [
                      for (
                        final option
                            in _specificationMarkers
                      )
                        _buildSpecMarkerButton(
                          entry:
                              technicalSpecifications[
                                  index],

                          value: option.$1,
                          label: option.$2,
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ==================================================
                  // QTY + UNIT
                  // ==================================================

                  Row(
                    children: [
                      Expanded(
                        child: formField(
                          label: 'Qty',

                          controller:
                              technicalSpecifications[
                                      index]
                                  .quantity,
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: unitField(
                          technicalSpecifications[
                              index],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ==================================================
                  // OPTIONAL PARAMETER
                  // ==================================================

                  if (technicalSpecifications[index]
                      .hasParameter) ...[
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        Expanded(
                          child: formField(
                            label: 'Parameter',

                            controller:
                                technicalSpecifications[
                                        index]
                                    .parameter,

                            maxLines: 2,
                          ),
                        ),

                        const SizedBox(width: 4),

                        IconButton(
                          tooltip:
                              'Remove parameter',

                          visualDensity:
                              VisualDensity.compact,

                          onPressed: () {
                            _removeTechnicalSpecificationParameter(
                              index,
                            );
                          },

                          icon: const Icon(
                            Icons.close,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment:
                          Alignment.centerLeft,

                      child: TextButton.icon(
                        onPressed: () {
                          _addTechnicalSpecificationParameter(
                            index,
                          );
                        },

                        icon: const Icon(
                          Icons.add,
                          size: 18,
                        ),

                        label: const Text(
                          'Add parameter',
                        ),

                        style:
                            TextButton.styleFrom(
                          foregroundColor:
                              const Color(
                            0xFF0B5D3B,
                          ),

                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 4),

                  // ==================================================
                  // COMPLY
                  // ==================================================

                  Align(
                    alignment:
                        Alignment.centerLeft,

                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),

                      decoration: BoxDecoration(
                        color:
                            const Color(
                          0xFFE2F2E8,
                        ),

                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),

                      child: const Row(
                        mainAxisSize:
                            MainAxisSize.min,

                        children: [
                          // Real visual check.
                          Icon(
                            Icons.check,
                            size: 15,
                            color: Color(
                              0xFF0B5D3B,
                            ),
                          ),

                          SizedBox(width: 5),

                          Text(
                            'COMPLY',

                            style: TextStyle(
                              color: Color(
                                0xFF0B5D3B,
                              ),
                              fontSize: 11.5,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ============================================================
        // + ADD SPECIFICATION
        // ============================================================

        OutlinedButton.icon(
          onPressed:
              technicalSpecifications.length >=
                      72
                  ? null
                  : _addTechnicalSpecification,

          icon: const Icon(Icons.add),

          label: Text(
            technicalSpecifications.length >=
                    72
                ? 'Maximum of 72 specifications'
                : 'Add Specification',
          ),

          style: OutlinedButton.styleFrom(
            foregroundColor:
                const Color(0xFF0B5D3B),

            side: const BorderSide(
              color: Color(0xFF0B5D3B),
            ),

            minimumSize:
                const Size.fromHeight(44),

            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}