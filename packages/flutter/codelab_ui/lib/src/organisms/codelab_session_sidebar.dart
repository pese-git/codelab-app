import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

typedef CodeLabSessionSelected = void Function(String sessionId);

enum CodeLabSessionStatus {
  idle,
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,

  /// Сессия есть у агента (`session/list`), но в этом запуске не открыта;
  /// выбор строки загружает её (change `add-session-list-and-reload`, D7).
  notLoaded,

  /// Сессия была открыта, но после переподключения агент её не знает.
  detached,
}

class CodeLabSessionListItem {
  const CodeLabSessionListItem({
    required this.id,
    required this.title,
    required this.status,
    this.subtitle,
    this.updatedLabel,
  });

  final String id;
  final String title;
  final CodeLabSessionStatus status;

  /// Вторая строка (обычно `cwd`); в сайдбаре по проектам — подсказка строки,
  /// проект и так виден заголовком группы.
  final String? subtitle;
  final String? updatedLabel;
}

/// Недавний проект для UI — уже без времени открытия: порядок по свежести
/// применяет app до передачи списка (add-open-project-picker/design.md,
/// Decision 5). Из него app строит свёрнутые группы [CodeLabSidebarProject].
class CodeLabRecentProject {
  const CodeLabRecentProject({required this.path});

  final String path;

  @override
  bool operator ==(Object other) =>
      other is CodeLabRecentProject && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Группа проекта в сайдбаре.
///
/// [current] — выбранный проект: группа раскрыта и содержит [sessions];
/// остальные группы — недавние проекты без сессий, их выбор переключает
/// проект (change `redesign-workbench-shell`, D4).
class CodeLabSidebarProject {
  const CodeLabSidebarProject({
    required this.path,
    required this.name,
    this.current = false,
    this.sessions = const [],
  });

  /// Полный путь папки — идентификатор группы и подсказка заголовка.
  final String path;

  /// Имя папки — заголовок группы.
  final String name;
  final bool current;
  final List<CodeLabSessionListItem> sessions;
}

/// Сайдбар сессий по проектам.
///
/// Почему: прежний сайдбар был плоским списком под выпадающим выбором
/// проекта с полными путями; макет (артборд Main, A13 шаг 0) группирует
/// сессии по проектам и ставит New session, поиск, Open folder и Settings в
/// сам сайдбар (change `redesign-workbench-shell`, D3, D4).
///
/// Для чего: организм в визуальном языке `NavigationPane` без самого
/// `NavigationView` — тот владеет телом страницы и переключается по своим
/// порогам (D3). Фильтр по названию — временное состояние окна, поэтому
/// живёт в виджете.
///
/// Как использовать: хост передаёт [projects], активную сессию и колбэки.
/// [onLoadMore] — `null`, если у текущего проекта больше нет страниц
/// `session/list`. При ширине меньше [compactThreshold] сайдбар рисует только
/// иконки (свёрнутый режим по Cmd/Ctrl+B).
class CodeLabSessionSidebar extends StatefulWidget {
  const CodeLabSessionSidebar({
    required this.projects,
    required this.onSessionSelected,
    this.activeSessionId,
    this.onNewSession,
    this.newSessionShortcut = 'Ctrl+N',
    this.onProjectSelected,
    this.onLoadMore,
    this.onOpenFolder,
    this.onSettings,
    this.emptyLabel = 'No sessions yet',
    super.key,
  });

  static const compactThreshold = 120.0;
  static const filterKey = ValueKey('sidebar-filter');
  static const newSessionKey = ValueKey('new-session-button');
  static const loadMoreKey = ValueKey('sessions-load-more');
  static const openFolderKey = ValueKey('sidebar-open-folder');
  static const settingsKey = ValueKey('sidebar-settings');

  /// Ключ заголовка группы проекта (A13, шаг 8).
  static ValueKey<String> projectKey(String name) =>
      ValueKey('sidebar-project-$name');

  static ValueKey<String> sessionKey(String id) => ValueKey('session-$id');

  final List<CodeLabSidebarProject> projects;
  final String? activeSessionId;
  final CodeLabSessionSelected onSessionSelected;
  final VoidCallback? onNewSession;
  final String newSessionShortcut;

  /// Выбор другого проекта по его пути.
  final ValueChanged<String>? onProjectSelected;

