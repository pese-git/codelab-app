import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

class AcpCommandPaletteSurface extends StatefulWidget {
  const AcpCommandPaletteSurface({
    this.actions = AcpCommandAction.defaults,
    this.initialQuery = '/',
    this.selectedActionId,
    this.emptyLabel = 'No matching commands',
    this.onActionSelected,
    super.key,
  });

  static const queryFieldKey = ValueKey('acp-command-palette-query');
  static const listKey = ValueKey('acp-command-palette-list');
  static const emptyKey = ValueKey('acp-command-palette-empty');

  final List<AcpCommandAction> actions;
  final String initialQuery;
  final String? selectedActionId;
  final String emptyLabel;
  final ValueChanged<AcpCommandAction>? onActionSelected;

  @override
  State<AcpCommandPaletteSurface> createState() =>
      _AcpCommandPaletteSurfaceState();
}

class _AcpCommandPaletteSurfaceState extends State<AcpCommandPaletteSurface> {
  late final TextEditingController _controller;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(AcpCommandPaletteSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != _query) {
      _query = widget.initialQuery;
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredActions = AcpCommandAction.filter(widget.actions, _query);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: kElevationToShadow[4],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AcpText('Command palette', role: AcpTextRole.subtitle),
            const SizedBox(height: 10),
            TextBox(
              key: AcpCommandPaletteSurface.queryFieldKey,
              controller: _controller,
              prefix: const Padding(
                padding: EdgeInsetsDirectional.only(start: 10),
                child: Icon(FluentIcons.search, size: 14),
              ),
              placeholder: '/command',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredActions.isEmpty
                  ? Center(
                      key: AcpCommandPaletteSurface.emptyKey,
                      child: AcpText(
                        widget.emptyLabel,
                        role: AcpTextRole.caption,
                      ),
                    )
                  : ListView.separated(
                      key: AcpCommandPaletteSurface.listKey,
                      itemCount: filteredActions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final action = filteredActions[index];

                        return _AcpCommandActionRow(
                          action: action,
                          selected: action.id == widget.selectedActionId,
                          onPressed: widget.onActionSelected == null
                              ? null
                              : () => widget.onActionSelected!(action),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcpCommandActionRow extends StatelessWidget {
  const _AcpCommandActionRow({
    required this.action,
    required this.selected,
    required this.onPressed,
  });

  final AcpCommandAction action;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final accentColor = FluentTheme.of(context).accentColor;
    final backgroundColor = selected
        ? accentColor.withAlpha(24)
        : Colors.transparent;
    final borderColor = selected ? accentColor : Colors.grey.withAlpha(38);

    return Semantics(
      selected: selected,
      button: true,
      label: action.slashCommand,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);

          return DecoratedBox(
            decoration: BoxDecoration(
              color: hovered && !selected
                  ? Colors.grey.withAlpha(18)
                  : backgroundColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AcpIcon(
                    action.icon,
                    tone: selected ? AcpTone.accent : AcpTone.neutral,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: AcpText(
                                action.label,
                                role: AcpTextRole.strong,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AcpBadge(
                              label: action.slashCommand,
                              tone: selected ? AcpTone.accent : AcpTone.neutral,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AcpText(
                          action.description,
                          role: AcpTextRole.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
