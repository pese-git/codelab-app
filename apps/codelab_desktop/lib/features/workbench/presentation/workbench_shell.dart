import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../app/app_scope.dart';
import '../../../app/navigation/navigation_cubit.dart';
import '../../../app/navigation/settings_page.dart';
import '../application/sessions_cubit.dart' show PendingRootSession;
import '../../project_files/presentation/project_files_pane.dart';
import '../../terminal/application/terminal_tabs_cubit.dart';
import '../../terminal/presentation/terminal_pane.dart';
import '../application/shell_cubit.dart';
import '../application/ui_mappers.dart'
    show connectionTooltipOf, sidebarProjectsOf;
import 'widgets/debug_log_pane.dart';
import 'widgets/debug_log_viewer_dialog.dart';
import 'widgets/inspector_pane.dart';
import 'widgets/main_pane.dart';
import 'widgets/secret_migration_banner.dart';

/// Рабочее место CodeLab: каркас из app bar, сайдбара по проектам, панели
/// сессии и дока панелей инструментов (`dart-agent-and-clients` §12.3 A13,
/// шаг 0; change `redesign-workbench-shell`).
///
/// Состояние читает из [CodeLabShellCubit], раскладку по ширине окна
/// выбирает [CodeLabWorkbenchLayout]; здесь — только сборка зон и привязка
/// колбэков.
class CodeLabShell extends StatelessWidget {
  const CodeLabShell({super.key});

