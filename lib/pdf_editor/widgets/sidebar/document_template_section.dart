part of '../../screens/pdf_editor_screen.dart';

extension _DocumentTemplateSection on _PdfEditorScreenState {
  String get _documentTemplatePreferenceKey =>
      'bid_document_template_${widget.referenceNumber.trim()}';

  Future<void> _loadDocumentTemplate() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_documentTemplatePreferenceKey);
      if (!mounted || documentTemplateRevision != 0) return;
      _updateState(() =>
          selectedDocumentTemplate = saved == 'initao' ? 'initao' : 'old');
    } catch (error) {
      if (mounted && documentTemplateRevision == 0) {
        _updateState(
            () => documentTemplateSaveError = 'Could not load saved option');
      }
    } finally {
      if (mounted) _updateState(() => isLoadingDocumentTemplate = false);
    }
  }

  void _selectDocumentTemplate(Set<String> selection) {
    final mode = selection.first;
    final revision = ++documentTemplateRevision;
    _updateState(() {
      selectedDocumentTemplate = mode;
      isSavingDocumentTemplate = true;
      documentTemplateSaveError = null;
    });
    _invalidateGeneratedPdf();
    // Keep taps responsive, serialize writes, and let only the newest save
    // update the status. A late initial load must not overwrite a user choice.
    documentTemplateSave = documentTemplateSave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(
            _documentTemplatePreferenceKey, mode)) {
          throw StateError('Document template preference was not saved');
        }
      } catch (error) {
        if (mounted && revision == documentTemplateRevision) {
          _updateState(
              () => documentTemplateSaveError = 'Could not save option');
        }
      } finally {
        if (mounted && revision == documentTemplateRevision) {
          _updateState(() => isSavingDocumentTemplate = false);
        }
      }
    });
  }

  Widget documentTemplateFields() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E1DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DOCUMENT TEMPLATE',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(documentTemplateSaveError ??
              (isLoadingDocumentTemplate
                  ? 'Loading saved values...'
                  : isSavingDocumentTemplate
                      ? 'Saving...'
                      : 'Saved automatically')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'old', label: Text('OLD')),
                ButtonSegment(
                    value: 'initao',
                    label: Text('INITAO LGU TEMPLATE',
                        textAlign: TextAlign.center)),
              ],
              selected: {selectedDocumentTemplate},
              onSelectionChanged: _selectDocumentTemplate,
            ),
          ),
        ],
      ),
    );
  }
}
