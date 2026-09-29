part of '../../screens/pdf_editor_screen.dart';

extension _TechnicalSpecsSection on _PdfEditorScreenState {
  // ================================================================
  // SUPPORTED MARKERS
  // ================================================================

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
  // NORMALIZE OLD / SAVED TEXT
  // ================================================================

  String _normalizeTechnicalSpecText(String text) {
    final separator =
        _PdfEditorScreenState.specificationLineSeparator;

    var normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u2029', '\n');

    // Compatibility with old custom separator.
    if (separator.isNotEmpty && separator != '\n') {
      normalized = normalized.replaceAll(
        separator,
        '\n',
      );
    }

    return normalized;
  }

  // ================================================================
  // GET MARKER FROM A LINE
  // ================================================================

  String _getLineMarker(String line) {
    final trimmed = line.trimLeft();

    for (final option in _specificationMarkers) {
      final marker = option.$1;

      if (marker.isEmpty) {
        continue;
      }

      if (trimmed.startsWith(marker)) {
        return marker;
      }
    }

    return '';
  }

  // ================================================================
  // REMOVE MARKER FROM LINE
  // ================================================================

  String _removeLineMarker(String line) {
    return line
        .replaceFirst(_markerRegex, '')
        .trimLeft();
  }

  // ================================================================
  // SET TEXT + CURSOR
  // ================================================================