  /// Панели дока, для которых есть данные (D5); остальные ждут своих change.
  ///
  /// Files вычисляется: он есть, только когда папка сессии на этой машине и
  /// хост привязал `ProjectFiles` (`CodeLabShellState.projectFilesAvailable`,
  /// design.md change `add-file-preview-and-tree`, D7). Недоступная панель
  /// остаётся в сохранённой раскладке и возвращается вместе с локальным
  /// профилем (spec agent-workbench-ui «Unavailable pane is hidden but kept in
  /// the layout»). Terminal входит, только если на платформе есть PTY
  /// (`add-integrated-terminal`, D12): без него переключателя нет.
  static List<ToolPane> _availablePanesOf(
    CodeLabShellState state, {
    required bool terminal,
  }) => [
    if (state.projectFilesAvailable) ToolPane.files,
    ToolPane.plan,
    ToolPane.protocol,
    if (terminal) ToolPane.terminal,
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final cubit = context.read<CodeLabShellCubit>();
        final logBuffer = codeLabDependenciesOf(context).logBuffer;
        final terminals = context.read<TerminalTabsCubit>();
        final layoutClass = CodeLabLayoutClass.ofContext(context);
        final availablePanes = _availablePanesOf(
          state,
          terminal: terminals.isSupported,
        );
        final openPanes = [
          for (final pane in state.openPanes)
            if (availablePanes.contains(pane)) pane,
        ];
        // В узких классах док выдвигается поверх ленты; скрытый док не значит
        // закрытые панели, поэтому переключатель сначала снова выдвигает
        // его, а подсвечен, только пока панель видна.
        final dockVisible =
            openPanes.isNotEmpty &&
            (layoutClass.dockAsColumn || state.dockOverlayOpen);

        return CodeLabWorkbenchShortcuts(
          onOpenCommandPalette: cubit.openCommandPalette,
          onCancel: state.pendingRootSession != null
              ? cubit.cancelRootSession
              : state.isCommandPaletteOpen
              ? cubit.closeCommandPalette
              : (state.canCancel ? cubit.cancelTurn : null),
          // Агент стартует сам (D13): «New session» доступна при выбранном
          // проекте и без соединения.
          onNewSession: state.selectedProjectPath != null
              ? () => unawaited(cubit.createSession())
              : null,
          onOpenSettings: () =>
              _openSettings(context, SettingsOpenSource.shortcut),
          onToggleFiles: state.projectFilesAvailable
              ? () => cubit.togglePane(ToolPane.files)
              : null,
          onToggleSidebar: layoutClass.sidebarAsColumn
              ? cubit.toggleSidebarCollapsed
              : cubit.toggleSidebarOverlay,
          child: NavigationView(
            content: Stack(
              children: [
                _ResizableWorkbenchLayout(
                  sessionsPaneWidth: state.sessionsPaneWidth,
                  dockWidth: state.dockWidth,
                  onSessionsPaneResized: cubit.resizeSessionsPane,
                  onDockResized: cubit.resizeDock,
                  sidebarCollapsed: state.sidebarCollapsed,
                  sidebarOverlayOpen: state.sidebarOverlayOpen,
                  dockOverlayOpen: state.dockOverlayOpen,
                  onSidebarOverlayDismiss: cubit.closeSidebarOverlay,
                  onDockOverlayDismiss: cubit.dismissDockOverlay,
                  appBar: CodeLabAppBar(
                    title: 'CodeLab',
                    connectionStatus: state.connectionStatus,
                    searchShortcutLabel:
                        defaultTargetPlatform == TargetPlatform.macOS
                        ? '⌘K'
                        : 'Ctrl+K',
                    onSearch: cubit.openCommandPalette,
                    paneToggles: [
                      for (final pane in availablePanes)
                        CodeLabPaneToggle(
                          pane: pane,
                          selected:
                              dockVisible &&
                              state.activePane == pane &&
                              openPanes.contains(pane),
                        ),
                    ],
                    onPaneToggled: (pane) {
                      // Панель закрывается, только если она видна и активна;
                      // иначе действие её открывает (`togglePane`).
                      final opens =
                          !(dockVisible &&
                              state.activePane == pane &&
                              openPanes.contains(pane));
                      dockVisible
                          ? cubit.togglePane(pane)
                          : cubit.openPane(pane);
                      // Открытие действием пользователя создаёт первую
                      // вкладку; восстановленный док её не создаёт (D1).
                      if (opens && pane == ToolPane.terminal) {
                        unawaited(terminals.ensureTab());
                      }
                    },
                    connectionTooltip: connectionTooltipOf(
                      profileLabel: state.profileLabel,
                      transportLabel: state.transportLabel,
                      connectionDetail: state.connectionDetail,
                    ),
                    // Бейдж без «Connect» (D18): агент стартует сам; в
                    // `lost`/`failed` «Retry» делает то же, что кнопка баннера.
                    onRetry: () => unawaited(cubit.retryStart()),
                    onMenu: layoutClass.sidebarAsColumn
                        ? null
                        : cubit.toggleSidebarOverlay,
                  ),
                  sidebar: CodeLabSessionSidebar(
                    projects: sidebarProjectsOf(
                      selectedProjectPath: state.selectedProjectPath,
                      sessions: state.sessions,
                      recentProjects: state.recentProjects,
                      sessionFolders: state.sessionFolders,
                    ),
                    activeSessionId: state.activeSessionId,
                    onSessionSelected: (id) {
                      cubit.selectSession(id);
                      cubit.closeSidebarOverlay();
                    },
                    onNewSession: () => unawaited(cubit.createSession()),
                    newSessionShortcut:
                        defaultTargetPlatform == TargetPlatform.macOS
                        ? '⌘N'
                        : 'Ctrl+N',
                    onProjectSelected: (path) =>
                        unawaited(cubit.selectProject(path)),
                    onLoadMore: state.hasMoreSessions
                        ? () => unawaited(cubit.loadMoreSessions())
                        : null,
                    onOpenFolder: () => unawaited(cubit.browseForProject()),
                    onSettings: () =>
                        _openSettings(context, SettingsOpenSource.sidebar),
                  ),
                  sessionPane: WorkbenchMainPane(
                    state: state,
                    cubit: cubit,
                    // «Restart agent» — тот же единственный перезапуск с
                    // подтверждением при работе (D22); прежний агент
                    // закрывает резолвер (D6 change `add-embedded-agent-mode`).
                    secretMigrationBanner: SecretMigrationBanner(
                      onRestart: () => unawaited(cubit.restartAgent()),
                    ),
                  ),
                  dock: openPanes.isEmpty
                      ? null
                      : CodeLabToolDock(
                          active: state.activePane ?? openPanes.last,
                          onSelected: cubit.selectPane,
                          onClosed: cubit.closePane,
                          tabs: [
                            for (final pane in openPanes)
                              CodeLabDockTab(
                                pane: pane,
                                content: switch (pane) {
                                  ToolPane.files => const ProjectFilesPane(),
                                  ToolPane.plan =>
                                    CodeLabProgressChecklist.list(
                                      entries: state.currentPlan ?? const [],
                                    ),
                                  ToolPane.terminal =>
                                    const WorkbenchTerminalPane(),
                                  _ => _ProtocolPane(
                                    state: state,
                                    logBuffer: logBuffer,
                                  ),
                                },
                              ),
                          ],
                        ),
                ),
                if (state.isCommandPaletteOpen)
                  _CommandPaletteOverlay(state: state, cubit: cubit),
                if (state.pendingRootSession case final pending?)
                  _RootSessionDialog(pending: pending, cubit: cubit),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Открывает настройки: Cmd/Ctrl+, и кнопка «Settings» сайдбара.
///
/// Почему через `NavigationCubit`: переход — состояние приложения, а не
/// маршрут (design.md change `add-app-settings-shell`, D1). Открывается
/// последняя страница или «Connection»; при пустом наборе страниц вызов
/// ничего не делает (SETUP-17).
void _openSettings(BuildContext context, SettingsOpenSource source) {
  unawaited(
    codeLabDependenciesOf(context).navigationCubit.openSettings(source: source),
  );
}

/// «Configure connection» экрана подключения и баннера соединения: открывает
/// страницу «Connection» (design.md change `add-app-settings-shell`, D6;
/// вместо прежнего диалога подключения).
void openConnectionSettings(BuildContext context) {
  unawaited(
    codeLabDependenciesOf(context).navigationCubit.openSettings(
      page: SettingsPage.connection,
      source: SettingsOpenSource.banner,
    ),
  );
}

/// Панель Protocol дока: записи протокола текущей сессии (бывший Inspector)
/// и debug log с поиском, фильтром и Expand (change
/// `redesign-workbench-shell`, D5).
class _ProtocolPane extends StatelessWidget {
  const _ProtocolPane({required this.state, required this.logBuffer});

  final CodeLabShellState state;
  final LogBuffer logBuffer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: WorkbenchInspectorPane(state: state)),
          const SizedBox(height: 8),
          Expanded(
            flex: 2,
            child: WorkbenchDebugLogPane(
              logBuffer: logBuffer,
              onExpand: () =>
                  unawaited(DebugLogViewerDialog.show(context, logBuffer)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог подтверждения открытия сессии в корне диска (D24).
///
/// Почему: сессия в `/` даёт агенту весь диск; решение, что это опасно,
/// принимает `SessionsCubit` (`pendingRootSession`), а виджет только
/// показывает вопрос и возвращает ответ (AGENTS.md §10). Диалог рисуется по
/// состоянию, поэтому вытеснение новым действием фокуса закрывает его без
/// участия виджета.
class _RootSessionDialog extends StatelessWidget {
  const _RootSessionDialog({required this.pending, required this.cubit});

  final PendingRootSession pending;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withAlpha(60),
        child: Center(
          child: ContentDialog(
            key: const ValueKey('root-session-dialog'),
            title: const Text('Open session in the disk root?'),
            content: Text(
              'This session runs in the disk root (${pending.cwd}). '
              'The agent gets access to the whole disk. Open anyway?',
            ),
            actions: [
              FilledButton(
                key: const ValueKey('root-session-open'),
                onPressed: cubit.confirmRootSession,
                child: const Text('Open'),
              ),
              Button(
                key: const ValueKey('root-session-cancel'),
                onPressed: cubit.cancelRootSession,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPaletteOverlay extends StatelessWidget {
  const _CommandPaletteOverlay({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withAlpha(60),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
            child: CodeLabCommandPaletteSurface(
              actions: state.paletteActions,
              search: state.searchPalette,
              onActionSelected: (action) =>
                  selectPaletteCommand(context, cubit, action),
            ),
          ),
        ),
      ),
    );
  }
}

/// Routes a selected [CodeLabCommandAction] to the right cubit method — shared
/// by the `Ctrl/Cmd+K` overlay and the inline composer trigger so both
/// paths behave identically (see wire-command-palette/design.md).
///
/// `/logs` открывает панель Protocol дока ([CodeLabShellCubit.selectCommand]);
/// полноэкранный просмотр логов — кнопка Expand в этой панели (change
/// `redesign-workbench-shell`, D5).
void selectPaletteCommand(
  BuildContext context,
  CodeLabShellCubit cubit,
  CodeLabCommandAction action,
) {
  if (action.source == CodeLabCommandSource.agent) {
    cubit.insertAgentCommand(action);
    return;
  }
  cubit.selectCommand(action);
}

/// Tracks a live, ephemeral preview of the sidebar and dock widths while
/// the user is dragging a resize divider, so every pointer movement only
/// rebuilds this small wrapper — not the whole cubit-driven workbench tree —
/// and only commits to [CodeLabShellCubit] (a real Bloc emit) once the drag
/// gesture ends. See add-resizable-panels/design.md Risks.
class _ResizableWorkbenchLayout extends StatefulWidget {
  const _ResizableWorkbenchLayout({
    required this.sessionsPaneWidth,
    required this.dockWidth,
    required this.onSessionsPaneResized,
    required this.onDockResized,
    required this.sidebarCollapsed,
    required this.sidebarOverlayOpen,
    required this.dockOverlayOpen,
    required this.onSidebarOverlayDismiss,
    required this.onDockOverlayDismiss,
    required this.appBar,
    required this.sidebar,
    required this.sessionPane,
    required this.dock,
  });

  final double sessionsPaneWidth;
  final double dockWidth;
  final ValueChanged<double> onSessionsPaneResized;
  final ValueChanged<double> onDockResized;
  final bool sidebarCollapsed;
  final bool sidebarOverlayOpen;
  final bool dockOverlayOpen;
  final VoidCallback onSidebarOverlayDismiss;
  final VoidCallback onDockOverlayDismiss;
  final Widget appBar;
  final Widget sidebar;
  final Widget sessionPane;
  final Widget? dock;

  @override
  State<_ResizableWorkbenchLayout> createState() =>
      _ResizableWorkbenchLayoutState();
}

class _ResizableWorkbenchLayoutState extends State<_ResizableWorkbenchLayout> {
  late double _sessionsPaneWidth = widget.sessionsPaneWidth;
  late double _dockWidth = widget.dockWidth;

  @override
  void didUpdateWidget(covariant _ResizableWorkbenchLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionsPaneWidth != widget.sessionsPaneWidth) {
      _sessionsPaneWidth = widget.sessionsPaneWidth;
    }
    if (oldWidget.dockWidth != widget.dockWidth) {
      _dockWidth = widget.dockWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CodeLabWorkbenchLayout(
      appBar: widget.appBar,
      sidebar: widget.sidebar,
      sessionPane: widget.sessionPane,
      dock: widget.dock,
      sidebarWidth: _sessionsPaneWidth,
      dockWidth: _dockWidth,
      sidebarCollapsed: widget.sidebarCollapsed,
      sidebarOverlayOpen: widget.sidebarOverlayOpen,
      dockOverlayOpen: widget.dockOverlayOpen,
      onSidebarOverlayDismiss: widget.onSidebarOverlayDismiss,
      onDockOverlayDismiss: widget.onDockOverlayDismiss,
      onSidebarWidthChanged: (dx) => setState(() {
        _sessionsPaneWidth = (_sessionsPaneWidth + dx).clamp(
          kSessionsPaneMinWidth,
          kSessionsPaneMaxWidth,
        );
      }),
      onSidebarResizeEnd: () =>
          widget.onSessionsPaneResized(_sessionsPaneWidth),
      onDockWidthChanged: (dx) => setState(() {
        _dockWidth = (_dockWidth + dx).clamp(kDockMinWidth, kDockMaxWidth);
      }),
      onDockResizeEnd: () => widget.onDockResized(_dockWidth),
    );
  }
}
