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
          onCancel: state.canCancel ? cubit.cancelTurn : null,
          child: NavigationView(
            content: AcpWorkbenchLayout(
              commandBar: WorkbenchCommandBar(state: state, cubit: cubit),
              sessionsPane: AcpSessionSidebar(
                sessions: state.sessions,
                activeSessionId: state.activeSessionId,
                onSessionSelected: cubit.selectSession,
                onNewSession: cubit.createSession,
              ),
              mainPane: WorkbenchMainPane(state: state, cubit: cubit),
              inspectorPane: WorkbenchInspectorPane(state: state, cubit: cubit),
            ),
          ),
        );
      },
    );
  }
}