  void _setTechnicalSpecificationText(
    dynamic entry,
    String text, {
    int? cursorOffset,
  }) {
    var offset = cursorOffset ?? text.length;

    if (offset < 0) {
      offset = 0;
    }

    if (offset > text.length) {
      offset = text.length;
    }

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
  // FIND CURRENT LINE BASED ON CURSOR
  // ================================================================

  int _getCurrentSpecificationLineIndex(
    String text,
    int cursorOffset,
  ) {
    if (text.isEmpty) {
      return 0;
    }

    final safeOffset =
        cursorOffset.clamp(0, text.length);

    final beforeCursor = text.substring(
      0,
      safeOffset,
    );

    return '\n'.allMatches(beforeCursor).length;
  }

  // ================================================================
  // ENTER HANDLER
  //
  // Main behavior:
  //
  // ✓ Line 1
  // press ENTER
  //
  // becomes:
  //
  // ✓ Line 1
  // ✓
  //
  // If previous line uses NONE:
  //
  // Line 1
  // press ENTER
  //
  // becomes:
  //
  // Line 1
  //
  // ================================================================

  void _handleTechnicalSpecificationChanged(
    dynamic entry,
    String newValue,
  ) {
    final oldValue =
        _normalizeTechnicalSpecText(
      entry.specification.text,
    );

    var value =
        _normalizeTechnicalSpecText(newValue);

    // Detect a newly inserted ENTER/newline.
    final oldNewLineCount =
        '\n'.allMatches(oldValue).length;

    final newNewLineCount =
        '\n'.allMatches(value).length;

    if (newNewLineCount > oldNewLineCount) {
      final selection =
          entry.specification.selection;

      var cursor = selection.isValid
          ? selection.baseOffset
          : value.length;

      cursor = cursor.clamp(
        0,
        value.length,
      );

      // Find the newline that was just inserted.
      var newLinePosition = cursor - 1;

      if (newLinePosition >= 0 &&
          newLinePosition < value.length &&
          value[newLinePosition] == '\n') {
        // Cursor is directly after Enter.
      } else {
        // Search backward for nearest newline.
        newLinePosition =
            value.lastIndexOf(
          '\n',
          cursor > 0 ? cursor - 1 : 0,
        );
      }

      if (newLinePosition >= 0) {
        final beforeNewLine = value.substring(
          0,
          newLinePosition,
        );

        final previousLineStart =
            beforeNewLine.lastIndexOf('\n') + 1;

        final previousLine =
            beforeNewLine.substring(
          previousLineStart,
        );

        // Inherit marker from previous line.
        final inheritedMarker =
            _getLineMarker(previousLine);

        if (inheritedMarker.isNotEmpty) {
          // Check that marker wasn't already inserted.
          final afterNewLineStart =
              newLinePosition + 1;

          final afterNewLine =
              value.substring(
            afterNewLineStart,
          );

          final alreadyHasMarker =
              _getLineMarker(afterNewLine)
                  .isNotEmpty;

          if (!alreadyHasMarker) {
            value = value.replaceRange(
              afterNewLineStart,
              afterNewLineStart,
              '$inheritedMarker ',
            );

            cursor +=
                inheritedMarker.length + 1;
          }
        }
      }
    }

    _setTechnicalSpecificationText(
      entry,
      value,
      cursorOffset: entry
              .specification
              .selection
              .isValid
          ? entry.specification.selection.baseOffset
              .clamp(0, value.length)
          : value.length,
    );
  }

  // ================================================================
  // MANUAL + ADD LINE
  //
  // Same behavior as pressing ENTER.
  // ================================================================

  void _addTechnicalSpecificationLineFixed(
    dynamic entry,
  ) {
    final current =
        _normalizeTechnicalSpecText(
      entry.specification.text,
    );

    // Empty first line.
    if (current.isEmpty) {
      return;
    }

    final lines = current.split('\n');

    final previousLine =
        lines.isEmpty ? '' : lines.last;

    final inheritedMarker =
        _getLineMarker(previousLine);

    String nextLine;

    if (inheritedMarker.isEmpty) {
      // NONE
      nextLine = '';
    } else {
      nextLine = '$inheritedMarker ';
    }

    final updated =
        '$current\n$nextLine';

    _setTechnicalSpecificationText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // APPLY MARKER TO CURRENT LINE
  // ================================================================

  void _applyTechnicalSpecificationMarker(
    dynamic entry,
    String marker,
  ) {
    final current =
        _normalizeTechnicalSpecText(
      entry.specification.text,
    );

    var lines = current.split('\n');

    if (lines.isEmpty) {
      lines = [''];
    }

    final selection =
        entry.specification.selection;

    final cursor = selection.isValid
        ? selection.baseOffset
        : current.length;

    var lineIndex =
        _getCurrentSpecificationLineIndex(
      current,
      cursor,
    );

    if (lineIndex >= lines.length) {
      lineIndex = lines.length - 1;
    }

    if (lineIndex < 0) {
      lineIndex = 0;
    }

    final cleanText =
        _removeLineMarker(
      lines[lineIndex],
    );

    if (marker.isEmpty) {
      // NONE
      lines[lineIndex] = cleanText;
    } else {
      // Actual marker.
      lines[lineIndex] = cleanText.isEmpty
          ? '$marker '
          : '$marker $cleanText';
    }

    final updated = lines.join('\n');

    // Put cursor at end of current edited line.
    var newCursor = 0;

    for (var i = 0; i <= lineIndex; i++) {
      newCursor += lines[i].length;

      if (i < lineIndex) {
        newCursor++;
      }
    }

    _setTechnicalSpecificationText(
      entry,
      updated,
      cursorOffset: newCursor,
    );
  }

  // ================================================================
  // REMOVE ONE LOGICAL LINE
  // ================================================================

  void _removeTechnicalSpecificationLineFixed(
    dynamic entry,
    int lineIndex,
  ) {
    final current =
        _normalizeTechnicalSpecText(
      entry.specification.text,
    );

    final lines = current.split('\n');

    if (lineIndex < 0 ||
        lineIndex >= lines.length) {
      return;
    }

    lines.removeAt(lineIndex);

    // Always retain at least one editable line.
    if (lines.isEmpty) {
      lines.add('');
    }

    final updated = lines.join('\n');

    _setTechnicalSpecificationText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // MARKER BUTTON
  // ================================================================

  Widget _technicalSpecMarkerButton({
    required dynamic entry,
    required String marker,
    required String label,
  }) {
    final isCheck = marker == '✓';

    return OutlinedButton(
      onPressed: () {
        _applyTechnicalSpecificationMarker(
          entry,
          marker,
        );
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(38, 32),
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
        ),
        foregroundColor:
            const Color(0xFF0B5D3B),
        visualDensity:
            VisualDensity.compact,
      ),

      // For ✓ use Flutter Icon visually,
      // while stored text remains actual "✓".
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
  // MAIN TECHNICAL SPECIFICATIONS SECTION
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
          index <
              technicalSpecifications.length;
          index++
        )
          Card(
            elevation: 0,

            color:
                const Color(0xFFF7FAF8),

            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xFFDCE5DF),
              ),
            ),

            margin:
                const EdgeInsets.only(
              bottom: 12,
            ),

            child: Padding(
              padding:
                  const EdgeInsets.all(12),

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
                              Icons
                                  .inventory_2_outlined,
                              size: 17,
                              color: Color(
                                0xFF0B5D3B,
                              ),
                            ),

                            const SizedBox(
                              width: 7,
                            ),

                            Text(
                              'Item ${index + 1}',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color: Color(
                                  0xFF234B38,
                                ),
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
                  // SPECIFICATION INPUT
                  //
                  // ENTER automatically inherits active marker.
                  // ==================================================

                  TextField(
                    controller:
                        technicalSpecifications[
                                index]
                            .specification,

                    keyboardType:
                        TextInputType.multiline,

                    textInputAction:
                        TextInputAction.newline,

                    minLines: 4,
                    maxLines: 8,

                    onChanged: (value) {
                      _handleTechnicalSpecificationChanged(
                        technicalSpecifications[
                            index],
                        value,
                      );
                    },

                    decoration:
                        InputDecoration(
                      labelText:
                          'Specification',

                      alignLabelWithHint:
                          true,

                      filled: true,

                      fillColor:
                          Colors.white,

                      contentPadding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),

                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                        borderSide:
                            const BorderSide(
                          color: Color(
                            0xFFDCE5DF,
                          ),
                        ),
                      ),

                      enabledBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                        borderSide:
                            const BorderSide(
                          color: Color(
                            0xFFDCE5DF,
                          ),
                        ),
                      ),

                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                        borderSide:
                            const BorderSide(
                          color: Color(
                            0xFF0B5D3B,
                          ),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // + ADD LINE
                  // ==================================================

                  Align(
                    alignment:
                        Alignment.centerLeft,

                    child: TextButton.icon(
                      onPressed: () {
                        _addTechnicalSpecificationLineFixed(
                          technicalSpecifications[
                              index],
                        );
                      },

                      icon: const Icon(
                        Icons.add,
                        size: 18,
                      ),

                      label:
                          const Text(
                        'Add line',
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

                  // ==================================================
                  // LINE PREVIEW
                  //
                  // IMPORTANT:
                  // blank newly-created lines are also displayed.
                  // ==================================================

                  Builder(
                    builder: (context) {
                      final entry =
                          technicalSpecifications[
                              index];

                      final text =
                          _normalizeTechnicalSpecText(
                        entry.specification.text,
                      );

                      final lines =
                          text.split('\n');

                      // Show preview once user has entered
                      // something OR created a second line.
                      final shouldShow =
                          text.isNotEmpty ||
                              lines.length > 1;

                      if (!shouldShow) {
                        return const SizedBox
                            .shrink();
                      }

                      return Container(
                        margin:
                            const EdgeInsets
                                .only(
                          bottom: 8,
                        ),

                        padding:
                            const EdgeInsets
                                .all(8),

                        decoration:
                            BoxDecoration(
                          color: Colors.white,

                          borderRadius:
                              BorderRadius
                                  .circular(8),

                          border:
                              Border.all(
                            color:
                                const Color(
                              0xFFDCE5DF,
                            ),
                          ),
                        ),

                        child: Column(
                          children: [
                            for (
                              var lineIndex =
                                  0;
                              lineIndex <
                                  lines.length;
                              lineIndex++
                            )
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

                                    onPressed:
                                        () {
                                      _removeTechnicalSpecificationLineFixed(
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
                  // MARKER BUTTONS
                  //
                  // None
                  // •
                  // ○
                  // ■
                  // ➢
                  // ✓
                  // ==================================================

                  Wrap(
                    spacing: 4,
                    runSpacing: 4,

                    children: [
                      for (
                        final option
                            in _specificationMarkers
                      )
                        _technicalSpecMarkerButton(
                          entry:
                              technicalSpecifications[
                                  index],

                          marker:
                              option.$1,

                          label:
                              option.$2,
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

                      const SizedBox(
                        width: 8,
                      ),

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
                  // PARAMETER
                  // ==================================================

                  if (technicalSpecifications[
                          index]
                      .hasParameter) ...[
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,

                      children: [
                        Expanded(
                          child: formField(
                            label:
                                'Parameter',

                            controller:
                                technicalSpecifications[
                                        index]
                                    .parameter,

                            maxLines: 2,
                          ),
                        ),

                        const SizedBox(
                          width: 4,
                        ),

                        IconButton(
                          tooltip:
                              'Remove parameter',

                          visualDensity:
                              VisualDensity
                                  .compact,

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

                      child:
                          TextButton.icon(
                        onPressed: () {
                          _addTechnicalSpecificationParameter(
                            index,
                          );
                        },

                        icon: const Icon(
                          Icons.add,
                          size: 18,
                        ),

                        label:
                            const Text(
                          'Add parameter',
                        ),

                        style:
                            TextButton
                                .styleFrom(
                          foregroundColor:
                              const Color(
                            0xFF0B5D3B,
                          ),

                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal:
                                4,
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
                          const EdgeInsets
                              .symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFFE2F2E8,
                        ),

                        borderRadius:
                            BorderRadius
                                .circular(20),
                      ),

                      child: const Row(
                        mainAxisSize:
                            MainAxisSize.min,

                        children: [
                          Icon(
                            Icons.check,
                            size: 15,
                            color: Color(
                              0xFF0B5D3B,
                            ),
                          ),

                          SizedBox(
                            width: 5,
                          ),

                          Text(
                            'COMPLY',
                            style:
                                TextStyle(
                              color: Color(
                                0xFF0B5D3B,
                              ),
                              fontSize:
                                  11.5,
                              fontWeight:
                                  FontWeight
                                      .bold,
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
        // ADD SPECIFICATION
        // ============================================================

        OutlinedButton.icon(
          onPressed:
              technicalSpecifications
                          .length >=
                      72
                  ? null
                  : _addTechnicalSpecification,

          icon: const Icon(
            Icons.add,
          ),

          label: Text(
            technicalSpecifications
                        .length >=
                    72
                ? 'Maximum of 72 specifications'
                : 'Add Specification',
          ),

          style:
              OutlinedButton.styleFrom(
            foregroundColor:
                const Color(
              0xFF0B5D3B,
            ),

            side:
                const BorderSide(
              color:
                  Color(0xFF0B5D3B),
            ),

            minimumSize:
                const Size
                    .fromHeight(44),

            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}