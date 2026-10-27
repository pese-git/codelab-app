import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../app/app_scope.dart';
import '../application/shell_cubit.dart';
import '../application/ui_mappers.dart'
    show connectionTooltipOf, sidebarProjectsOf;
import 'widgets/connection_setup_dialog.dart';
import 'widgets/debug_log_pane.dart';
import 'widgets/debug_log_viewer_dialog.dart';
import 'widgets/inspector_pane.dart';
import 'widgets/main_pane.dart';

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
  static const _availablePanes = [ToolPane.plan, ToolPane.protocol];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final cubit = context.read<CodeLabShellCubit>();
        final logBuffer = codeLabDependenciesOf(context).logBuffer;
        final layoutClass = CodeLabLayoutClass.ofContext(context);
        final openPanes = [
          for (final pane in state.openPanes)
            if (_availablePanes.contains(pane)) pane,
        ];
        // В узких классах док выдвигается поверх ленты; скрытый док не значит
        // закрытые панели, поэтому переключатель сначала снова выдвигает
        // его, а подсвечен, только пока панель видна.
        final dockVisible =
            openPanes.isNotEmpty &&
            (layoutClass.dockAsColumn || state.dockOverlayOpen);

        return CodeLabWorkbenchShortcuts(
          onOpenCommandPalette: cubit.openCommandPalette,
          onCancel: state.isCommandPaletteOpen
              ? cubit.closeCommandPalette
              : (state.canCancel ? cubit.cancelTurn : null),
          onNewSession:
              state.connectionStatus == CodeLabConnectionStatus.connected
              ? () => unawaited(cubit.createSession())
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
                      for (final pane in _availablePanes)
                        CodeLabPaneToggle(
                          pane: pane,
                          selected:
                              dockVisible &&
                              state.activePane == pane &&
                              openPanes.contains(pane),
                        ),
                    ],
                    onPaneToggled: (pane) => dockVisible
                        ? cubit.togglePane(pane)
                        : cubit.openPane(pane),
                    connectionTooltip: connectionTooltipOf(
                      profileLabel: state.profileLabel,
                      transportLabel: state.transportLabel,
                      connectionDetail: state.connectionDetail,
                    ),
                    onRetry: () => unawaited(cubit.reconnect()),
                    onConnect: () => unawaited(cubit.connect()),
                    onMenu: layoutClass.sidebarAsColumn
                        ? null
                        : cubit.toggleSidebarOverlay,
                  ),
                  sidebar: CodeLabSessionSidebar(
                    projects: sidebarProjectsOf(
                      selectedProjectPath: state.selectedProjectPath,
                      sessions: state.sessions,
                      recentProjects: state.recentProjects,
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
                    onSettings: () => ConnectionSetupDialog.show(context),
                  ),
                  sessionPane: WorkbenchMainPane(state: state, cubit: cubit),
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
                                  ToolPane.plan =>
                                    CodeLabProgressChecklist.list(
                                      entries: state.currentPlan ?? const [],
                                    ),
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
              ],
            ),
          ),
        );
      },
    );
  }
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
