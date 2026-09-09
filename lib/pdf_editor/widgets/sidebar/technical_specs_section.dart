part of '../../screens/pdf_editor_screen.dart';

extension _TechnicalSpecsSection on _PdfEditorScreenState {
  Widget technicalSpecificationsFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(Icons.fact_check_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'TECHNICAL SPECIFICATIONS',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingTechnicalSpecifications
            ? 'Loading saved values...'
            : isSavingTechnicalSpecifications
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        for (var index = 0; index < technicalSpecifications.length; index++)
          Card(
            elevation: 0,
            color: const Color(0xFFF7FAF8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFDCE5DF)),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF234B38),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove specification',
                        onPressed: () => _removeTechnicalSpecification(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  formField(
                    label: 'Specification',
                    controller: technicalSpecifications[index].specification,
                    maxLines: 5,
                    inputFormatters: const <TextInputFormatter>[
                      _SpecificationListFormatter(),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final entry = technicalSpecifications[index];
                        final current = entry.specification.text;
                        entry.specification.text = current.trim().isEmpty
                            ? '✓ '
                            : '${current.trimRight()}$_PdfEditorScreenState.specificationLineSeparator✓ ';
                        entry.specification.selection = TextSelection.collapsed(
                          offset: entry.specification.text.length,
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add line'),
                    ),
                  ),
                  if (technicalSpecifications[index]
                      .specification
                      .text
                      .trim()
                      .isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDCE5DF)),
                      ),
                      child: Column(
                        children: [
                          for (final line in technicalSpecifications[index]
                              .specification
                              .text
                              .replaceAll(
                                '\u2029',
                                _PdfEditorScreenState
                                    .specificationLineSeparator,
                              )
                              .split(_PdfEditorScreenState
                                  .specificationLineSeparator)
                              .asMap()
                              .entries)
                            if (line.value.trim().isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Line ${line.key + 1}: ${line.value}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete this line',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () => _removeSpecificationLine(
                                      technicalSpecifications[index],
                                      line.key,
                                    ),
                                  ),
                                ],
                              ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final option in const <(String, String)>[
                        ('', 'None'),
                        ('•', '•'),
                        ('○', '○'),
                        ('■', '■'),
                        ('➢', '➢'),
                        ('✓', '✓'),
                      ])
                        OutlinedButton(
                          onPressed: () => _applySpecificationMarker(
                            technicalSpecifications[index],
                            option.$1,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(38, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            foregroundColor: const Color(0xFF0B5D3B),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(option.$2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: formField(
                          label: 'Qty',
                          controller: technicalSpecifications[index].quantity,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: unitField(technicalSpecifications[index]),
                      ),
                    ],
                  ),
                  if (technicalSpecifications[index].hasParameter) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: formField(
                            label: 'Parameter',
                            controller:
                                technicalSpecifications[index].parameter,
                            maxLines: 2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Remove parameter',
                          onPressed: () =>
                              _removeTechnicalSpecificationParameter(index),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            _addTechnicalSpecificationParameter(index),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add parameter'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0B5D3B),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F2E8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '✓  COMPLY',
                        style: TextStyle(
                          color: Color(0xFF0B5D3B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: technicalSpecifications.length >= 72
              ? null
              : _addTechnicalSpecification,
          icon: const Icon(Icons.add),
          label: Text(
            technicalSpecifications.length >= 72
                ? 'Maximum of 72 specifications'
                : 'Add Specification',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0B5D3B),
            side: const BorderSide(color: Color(0xFF0B5D3B)),
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // Sidebar rebuilds display these results without recalculating prices.
}
