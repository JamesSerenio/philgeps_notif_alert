part of '../../screens/pdf_editor_screen.dart';

extension _OmnibusSection on _PdfEditorScreenState {
  Widget omnibusFields() {
    return _SidebarAccordion(
      initiallyExpanded: true,
      leading: const Icon(Icons.description_outlined, color: Color(0xFF0B5D3B)),
      title: const Text('OMNIBUS SWORN STATEMENT',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(omnibusSaveError ??
          (isLoadingOmnibus
              ? 'Loading saved values...'
              : isSavingOmnibus
                  ? 'Saving...'
                  : 'Saved automatically')),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              if (isInitaoDocument)
                const ButtonSegment(
                    value: 'initao_lgu', label: Text('INITAO LGU'))
              else
                const ButtonSegment(value: 'old', label: Text('OLD')),
            ],
            selected: {effectiveOmnibusTemplate},
            onSelectionChanged: _selectOmnibus,
          ),
        ),
      ],
    );
  }
}
