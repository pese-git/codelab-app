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
    this.showSearchField = true,
    this.queryOverride,
    super.key,
  });

  static const queryFieldKey = ValueKey('acp-command-palette-query');
  static const listKey = ValueKey('acp-command-palette-list');
  static const emptyKey = ValueKey('acp-command-palette-empty');
  static const agentSectionHeaderKey = ValueKey(
    'acp-command-palette-agent-section',
  );

  final List<AcpCommandAction> actions;
  final String initialQuery;
  final String? selectedActionId;
  final String emptyLabel;
  final ValueChanged<AcpCommandAction>? onActionSelected;

  /// When `false`, the surface does not render its own [TextBox] and
  /// filters [actions] using [queryOverride] instead — used for the inline
  /// trigger anchored above the prompt composer, where the user keeps
  /// typing in the composer itself rather than a separate search field.
  final bool showSearchField;
  final String? queryOverride;

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
    _query = widget.showSearchField
        ? widget.initialQuery
        : (widget.queryOverride ?? '');
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(AcpCommandPaletteSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSearchField) {
      if (widget.initialQuery != oldWidget.initialQuery &&
          widget.initialQuery != _query) {
        _query = widget.initialQuery;
        _controller.text = widget.initialQuery;
      }
    } else if (widget.queryOverride != oldWidget.queryOverride) {
      _query = widget.queryOverride ?? '';
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
    final clientActions = filteredActions
        .where((action) => action.source == AcpCommandSource.client)
        .toList(growable: false);
    final agentActions = filteredActions
        .where((action) => action.source == AcpCommandSource.agent)
        .toList(growable: false);

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
          mainAxisSize: widget.showSearchField
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.showSearchField) ...[
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
            ],
            if (filteredActions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  key: AcpCommandPaletteSurface.emptyKey,
                  child: AcpText(widget.emptyLabel, role: AcpTextRole.caption),
                ),
              )
            else
              _buildList(clientActions, agentActions),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<AcpCommandAction> clientActions,
    List<AcpCommandAction> agentActions,
  ) {
    final rows = <Widget>[
      for (final action in clientActions) ...[
        _buildRow(action),
        const SizedBox(height: 6),
      ],
      if (agentActions.isNotEmpty) ...[
        Padding(
          key: AcpCommandPaletteSurface.agentSectionHeaderKey,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AcpText('From agent', role: AcpTextRole.caption),
        ),
        const SizedBox(height: 6),
        for (final action in agentActions) ...[
          _buildRow(action),
          const SizedBox(height: 6),
        ],
      ],
    ];

    final list = ListView(
      key: AcpCommandPaletteSurface.listKey,
      shrinkWrap: !widget.showSearchField,
      children: rows,
    );

    if (widget.showSearchField) {
      return Expanded(child: list);
    }

    // No search field means no ancestor is guaranteed to hand this surface
    // a bounded height (the inline trigger sizes itself to content instead
    // of filling a modal). Cap it here so a long agent-declared command
    // list scrolls instead of overflowing the composer.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: list,
    );
  }

  Widget _buildRow(AcpCommandAction action) {
    return _AcpCommandActionRow(
      action: action,
      selected: action.id == widget.selectedActionId,
      onPressed: widget.onActionSelected == null
          ? null
          : () => widget.onActionSelected!(action),
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
    final unavailable = !action.isAvailable;

    return Semantics(
      selected: selected,
      button: true,
      enabled: !unavailable,
      label: action.slashCommand,
      child: Opacity(
        opacity: unavailable ? 0.55 : 1,
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
                                tone: selected
                                    ? AcpTone.accent
                                    : AcpTone.neutral,
                              ),
                              if (unavailable) ...[
                                const SizedBox(width: 8),
                                const AcpBadge(
                                  label: 'Coming soon',
                                  tone: AcpTone.warning,
                                ),
                              ],
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
      ),
    );
  }
}
