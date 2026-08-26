import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/shell_cubit.dart';
import 'widgets/command_bar.dart';
import 'widgets/inspector_pane.dart';
import 'widgets/main_pane.dart';

class CodeLabShell extends StatelessWidget {
  const CodeLabShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final cubit = context.read<CodeLabShellCubit>();

        return AcpWorkbenchShortcuts(
          onOpenCommandPalette: cubit.openCommandPalette,
          onCancel: state.isCommandPaletteOpen
              ? cubit.closeCommandPalette
              : (state.canCancel ? cubit.cancelTurn : null),
          child: NavigationView(
            content: Stack(
              children: [
                AcpWorkbenchLayout(
                  commandBar: WorkbenchCommandBar(state: state, cubit: cubit),
                  sessionsPane: AcpSessionSidebar(
                    sessions: state.sessions,
                    activeSessionId: state.activeSessionId,
                    onSessionSelected: cubit.selectSession,
                    onNewSession: cubit.createSession,
                  ),
                  mainPane: WorkbenchMainPane(state: state, cubit: cubit),
                  inspectorPane: WorkbenchInspectorPane(
                    state: state,
                    cubit: cubit,
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
              onActionSelected: (action) => selectPaletteCommand(cubit, action),
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
void selectPaletteCommand(CodeLabShellCubit cubit, AcpCommandAction action) {
  if (action.source == AcpCommandSource.agent) {
    cubit.insertAgentCommand(action);
  } else {
    cubit.selectCommand(action);
  }
}
