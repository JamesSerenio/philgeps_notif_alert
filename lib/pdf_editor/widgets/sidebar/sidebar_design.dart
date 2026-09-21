part of '../../screens/pdf_editor_screen.dart';

const _sidebarGreen = Color(0xFF0B4F3A);
const _sidebarInk = Color(0xFF17212B);
const _sidebarMuted = Color(0xFF667085);
const _sidebarBorder = Color(0xFFE5E7EB);

class _SidebarCard extends StatelessWidget {
  const _SidebarCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _sidebarBorder)),
        child: child,
      );
}

class _SidebarAccordion extends StatefulWidget {
  const _SidebarAccordion(
      {required this.title,
      required this.subtitle,
      required this.leading,
      required this.children,
      this.initiallyExpanded = false});
  final Text title;
  final Text subtitle;
  final Icon leading;
  final List<Widget> children;
  final bool initiallyExpanded;
  @override
  State<_SidebarAccordion> createState() => _SidebarAccordionState();
}

class _SidebarAccordionState extends State<_SidebarAccordion> {
  late bool expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: expanded ? const Color(0xFFADCDBB) : _sidebarBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          onExpansionChanged: (value) => setState(() => expanded = value),
          expansionAnimationStyle:
              const AnimationStyle(duration: Duration(milliseconds: 180)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          childrenPadding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFF2F8F4),
          collapsedBackgroundColor: Colors.white,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: _sidebarGreen,
          collapsedIconColor: _sidebarMuted,
          leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF7F2),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(widget.leading.icon, size: 18, color: _sidebarGreen)),
          title: Text(widget.title.data!,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: _sidebarInk)),
          subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(widget.subtitle.data!,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.4, color: _sidebarMuted))),
          children: [
            Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children))
          ],
        ),
      );
}

ThemeData _sidebarTheme(ThemeData base) {
  final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: const BorderSide(color: _sidebarBorder));
  return base.copyWith(
    hoverColor: const Color(0x0A176B50),
    textTheme: base.textTheme.copyWith(
      bodyLarge:
          const TextStyle(fontSize: 14, height: 1.45, color: _sidebarInk),
      bodyMedium:
          const TextStyle(fontSize: 13, height: 1.4, color: _sidebarInk),
    ),
    listTileTheme:
        const ListTileThemeData(horizontalTitleGap: 10, minLeadingWidth: 30),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w500, color: _sidebarMuted),
      floatingLabelStyle: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w500, color: _sidebarGreen),
      hintStyle: const TextStyle(fontSize: 13, color: _sidebarMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: Color(0xFF2E7D5B), width: 1.4)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
      animationDuration: const Duration(milliseconds: 180),
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
      textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      iconSize: const WidgetStatePropertyAll(16),
      foregroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? _sidebarGreen : _sidebarMuted),
      backgroundColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? const Color(0xFFE0F0E5)
              : Colors.white),
      side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFCCDCD2))),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
    )),
    scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(8),
        thumbColor:
            WidgetStatePropertyAll(_sidebarGreen.withValues(alpha: .22))),
  );
}