  /// Подгрузка следующей страницы сессий текущего проекта; `null` — страниц
  /// больше нет (design D7 change `add-session-list-and-reload`).
  final VoidCallback? onLoadMore;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onSettings;
  final String emptyLabel;

  @override
  State<CodeLabSessionSidebar> createState() => _CodeLabSessionSidebarState();
}

class _CodeLabSessionSidebarState extends State<CodeLabSessionSidebar> {
  final _filter = TextEditingController();

  /// Текущий проект можно свернуть вручную; выбор другого проекта раскрывает
  /// новый текущий заново.
  bool _currentCollapsed = false;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.projects.where((p) => p.current).firstOrNull;
    if (current?.path != _currentPath) {
      _currentPath = current?.path;
      _currentCollapsed = false;
    }
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < CodeLabSessionSidebar.compactThreshold
            ? _buildCompact(current)
            : _buildOpen(current),
      ),
    );
  }

  Widget _buildOpen(CodeLabSidebarProject? current) {
    final query = _filter.text.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: _PaneRow(
            key: CodeLabSessionSidebar.newSessionKey,
            icon: FluentIcons.add,
            label: 'New session',
            trailing: widget.newSessionShortcut,
            onPressed: widget.onNewSession,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: TextBox(
            key: CodeLabSessionSidebar.filterKey,
            controller: _filter,
            placeholder: 'Search sessions',
            suffix: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(FluentIcons.search, size: 12),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 4, 12, 4),
          child: CodeLabText('Projects', role: CodeLabTextRole.strong),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            children: [
              for (final project in widget.projects)
                ..._projectGroup(project, query),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PaneRow(
                key: CodeLabSessionSidebar.openFolderKey,
                icon: FluentIcons.open_folder_horizontal,
                label: 'Open folder…',
                onPressed: widget.onOpenFolder,
              ),
              _PaneRow(
                key: CodeLabSessionSidebar.settingsKey,
                icon: FluentIcons.settings,
                label: 'Settings',
                onPressed: widget.onSettings,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _projectGroup(CodeLabSidebarProject project, String query) {
    final expanded = project.current && !_currentCollapsed;
    final sessions = [
      for (final session in project.sessions)
        if (query.isEmpty || session.title.toLowerCase().contains(query))
          session,
    ];
    return [
      Tooltip(
        message: project.path,
        child: _PaneRow(
          key: CodeLabSessionSidebar.projectKey(project.name),
          icon: expanded ? FluentIcons.chevron_down : FluentIcons.chevron_right,
          secondIcon: FluentIcons.folder_horizontal,
          label: project.name,
          strong: project.current,
          trailing: project.current ? '${project.sessions.length}' : null,
          onPressed: project.current
              ? () => setState(() => _currentCollapsed = !_currentCollapsed)
              : widget.onProjectSelected == null
              ? null
              : () => widget.onProjectSelected!(project.path),
        ),
      ),
      if (expanded) ...[
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 6, 8, 6),
            child: CodeLabText(
              query.isEmpty ? widget.emptyLabel : 'No matching sessions',
              role: CodeLabTextRole.caption,
            ),
          ),
        for (final session in sessions)
          _SessionRow(
            session: session,
            selected: session.id == widget.activeSessionId,
            onSelected: () => widget.onSessionSelected(session.id),
          ),
        if (widget.onLoadMore != null && query.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 18),
            child: _PaneRow(
              key: CodeLabSessionSidebar.loadMoreKey,
              icon: FluentIcons.chevron_down_med,
              label: 'Load more sessions',
              onPressed: widget.onLoadMore,
            ),
          ),
      ],
    ];
  }

  Widget _buildCompact(CodeLabSidebarProject? current) {
    return Column(
      children: [
        const SizedBox(height: 6),
        _CompactButton(
          key: CodeLabSessionSidebar.newSessionKey,
          icon: FluentIcons.add,
          tooltip: 'New session (${widget.newSessionShortcut})',
          onPressed: widget.onNewSession,
        ),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              for (final session in current?.sessions ?? const [])
                _CompactButton(
                  key: CodeLabSessionSidebar.sessionKey(session.id),
                  icon: _statusIcon(session.status),
                  tone: _statusTone(session.status),
                  selected: session.id == widget.activeSessionId,
                  tooltip: session.title,
                  onPressed: () => widget.onSessionSelected(session.id),
                ),
            ],
          ),
        ),
        _CompactButton(
          key: CodeLabSessionSidebar.openFolderKey,
          icon: FluentIcons.open_folder_horizontal,
          tooltip: 'Open folder…',
          onPressed: widget.onOpenFolder,
        ),
        _CompactButton(
          key: CodeLabSessionSidebar.settingsKey,
          icon: FluentIcons.settings,
          tooltip: 'Settings',
          onPressed: widget.onSettings,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Строка в стиле пункта `NavigationPane`: высота 36, отступы иконки 12 и
/// подписи 10 (`NavigationPaneThemeData.standard`, спайк 1.1 change
/// `redesign-workbench-shell`).
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondIcon,
    this.trailing,
    this.strong = false,
    super.key,
  });

  final IconData icon;
  final IconData? secondIcon;
  final String label;
  final String? trailing;
  final bool strong;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) => Container(
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: states.isHovered
              ? theme.resources.subtleFillColorTertiary
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(icon, size: 12),
            ),
            if (secondIcon != null) ...[
              Icon(secondIcon, size: 14),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: CodeLabText(
                label,
                role: strong ? CodeLabTextRole.strong : CodeLabTextRole.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              CodeLabText(trailing!, role: CodeLabTextRole.caption),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.selected,
    required this.onSelected,
  });

  final CodeLabSessionListItem session;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final badge = _statusBadge(session.status);
    final row = HoverButton(
      key: CodeLabSessionSidebar.sessionKey(session.id),
      onPressed: onSelected,
      builder: (context, states) => Container(
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsetsDirectional.only(start: 30, end: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.resources.subtleFillColorSecondary
              : states.isHovered
              ? theme.resources.subtleFillColorTertiary
              : null,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border(left: BorderSide(color: theme.accentColor, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: CodeLabText(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              CodeLabBadge(label: badge, tone: _statusTone(session.status)),
            ],
          ],
        ),
      ),
    );
    final subtitle = session.subtitle;
    return subtitle == null ? row : Tooltip(message: subtitle, child: row);
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tone = CodeLabTone.neutral,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final CodeLabTone tone;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) => Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: selected
                ? theme.resources.subtleFillColorSecondary
                : states.isHovered
                ? theme.resources.subtleFillColorTertiary
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(child: CodeLabIcon(icon, tone: tone, size: 14)),
        ),
      ),
    );
  }
}

