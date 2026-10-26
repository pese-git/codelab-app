import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

class CodeLabCommandPaletteSurface extends StatefulWidget {
  const CodeLabCommandPaletteSurface({
    this.actions = CodeLabCommandAction.defaults,
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

  final List<CodeLabCommandAction> actions;
  final String initialQuery;
  final String? selectedActionId;
  final String emptyLabel;
  final ValueChanged<CodeLabCommandAction>? onActionSelected;

  /// When `false`, the surface does not render its own [TextBox] and
  /// filters [actions] using [queryOverride] instead — used for the inline
  /// trigger anchored above the prompt composer, where the user keeps
  /// typing in the composer itself rather than a separate search field.
  final bool showSearchField;
  final String? queryOverride;

  @override
  State<CodeLabCommandPaletteSurface> createState() =>
      _AcpCommandPaletteSurfaceState();
}

class _AcpCommandPaletteSurfaceState
    extends State<CodeLabCommandPaletteSurface> {
  late final TextEditingController _controller;

  /// Фокус поля поиска палитры.
  ///
  /// Почему: палитра открывается поверх композера, который уже держит фокус,
  /// а `autofocus` срабатывает, только когда в области фокуса никого нет, —
  /// без явного запроса ввод после Cmd/Ctrl+K уходил бы в композер. При
  /// закрытии палитры узел удаляется, и `FocusScope` возвращает фокус
  /// прежнему владельцу, поэтому сочетания workbench продолжают работать.
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'command-palette-search',
  );
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.showSearchField
        ? widget.initialQuery
        : (widget.queryOverride ?? '');
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.showSearchField) {
      // Запрос фокуса во время первого build недопустим, поэтому — после кадра.
      // Без `Overlay` (превью виджета вне `FluentApp`) поле с фокусом падает
      // на ручках выделения; в app `Overlay` есть всегда.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Overlay.maybeOf(context) != null) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(CodeLabCommandPaletteSurface oldWidget) {
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
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredActions = CodeLabCommandAction.filter(widget.actions, _query);
    final clientActions = filteredActions
        .where((action) => action.source == CodeLabCommandSource.client)
        .toList(growable: false);
    final agentActions = filteredActions
        .where((action) => action.source == CodeLabCommandSource.agent)
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        // Сплошная заливка, а не `scaffoldBackgroundColor`: без темы app
        // fluent_ui отдаёт там полупрозрачный акрил (25 % в светлой теме),
        // и лента под палитрой просвечивала сквозь список команд.
        color: FluentTheme.of(context).resources.solidBackgroundFillColorBase,
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
              const CodeLabText(
                'Command palette',
                role: CodeLabTextRole.subtitle,
              ),
              const SizedBox(height: 10),
              TextBox(
                key: CodeLabCommandPaletteSurface.queryFieldKey,
                controller: _controller,
                focusNode: _searchFocusNode,
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
                  key: CodeLabCommandPaletteSurface.emptyKey,
                  child: CodeLabText(
                    widget.emptyLabel,
                    role: CodeLabTextRole.caption,
                  ),
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
    List<CodeLabCommandAction> clientActions,
    List<CodeLabCommandAction> agentActions,
  ) {
    final rows = <Widget>[
      for (final action in clientActions) ...[
        _buildRow(action),
        const SizedBox(height: 6),
      ],
      if (agentActions.isNotEmpty) ...[
        Padding(
          key: CodeLabCommandPaletteSurface.agentSectionHeaderKey,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: CodeLabText('From agent', role: CodeLabTextRole.caption),
        ),
        const SizedBox(height: 6),
        for (final action in agentActions) ...[
          _buildRow(action),
          const SizedBox(height: 6),
        ],
      ],
    ];

    final list = ListView(
      key: CodeLabCommandPaletteSurface.listKey,
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

  Widget _buildRow(CodeLabCommandAction action) {
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

  final CodeLabCommandAction action;
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
                    CodeLabIcon(
                      action.icon,
                      tone: selected ? CodeLabTone.accent : CodeLabTone.neutral,
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
                                child: CodeLabText(
                                  action.label,
                                  role: CodeLabTextRole.strong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CodeLabBadge(
                                label: action.slashCommand,
                                tone: selected
                                    ? CodeLabTone.accent
                                    : CodeLabTone.neutral,
                              ),
                              if (unavailable) ...[
                                const SizedBox(width: 8),
                                const CodeLabBadge(
                                  label: 'Coming soon',
                                  tone: CodeLabTone.warning,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          CodeLabText(
                            action.description,
                            role: CodeLabTextRole.caption,
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
