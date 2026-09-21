part of '../../main.dart';

// Dashboard-only tokens: PDF editor styling and document templates are unchanged.
class _DashboardColors {
  static const green = Color(0xFF0B4F3A);
  static const secondary = Color(0xFF176B50);
  static const gold = Color(0xFFE0B72F);
  static const goldText = Color(0xFF856813);
  static const background = Color(0xFFF5F7F6);
  static const ink = Color(0xFF17212B);
  static const muted = Color(0xFF667085);
  static const border = Color(0xFFE4E7EC);
  static const orange = Color(0xFFB86A12);
  static const danger = Color(0xFFB54730);
}

class _DashboardSurface extends StatefulWidget {
  const _DashboardSurface(
      {required this.child,
      this.onTap,
      this.selected,
      this.accent = _DashboardColors.green,
      this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final VoidCallback? onTap;
  final bool? selected;
  final Color accent;
  final EdgeInsetsGeometry padding;
  @override
  State<_DashboardSurface> createState() => _DashboardSurfaceState();
}

class _DashboardSurfaceState extends State<_DashboardSurface> {
  bool hovered = false;
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final raised = hovered || focused;
    final selected = widget.selected == true;
    return Semantics(
      selected: widget.selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(
                  widget.accent.withValues(alpha: .045), Colors.white)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected || focused
                  ? widget.accent
                  : _DashboardColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: raised ? .07 : .025),
                blurRadius: raised ? 16 : 6,
                offset: Offset(0, raised ? 5 : 2))
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (value) => setState(() => hovered = value),
            onFocusChange: (value) => setState(() => focused = value),
            borderRadius: BorderRadius.circular(12),
            hoverColor: widget.accent.withValues(alpha: .025),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.text,
      {this.color = _DashboardColors.green, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5)
          ],
          Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color))),
        ]),
      );
}

class _OpportunityDatum extends StatelessWidget {
  const _OpportunityDatum(this.label, this.value,
      {this.color = _DashboardColors.ink,
      this.emphasized = false,
      this.monospace = false});
  final String label;
  final String value;
  final Color color;
  final bool emphasized;
  final bool monospace;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: _DashboardColors.muted,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        Text(value.isEmpty ? '—' : value,
            style: TextStyle(
                fontSize: emphasized ? 19 : 13,
                height: 1.4,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                color: color,
                fontFamily: monospace ? 'monospace' : null)),
      ]);
}

class _CopyProjectButton extends StatefulWidget {
  const _CopyProjectButton({required this.details});
  final String details;
  @override
  State<_CopyProjectButton> createState() => _CopyProjectButtonState();
}

class _CopyProjectButtonState extends State<_CopyProjectButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.details));
      if (!mounted) return;
      _resetTimer?.cancel();
      setState(() => _copied = true);
      _resetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Project details copied'),
        duration: Duration(seconds: 2),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to copy project details. Please try again.'),
      ));
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _copied ? 'Project details copied' : 'Copy project details',
        onPressed: _copy,
        icon:
            Icon(_copied ? Icons.check_rounded : Icons.copy_outlined, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: _DashboardColors.green,
          backgroundColor: const Color(0xFFF1F7F3),
          side: const BorderSide(color: Color(0xFFCCE0D5)),
          highlightColor: const Color(0xFFD9EADF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}