/// Бейдж статуса только у заметных состояний: обычная и завершённая сессия
/// бейджа не получают, как на артборде Main.
String? _statusBadge(CodeLabSessionStatus status) => switch (status) {
  CodeLabSessionStatus.idle || CodeLabSessionStatus.completed => null,
  CodeLabSessionStatus.running => 'Running',
  CodeLabSessionStatus.awaitingApproval => 'Approval',
  CodeLabSessionStatus.failed => 'Failed',
  CodeLabSessionStatus.cancelled => 'Cancelled',
  CodeLabSessionStatus.notLoaded => 'Not loaded',
  CodeLabSessionStatus.detached => 'Detached',
};

CodeLabTone _statusTone(CodeLabSessionStatus status) => switch (status) {
  CodeLabSessionStatus.idle => CodeLabTone.neutral,
  CodeLabSessionStatus.running => CodeLabTone.accent,
  CodeLabSessionStatus.awaitingApproval => CodeLabTone.warning,
  CodeLabSessionStatus.completed => CodeLabTone.success,
  CodeLabSessionStatus.failed => CodeLabTone.danger,
  CodeLabSessionStatus.cancelled => CodeLabTone.warning,
  CodeLabSessionStatus.notLoaded => CodeLabTone.neutral,
  CodeLabSessionStatus.detached => CodeLabTone.warning,
};

IconData _statusIcon(CodeLabSessionStatus status) => switch (status) {
  CodeLabSessionStatus.idle => FluentIcons.circle_ring,
  CodeLabSessionStatus.running => FluentIcons.processing,
  CodeLabSessionStatus.awaitingApproval => FluentIcons.permissions,
  CodeLabSessionStatus.completed => FluentIcons.completed,
  CodeLabSessionStatus.failed => FluentIcons.error,
  CodeLabSessionStatus.cancelled => FluentIcons.cancel,
  CodeLabSessionStatus.notLoaded => FluentIcons.history,
  CodeLabSessionStatus.detached => FluentIcons.plug_disconnected,
};
