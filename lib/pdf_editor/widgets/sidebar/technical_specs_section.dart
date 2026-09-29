part of '../../screens/pdf_editor_screen.dart';

extension _TechnicalSpecsSection on _PdfEditorScreenState {
  // ================================================================
  // MARKERS
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

  // IMPORTANT:
  // Store the currently selected marker PER specification item.
  static final Map<int, String> _activeMarkerByEntry = {};

  // Needed because controller.text is already updated when onChanged fires.
  static final Map<int, String> _previousTextByEntry = {};

  int _entryKey(dynamic entry) => identityHashCode(entry);

  // ================================================================
  // NORMALIZE
  // ================================================================

  String _normalizeSpecText(String text) {
    final separator =
        _PdfEditorScreenState.specificationLineSeparator;

    var result = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u2029', '\n');

    if (separator.isNotEmpty && separator != '\n') {
      result = result.replaceAll(
        separator,
        '\n',
      );
    }

    return result;
  }

  // ================================================================
  // FIND MARKER
  // ================================================================

  String _markerFromLine(String line) {
    final value = line.trimLeft();

    for (final option in _specificationMarkers) {
      final marker = option.$1;

      if (marker.isEmpty) {
        continue;
      }

      if (value.startsWith(marker)) {
        return marker;
      }
    }

    return '';
  }

  String _removeMarker(String line) {
    return line
        .replaceFirst(_markerRegex, '')
        .trimLeft();
  }

  // ================================================================
  // ACTIVE MARKER
  // ================================================================

