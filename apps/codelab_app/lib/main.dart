import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/app_scope.dart';
import 'src/presentation/shell_cubit.dart';

void main() {
  runApp(const CodeLabBootstrap(child: CodeLabApp()));
}

class CodeLabApp extends StatelessWidget {
  const CodeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);

    return FluentApp(
      title: 'CodeLab',
      home: BlocProvider.value(
        value: dependencies.shellCubit,
        child: const CodeLabShell(),
      ),
    );
  }
}

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
              commandBar: _CodeLabCommandBar(state: state, cubit: cubit),
              sessionsPane: AcpSessionSidebar(
                sessions: state.sessions,
                activeSessionId: state.activeSessionId,
                onSessionSelected: cubit.selectSession,
                onNewSession: cubit.createSession,
              ),
              mainPane: _CodeLabMainPane(state: state, cubit: cubit),
              inspectorPane: AcpDebugLogPanel(
                entries: state.diagnostics,
                onClear: cubit.clearDiagnostics,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeLabCommandBar extends StatelessWidget {
  const _CodeLabCommandBar({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text('CodeLab', style: FluentTheme.of(context).typography.subtitle),
            const SizedBox(width: 16),
            Expanded(
              child: AcpConnectionStatusRow(
                status: state.connectionStatus,
                transportLabel: state.transportLabel,
                profileLabel: state.profileLabel,
                detail: state.connectionDetail,
              ),
            ),
            const SizedBox(width: 8),
            AcpButton(
              label: 'Connect',
              icon: FluentIcons.plug_connected,
              emphasis: AcpButtonEmphasis.primary,
              onPressed: cubit.connect,
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeLabMainPane extends StatelessWidget {
  const _CodeLabMainPane({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: state.transcriptEntries.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
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
                          onEditProfile: cubit.editProfile,
                        ),
                      ),
                    );
                  },
                )
              : AcpTranscriptPanel(
                  entries: state.transcriptEntries,
                  viewMode: state.viewMode,
                ),
        ),
        const SizedBox(height: 12),
        AcpPromptComposer(
          enabled: state.isPromptEnabled,
          isSubmitting: state.isPromptSubmitting,
          canCancel: state.canCancel,
          onSubmit: cubit.submitPrompt,
          onCancel: cubit.cancelTurn,
        ),
      ],
    );
  }
}
