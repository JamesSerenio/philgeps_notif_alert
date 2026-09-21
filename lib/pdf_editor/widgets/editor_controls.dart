part of '../screens/pdf_editor_screen.dart';

class _CompactPanelButton extends StatelessWidget {
  const _CompactPanelButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF0B5D3B);
    return Material(
      color: selected ? const Color(0xFF0B5D3B) : const Color(0xFFEAF3EE),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfGenerationOverlay extends StatefulWidget {
  const _PdfGenerationOverlay();

  @override
  State<_PdfGenerationOverlay> createState() => _PdfGenerationOverlayState();
}

class _PdfGenerationOverlayState extends State<_PdfGenerationOverlay> {
  static const messages = <String>[
    'Saving your latest information...',
    'Preparing technical specifications...',
    'Calculating the price schedule...',
    'Building and arranging PDF pages...',
    'Finalizing your bid document...',
  ];

  Timer? messageTimer;
  int messageIndex = 0;

  @override
  void initState() {
    super.initState();
    messageTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) {
        setState(() => messageIndex = (messageIndex + 1) % messages.length);
      }
    });
  }

  @override
  void dispose() {
    messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.38),
      child: Center(
        child: Container(
          width: 360,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 82,
                      height: 82,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Color(0xFF0B5D3B),
                        backgroundColor: Color(0xFFE1EEE7),
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F4EC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 31,
                        color: Color(0xFF0B5D3B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Generating Bid Document',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF173D2C),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 22,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    messages[messageIndex],
                    key: ValueKey(messageIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF66736C),
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  color: Color(0xFF0B5D3B),
                  backgroundColor: Color(0xFFE2ECE6),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please keep this window open.',
                style: TextStyle(
                  color: Color(0xFF87918B),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmittedByMenuIcon extends StatelessWidget {
  const _SubmittedByMenuIcon();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_PdfEditorScreenState>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
      tooltip: 'Select submitted by',
      onSelected: (name) {
        state?.submittedByController.text = name;
        state?.submittedByController.selection = TextSelection.collapsed(
          offset: name.length,
        );
      },
      itemBuilder: (context) {
        return _PdfEditorScreenState.submittedByNames
            .map(
              (name) => PopupMenuItem<String>(
                value: name,
                child: Text(name),
              ),
            )
            .toList();
      },
    );
  }
}