  String _activeMarker(dynamic entry) {
    final key = _entryKey(entry);

    if (_activeMarkerByEntry.containsKey(key)) {
      return _activeMarkerByEntry[key]!;
    }

    // If old saved data already has a marker,
    // infer the initial active marker from the last non-empty line.
    final text = _normalizeSpecText(
      entry.specification.text,
    );

    final lines = text.split('\n');

    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim().isNotEmpty) {
        final marker = _markerFromLine(lines[i]);

        _activeMarkerByEntry[key] = marker;
        return marker;
      }
    }

    _activeMarkerByEntry[key] = '';
    return '';
  }

  void _setActiveMarker(
    dynamic entry,
    String marker,
  ) {
    _activeMarkerByEntry[_entryKey(entry)] = marker;
  }

  // ================================================================
  // SET CONTROLLER TEXT
  // ================================================================

  void _setSpecText(
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

    // Very important for Enter detection.
    _previousTextByEntry[_entryKey(entry)] = text;

    if (mounted) {
      setState(() {});
    }
  }

  // ================================================================
  // CURRENT LINE
  // ================================================================

  int _lineIndexFromCursor(
    String text,
    int cursor,
  ) {
    if (text.isEmpty) {
      return 0;
    }

    final safeCursor = cursor.clamp(
      0,
      text.length,
    );

    return '\n'
        .allMatches(
          text.substring(0, safeCursor),
        )
        .length;
  }

  // ================================================================
  // ENTER -> AUTO ADD LINE + AUTO ACTIVE MARKER
  // ================================================================

  void _handleSpecificationChanged(
    dynamic entry,
    String rawValue,
  ) {
    final key = _entryKey(entry);

    final newText = _normalizeSpecText(
      rawValue,
    );

    final previousText =
        _previousTextByEntry[key] ??
            _normalizeSpecText(
              entry.specification.text,
            );

    final previousNewlines =
        '\n'.allMatches(previousText).length;

    final newNewlines =
        '\n'.allMatches(newText).length;

    // Save current text for next onChanged.
    _previousTextByEntry[key] = newText;

    // No ENTER was inserted.
    if (newNewlines <= previousNewlines) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final marker = _activeMarker(entry);

    // NONE = normal newline only.
    if (marker.isEmpty) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final selection =
        entry.specification.selection;

    var cursor = selection.isValid
        ? selection.baseOffset
        : newText.length;

    cursor = cursor.clamp(
      0,
      newText.length,
    );

    // Cursor is normally immediately AFTER the newline.
    final currentLineIndex =
        _lineIndexFromCursor(
      newText,
      cursor,
    );

    final lines = newText.split('\n');

    if (currentLineIndex >= lines.length) {
      return;
    }

    // If new line does not already have a marker,
    // automatically put the currently ACTIVE marker.
    if (_markerFromLine(
          lines[currentLineIndex],
        ).isEmpty &&
        lines[currentLineIndex].trim().isEmpty) {
      lines[currentLineIndex] = '$marker ';

      final updated = lines.join('\n');

      // Calculate cursor position at end of marker.
      var newCursor = 0;

      for (
        var i = 0;
        i <= currentLineIndex;
        i++
      ) {
        newCursor += lines[i].length;

        if (i < currentLineIndex) {
          newCursor++;
        }
      }

      _setSpecText(
        entry,
        updated,
        cursorOffset: newCursor,
      );

      return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ================================================================
  // + ADD LINE
  // ================================================================

  void _addLineFixed(dynamic entry) {
    final current = _normalizeSpecText(
      entry.specification.text,
    );

    final marker = _activeMarker(entry);

    String updated;

    if (current.isEmpty) {
      updated = marker.isEmpty
          ? ''
          : '$marker ';
    } else if (current.endsWith('\n')) {
      // Don't create double blank line.
      updated = current;

      if (marker.isNotEmpty) {
        final lines = updated.split('\n');

        if (lines.last.isEmpty) {
          lines[lines.length - 1] =
              '$marker ';

          updated = lines.join('\n');
        }
      }
    } else {
      updated = marker.isEmpty
          ? '$current\n'
          : '$current\n$marker ';
    }

    _setSpecText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // APPLY MARKER BUTTON
  // ================================================================

  void _applyMarkerFixed(
    dynamic entry,
    String marker,
  ) {
    // THIS makes it the active/default marker
    // for all following Enter / Add Line actions.
    _setActiveMarker(
      entry,
      marker,
    );

    final current = _normalizeSpecText(
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

    var lineIndex = _lineIndexFromCursor(
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
        _removeMarker(
      lines[lineIndex],
    );

    if (marker.isEmpty) {
      // NONE
      lines[lineIndex] = cleanText;
    } else {
      lines[lineIndex] =
          cleanText.isEmpty
              ? '$marker '
              : '$marker $cleanText';
    }

    final updated = lines.join('\n');

    var newCursor = 0;

    for (
      var i = 0;
      i <= lineIndex;
      i++
    ) {
      newCursor += lines[i].length;

      if (i < lineIndex) {
        newCursor++;
      }
    }

    _setSpecText(
      entry,
      updated,
      cursorOffset: newCursor,
    );
  }

  // ================================================================
  // DELETE LINE
  // ================================================================

  void _removeLineFixed(
    dynamic entry,
    int lineIndex,
  ) {
    final current =
        _normalizeSpecText(
      entry.specification.text,
    );

    final lines = current.split('\n');

    if (lineIndex < 0 ||
        lineIndex >= lines.length) {
      return;
    }

    lines.removeAt(lineIndex);

    if (lines.isEmpty) {
      lines.add('');
    }

    final updated = lines.join('\n');

    _setSpecText(
      entry,
      updated,
      cursorOffset: updated.length,
    );
  }

  // ================================================================
  // MARKER BUTTON UI
  // ================================================================

  Widget _markerButton({
    required dynamic entry,
    required String marker,
    required String label,
  }) {
    final active =
        _activeMarker(entry);

    final selected =
        active == marker;

    final isCheck =
        marker == '✓';

    return OutlinedButton(
      onPressed: () {
        _applyMarkerFixed(
          entry,
          marker,
        );
      },

      style: OutlinedButton.styleFrom(
        minimumSize:
            const Size(38, 32),

        padding:
            const EdgeInsets.symmetric(
          horizontal: 9,
        ),

        foregroundColor:
            const Color(0xFF0B5D3B),

        backgroundColor: selected
            ? const Color(0xFFE2F2E8)
            : Colors.transparent,

        side: BorderSide(
          color: selected
              ? const Color(
                  0xFF0B5D3B,
                )
              : const Color(
                  0xFF8CA99A,
                ),
        ),

        visualDensity:
            VisualDensity.compact,
      ),

      child: isCheck
          ? const Icon(
              Icons.check,
              size: 18,
              color:
                  Color(0xFF0B5D3B),
            )
          : Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
    );
  }

  // ================================================================
  // MAIN UI
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
          Builder(
            builder: (context) {
              final entry =
                  technicalSpecifications[
                      index];

              // Initialize previous-text tracker
              // BEFORE user starts typing.
              final key =
                  _entryKey(entry);

              _previousTextByEntry
                  .putIfAbsent(
                key,
                () => _normalizeSpecText(
                  entry.specification.text,
                ),
              );

              _activeMarker(entry);

              return Card(
                elevation: 0,

                color:
                    const Color(
                  0xFFF7FAF8,
                ),

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),

                  side:
                      const BorderSide(
                    color:
                        Color(
                      0xFFDCE5DF,
                    ),
                  ),
                ),

                margin:
                    const EdgeInsets.only(
                  bottom: 12,
                ),

                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,

                    children: [
                      // ==============================================
                      // ITEM HEADER
                      // ==============================================

                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons
                                      .inventory_2_outlined,
                                  size: 17,
                                  color:
                                      Color(
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
                                        FontWeight
                                            .bold,

                                    color:
                                        Color(
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

                            onPressed: () {
                              _activeMarkerByEntry
                                  .remove(
                                key,
                              );

                              _previousTextByEntry
                                  .remove(
                                key,
                              );

                              _removeTechnicalSpecification(
                                index,
                              );
                            },

                            icon:
                                const Icon(
                              Icons
                                  .delete_outline,
                            ),
                          ),
                        ],
                      ),

                      // ==============================================
                      // SPECIFICATION
                      // ==============================================

                      TextField(
                        controller:
                            entry
                                .specification,

                        keyboardType:
                            TextInputType
                                .multiline,

                        textInputAction:
                            TextInputAction
                                .newline,

                        minLines: 4,
                        maxLines: 8,

                        onChanged:
                            (value) {
                          _handleSpecificationChanged(
                            entry,
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
                            horizontal:
                                12,
                            vertical: 12,
                          ),

                          enabledBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),

                            borderSide:
                                const BorderSide(
                              color:
                                  Color(
                                0xFFDCE5DF,
                              ),
                            ),
                          ),

                          focusedBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),

                            borderSide:
                                const BorderSide(
                              color:
                                  Color(
                                0xFF0B5D3B,
                              ),
                              width: 1.4,
                            ),
                          ),

                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              10,
                            ),
                          ),
                        ),
                      ),

                      // ==============================================
                      // ADD LINE
                      // ==============================================

                      Align(
                        alignment:
                            Alignment
                                .centerLeft,

                        child:
                            TextButton.icon(
                          onPressed: () {
                            _addLineFixed(
                              entry,
                            );
                          },

                          icon:
                              const Icon(
                            Icons.add,
                            size: 18,
                          ),

                          label:
                              const Text(
                            'Add line',
                          ),

                          style:
                              TextButton
                                  .styleFrom(
                            foregroundColor:
                                const Color(
                              0xFF0B5D3B,
                            ),
                          ),
                        ),
                      ),

                      // ==============================================
                      // LINE LIST
                      // ==============================================

                      Builder(
                        builder:
                            (context) {
                          final text =
                              _normalizeSpecText(
                            entry
                                .specification
                                .text,
                          );

                          final lines =
                              text.split(
                            '\n',
                          );

                          if (text.isEmpty &&
                              lines.length ==
                                  1) {
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
                              color:
                                  Colors.white,

                              borderRadius:
                                  BorderRadius
                                      .circular(
                                8,
                              ),

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
                                        child:
                                            Text(
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
                                          Icons
                                              .close,
                                          size: 18,
                                          color: Colors
                                              .redAccent,
                                        ),

                                        onPressed:
                                            () {
                                          _removeLineFixed(
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

                      // ==============================================
                      // MARKERS
                      // ==============================================

                      Wrap(
                        spacing: 4,
                        runSpacing: 4,

                        children: [
                          for (
                            final option
                                in _specificationMarkers
                          )
                            _markerButton(
                              entry:
                                  entry,

                              marker:
                                  option.$1,

                              label:
                                  option.$2,
                            ),
                        ],
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      // ==============================================
                      // QTY + UNIT
                      // ==============================================

                      Row(
                        children: [
                          Expanded(
                            child:
                                formField(
                              label:
                                  'Qty',

                              controller:
                                  entry
                                      .quantity,
                            ),
                          ),

                          const SizedBox(
                            width: 8,
                          ),

                          Expanded(
                            child:
                                unitField(
                              entry,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 4,
                      ),

                      // ==============================================
                      // PARAMETER
                      // ==============================================

                      if (entry
                          .hasParameter) ...[
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [
                            Expanded(
                              child:
                                  formField(
                                label:
                                    'Parameter',

                                controller:
                                    entry
                                        .parameter,

                                maxLines:
                                    2,
                              ),
                            ),

                            IconButton(
                              onPressed:
                                  () {
                                _removeTechnicalSpecificationParameter(
                                  index,
                                );
                              },

                              icon:
                                  const Icon(
                                Icons.close,
                              ),
                            ),
                          ],
                        ),
                      ] else
                        Align(
                          alignment:
                              Alignment
                                  .centerLeft,

                          child:
                              TextButton
                                  .icon(
                            onPressed:
                                () {
                              _addTechnicalSpecificationParameter(
                                index,
                              );
                            },

                            icon:
                                const Icon(
                              Icons.add,
                              size: 18,
                            ),

                            label:
                                const Text(
                              'Add parameter',
                            ),
                          ),
                        ),

                      // ==============================================
                      // COMPLY
                      // ==============================================

                      Align(
                        alignment:
                            Alignment
                                .centerLeft,

                        child:
                            Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal:
                                10,
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
                                    .circular(
                              20,
                            ),
                          ),

                          child:
                              const Row(
                            mainAxisSize:
                                MainAxisSize
                                    .min,

                            children: [
                              Icon(
                                Icons
                                    .check,
                                size: 15,
                                color:
                                    Color(
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
                                  color:
                                      Color(
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
              );
            },
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

          icon:
              const Icon(
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
                  Color(
                0xFF0B5D3B,
              ),
            ),

            minimumSize:
                const Size
                    .fromHeight(
              44,
            ),

            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius
                      .circular(
                10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}