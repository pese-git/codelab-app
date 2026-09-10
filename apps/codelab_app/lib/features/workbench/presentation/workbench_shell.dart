import 'dart:async';

import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/shell_cubit.dart';
import 'widgets/command_bar.dart';
import 'widgets/debug_log_pane.dart';
import 'widgets/debug_log_viewer_dialog.dart';
import 'widgets/inspector_pane.dart';
import 'widgets/main_pane.dart';

class CodeLabShell extends StatelessWidget {
  const CodeLabShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final cubit = context.read<CodeLabShellCubit>();
        final logBuffer = codeLabDependenciesOf(context).logBuffer;

        return AcpWorkbenchShortcuts(
          onOpenCommandPalette: cubit.openCommandPalette,
          onCancel: state.isCommandPaletteOpen
              ? cubit.closeCommandPalette
              : (state.canCancel ? cubit.cancelTurn : null),
          child: NavigationView(
            content: Stack(
              children: [
                _ResizableWorkbenchLayout(
                  sessionsPaneWidth: state.sessionsPaneWidth,
                  inspectorPaneWidth: state.inspectorPaneWidth,
                  onSessionsPaneResized: cubit.resizeSessionsPane,
                  onInspectorPaneResized: cubit.resizeInspectorPane,
                  commandBar: WorkbenchCommandBar(state: state, cubit: cubit),
                  sessionsPane: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AcpProjectPicker(
                        currentProjectPath: state.selectedProjectPath,
                        recentProjects: state.recentProjects,
                        onProjectSelected: (path) =>
                            unawaited(cubit.selectProject(path)),
                        onBrowseRequested: () =>
                            unawaited(cubit.browseForProject()),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: AcpSessionSidebar(
                          sessions: state.sessions,
                          activeSessionId: state.activeSessionId,
                          onSessionSelected: cubit.selectSession,
                          onNewSession: cubit.createSession,
                        ),
                      ),
                    ],
                  ),
                  mainPane: WorkbenchMainPane(state: state, cubit: cubit),
                  inspectorPane: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: WorkbenchInspectorPane(state: state)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 280,
                        child: WorkbenchDebugLogPane(
                          logBuffer: logBuffer,
                          onExpand: () => unawaited(
                            DebugLogViewerDialog.show(context, logBuffer),
                          ),
                        ),
                      ),
                    ],
                  ),
                  inspectorVisibleInNarrowMode:
                      state.isInspectorVisibleInNarrowLayout,
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
            child: AcpCommandPaletteSurface(
              actions: state.paletteActions,
              onActionSelected: (action) =>
                  selectPaletteCommand(context, cubit, action),
            ),
          ),
        ),
      ),
    );
  }
}

/// Routes a selected [AcpCommandAction] to the right cubit method — shared
/// by the `Ctrl/Cmd+K` overlay and the inline composer trigger so both
/// paths behave identically (see wire-command-palette/design.md).
///
/// `/logs` additionally opens the full-screen [DebugLogViewerDialog] — the
/// same dialog [WorkbenchDebugLogPane]'s "Expand" button opens
/// (`replace-debug-log-panel-with-fluent/design.md`, Decision 4) — on top of
/// [CodeLabShellCubit.selectCommand]'s existing narrow-layout Inspector
/// reveal, which stays unrelated to logging and untouched.
void selectPaletteCommand(
  BuildContext context,
  CodeLabShellCubit cubit,
  AcpCommandAction action,
) {
  if (action.source == AcpCommandSource.agent) {
    cubit.insertAgentCommand(action);
    return;
  }
  if (action.id == 'logs') {
    unawaited(
      DebugLogViewerDialog.show(
        context,
        codeLabDependenciesOf(context).logBuffer,
      ),
    );
  }
  cubit.selectCommand(action);
}

/// Tracks a live, ephemeral preview of the sessions/inspector pane widths
/// while the user is dragging a resize divider, so every pointer movement
/// only rebuilds this small wrapper — not the whole cubit-driven workbench
/// tree — and only commits to [CodeLabShellCubit] (a real Bloc emit) once
/// the drag gesture ends. See add-resizable-panels/design.md Risks.
class _ResizableWorkbenchLayout extends StatefulWidget {
  const _ResizableWorkbenchLayout({
    required this.sessionsPaneWidth,
    required this.inspectorPaneWidth,
    required this.onSessionsPaneResized,
    required this.onInspectorPaneResized,
    required this.commandBar,
    required this.sessionsPane,
    required this.mainPane,
    required this.inspectorPane,
    required this.inspectorVisibleInNarrowMode,
  });

  final double sessionsPaneWidth;
  final double inspectorPaneWidth;
  final ValueChanged<double> onSessionsPaneResized;
  final ValueChanged<double> onInspectorPaneResized;
  final Widget commandBar;
  final Widget sessionsPane;
  final Widget mainPane;
  final Widget inspectorPane;
  final bool inspectorVisibleInNarrowMode;

  @override
  State<_ResizableWorkbenchLayout> createState() =>
      _ResizableWorkbenchLayoutState();
}

class _ResizableWorkbenchLayoutState extends State<_ResizableWorkbenchLayout> {
  late double _sessionsPaneWidth = widget.sessionsPaneWidth;
  late double _inspectorPaneWidth = widget.inspectorPaneWidth;

  @override
  void didUpdateWidget(covariant _ResizableWorkbenchLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionsPaneWidth != widget.sessionsPaneWidth) {
      _sessionsPaneWidth = widget.sessionsPaneWidth;
    }
    if (oldWidget.inspectorPaneWidth != widget.inspectorPaneWidth) {
      _inspectorPaneWidth = widget.inspectorPaneWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AcpWorkbenchLayout(
      commandBar: widget.commandBar,
      sessionsPane: widget.sessionsPane,
      mainPane: widget.mainPane,
      inspectorPane: widget.inspectorPane,
      inspectorVisibleInNarrowMode: widget.inspectorVisibleInNarrowMode,
      sessionsPaneWidth: _sessionsPaneWidth,
      inspectorPaneWidth: _inspectorPaneWidth,
      onSessionsPaneWidthChanged: (dx) => setState(() {
        _sessionsPaneWidth = (_sessionsPaneWidth + dx).clamp(
          kSessionsPaneMinWidth,
          kSessionsPaneMaxWidth,
        );
      }),
      onSessionsPaneResizeEnd: () =>
          widget.onSessionsPaneResized(_sessionsPaneWidth),
      onInspectorPaneWidthChanged: (dx) => setState(() {
        _inspectorPaneWidth = (_inspectorPaneWidth + dx).clamp(
          kInspectorPaneMinWidth,
          kInspectorPaneMaxWidth,
        );
      }),
      onInspectorPaneResizeEnd: () =>
          widget.onInspectorPaneResized(_inspectorPaneWidth),
    );
  }
}
