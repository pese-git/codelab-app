import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/shell_cubit.dart';
import '../workbench_shell.dart' show selectPaletteCommand;
import 'connection_setup_dialog.dart';
import 'current_session_panel.dart';

class WorkbenchMainPane extends StatelessWidget {
  const WorkbenchMainPane({
    required this.state,
    required this.cubit,
    super.key,
  });

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.transcriptEntries.isEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CurrentSessionPanel(state: state),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight > 180
                              ? constraints.maxHeight - 180
                              : 0,
                        ),
                        child: AcpConnectionScreen(
                          status: state.connectionStatus,
                          transportLabel: state.transportLabel,
                          profileLabel: state.profileLabel,
                          detail: state.connectionDetail,
                          description:
                              'Connect an ACP agent to start a session.',
                          onConnect: cubit.connect,
                          onReconnect: cubit.reconnect,
                          onConfigureConnection: () =>
                              ConnectionSetupDialog.show(context),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        else ...[
          CurrentSessionPanel(state: state),
          const SizedBox(height: 12),
          Expanded(
            child: AcpTranscriptPanel(
              entries: state.transcriptEntries,
              viewMode: state.viewMode,
            ),
          ),
        ],
        const SizedBox(height: 12),
        AcpPromptComposer(
          enabled: state.isPromptEnabled,
          isSubmitting: state.isPromptSubmitting,
          canCancel: state.canCancel,
          initialPrompt: state.composerDraft,
          onSubmit: cubit.submitPrompt,
          onCancel: cubit.cancelTurn,
          commandActions: state.paletteActions,
          onCommandSelected: (action) => selectPaletteCommand(cubit, action),
          configOptions: state.configOptions,
          onConfigOptionSelected: cubit.setSessionConfigOption,
          isRespondingToConfigOption: state.isRespondingToConfigOption,
        ),
      ],
    );
  }
}
