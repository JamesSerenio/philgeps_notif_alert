part of '../../screens/pdf_editor_screen.dart';

extension _SlccSection on _PdfEditorScreenState {
  Widget slccFields() {
    return _SidebarAccordion(
      initiallyExpanded: false,
      leading: const Icon(Icons.assignment_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'SLCC',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingSlcc
            ? 'Loading saved values...'
            : isSavingSlcc
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'none', label: Text('None')),
              ButtonSegment(value: 'cctv', label: Text('CCTV')),
              ButtonSegment(
                value: 'streetlight',
                label: Text('Street Lights'),
              ),
            ],
            selected: {selectedSlccTemplate},
            onSelectionChanged: (selection) {
              _updateState(() => selectedSlccTemplate = selection.first);
              _invalidateGeneratedPdf();
              _scheduleSlccSave();
            },
          ),
        ),
      ],
    );
  }
}
