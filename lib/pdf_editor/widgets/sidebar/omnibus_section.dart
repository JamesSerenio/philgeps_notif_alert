part of '../../screens/pdf_editor_screen.dart';

extension _OmnibusSection on _PdfEditorScreenState {
  Widget omnibusFields() {
    return ExpansionTile(
      initiallyExpanded: true,
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
