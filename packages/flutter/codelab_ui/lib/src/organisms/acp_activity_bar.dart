import 'package:fluent_ui/fluent_ui.dart';

typedef AcpActivityBarSectionHeaderBuilder =
    Widget Function(BuildContext context, bool expanded);
typedef AcpActivityBarSectionBodyBuilder =
    Widget Function(BuildContext context);

/// One collapsible section of an [AcpActivityBar] — e.g. the agent's plan.
///
/// Only [headerBuilder] is always shown; [bodyBuilder], when present, renders
/// below it while the section is expanded. The whole header area is
/// clickable to toggle expansion — [headerBuilder] should not wrap its
/// content in its own tappable, except for controls (like a dismiss button)
/// that must act independently of the toggle.
class AcpActivityBarSection {
  const AcpActivityBarSection({
    required this.id,
    required this.headerBuilder,
    this.bodyBuilder,
    this.initiallyExpanded = false,
  });

  final String id;
  final AcpActivityBarSectionHeaderBuilder headerBuilder;
  final AcpActivityBarSectionBodyBuilder? bodyBuilder;
  final bool initiallyExpanded;
}

/// Docked container, above the composer, for whatever is blocking or
/// informing the next turn — today just the agent's plan
/// ([AcpProgressChecklist]); edited files and a queued-messages summary are
/// reserved future sections (see
/// `openspec/changes/add-plan-progress-checklist/design.md`), registered the
/// same way without any change to this widget. Renders nothing when
/// [sections] is empty, so a host never has to conditionally include it.
class AcpActivityBar extends StatefulWidget {
  const AcpActivityBar({required this.sections, super.key});

  final List<AcpActivityBarSection> sections;

  @override
  State<AcpActivityBar> createState() => _AcpActivityBarState();
}

class _AcpActivityBarState extends State<AcpActivityBar> {
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    for (final section in widget.sections) {
      if (section.initiallyExpanded) {
        _expandedIds.add(section.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) Container(height: 1, color: Colors.grey.withAlpha(54)),
            _AcpActivityBarSectionView(
              section: sections[i],
              expanded: _expandedIds.contains(sections[i].id),
              onToggle: () => setState(() {
                final id = sections[i].id;
                if (!_expandedIds.remove(id)) {
                  _expandedIds.add(id);
                }
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _AcpActivityBarSectionView extends StatelessWidget {
  const _AcpActivityBarSectionView({
    required this.section,
    required this.expanded,
    required this.onToggle,
  });

  final AcpActivityBarSection section;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Button(
          onPressed: onToggle,
          style: ButtonStyle(
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.isHovered
                  ? Colors.grey.withAlpha(18)
                  : Colors.transparent;
            }),
            shape: WidgetStateProperty.all(const RoundedRectangleBorder()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: section.headerBuilder(context, expanded),
          ),
        ),
        if (expanded && section.bodyBuilder != null)
          section.bodyBuilder!(context),
      ],
    );
  }
}
