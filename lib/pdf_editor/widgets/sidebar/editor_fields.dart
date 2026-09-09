part of '../../screens/pdf_editor_screen.dart';

extension _EditorFields on _PdfEditorScreenState {
  Widget formField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    bool readOnly = false,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        readOnly: readOnly,
        inputFormatters: inputFormatters,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: readOnly ? const Color(0xFFF1F5F2) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF0B5D3B),
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget sectionHeading(IconData icon, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE4F1E9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: const Color(0xFF0B5D3B)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF153D2C),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .35,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7770),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget unitField(_TechnicalSpecificationEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<String>(
        textEditingController: entry.unit,
        focusNode: entry.unitFocusNode,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          final matches = unitSuggestions.where(
            (unit) => query.isEmpty || unit.toLowerCase().contains(query),
          );
          final sorted = matches.toList()
            ..sort((first, second) {
              final firstStarts = first.toLowerCase().startsWith(query);
              final secondStarts = second.toLowerCase().startsWith(query);
              if (firstStarts != secondStarts) return firstStarts ? -1 : 1;
              return first.compareTo(second);
            });
          return sorted;
        },
        onSelected: (unit) {
          entry.unit.text = unit;
          entry.unit.selection = TextSelection.collapsed(offset: unit.length);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Unit',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: PopupMenuButton<String>(
                tooltip: 'Select unit',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (unit) {
                  controller.text = unit;
                  controller.selection = TextSelection.collapsed(
                    offset: unit.length,
                  );
                },
                itemBuilder: (context) => [
                  for (final unit in unitSuggestions)
                    PopupMenuItem(value: unit, child: Text(unit)),
                ],
              ),
            ),
            onSubmitted: (_) => onSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240,
                  maxWidth: 260,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final unit = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(unit),
                      onTap: () => onSelected(unit),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget submittedByField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<String>(
        textEditingController: submittedByController,
        focusNode: submittedByFocusNode,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return _PdfEditorScreenState.submittedByNames;

          return _PdfEditorScreenState.submittedByNames.where(
            (name) => name.toLowerCase().contains(query),
          );
        },
        onSelected: (name) {
          submittedByController.text = name;
        },
        fieldViewBuilder: (
          context,
          controller,
          focusNode,
          onFieldSubmitted,
        ) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Submitted by',
              hintText: 'Type or select a name',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1DB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF0B5D3B),
                  width: 1.6,
                ),
              ),
              suffixIcon: const _SubmittedByMenuIcon(),
            ),
            onSubmitted: (_) => onFieldSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 328,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final name = options.elementAt(index);
                    return ListTile(
                      title: Text(name),
                      onTap: () => onSelected(name),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
