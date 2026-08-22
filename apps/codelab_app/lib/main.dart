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
        if (state.transcriptEntries.isEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TransportSetupPanel(state: state, cubit: cubit),
                      const SizedBox(height: 12),
                      _CurrentSessionPanel(state: state),
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
                          onEditProfile: cubit.editProfile,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        else ...[
          _TransportSetupPanel(state: state, cubit: cubit),
          const SizedBox(height: 12),
          _CurrentSessionPanel(state: state),
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
          onSubmit: cubit.submitPrompt,
          onCancel: cubit.cancelTurn,
        ),
      ],
    );
  }
}

class _CurrentSessionPanel extends StatelessWidget {
  const _CurrentSessionPanel({required this.state});

  final CodeLabShellState state;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(FluentIcons.chat, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.currentSessionLabel,
                    style: theme.typography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.currentSessionDetail,
                    style: theme.typography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportSetupPanel extends StatelessWidget {
  const _TransportSetupPanel({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.micaBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Transport', style: theme.typography.bodyStrong),
                const SizedBox(width: 12),
                AcpButton(
                  label: 'stdio',
                  icon: FluentIcons.command_prompt,
                  emphasis: state.transportType == CodeLabTransportType.stdio
                      ? AcpButtonEmphasis.primary
                      : AcpButtonEmphasis.secondary,
                  onPressed: () =>
                      cubit.selectTransport(CodeLabTransportType.stdio),
                ),
                const SizedBox(width: 8),
                AcpButton(
                  label: 'WebSocket',
                  icon: FluentIcons.plug,
                  emphasis:
                      state.transportType == CodeLabTransportType.webSocket
                      ? AcpButtonEmphasis.primary
                      : AcpButtonEmphasis.secondary,
                  onPressed: () =>
                      cubit.selectTransport(CodeLabTransportType.webSocket),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.transportType == CodeLabTransportType.stdio)
              _StdioTransportFields(state: state, cubit: cubit)
            else
              _WebSocketTransportFields(state: state, cubit: cubit),
          ],
        ),
      ),
    );
  }
}

class _StdioTransportFields extends StatelessWidget {
  const _StdioTransportFields({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TransportTextField(
                label: 'Profile',
                value: state.stdioProfileName,
                onChanged: cubit.updateStdioProfileName,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TransportTextField(
                label: 'Command',
                value: state.stdioCommand,
                onChanged: cubit.updateStdioCommand,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TransportTextField(
                label: 'Args',
                value: state.stdioArgs,
                onChanged: cubit.updateStdioArgs,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TransportTextField(
                label: 'Working directory',
                value: state.stdioCwd,
                placeholder: 'Optional',
                onChanged: cubit.updateStdioCwd,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _TransportTextField(
          label: 'Environment',
          value: state.stdioEnv,
          minLines: 1,
          maxLines: 2,
          onChanged: cubit.updateStdioEnv,
        ),
      ],
    );
  }
}

class _WebSocketTransportFields extends StatelessWidget {
  const _WebSocketTransportFields({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _TransportTextField(
            label: 'Endpoint',
            value: state.webSocketEndpoint,
            onChanged: cubit.updateWebSocketEndpoint,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TransportTextField(
            label: 'Token',
            value: state.webSocketToken,
            placeholder: 'Optional',
            onChanged: cubit.updateWebSocketToken,
          ),
        ),
      ],
    );
  }
}

class _TransportTextField extends StatefulWidget {
  const _TransportTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final String? placeholder;
  final int minLines;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<_TransportTextField> createState() => _TransportTextFieldState();
}

class _TransportTextFieldState extends State<_TransportTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TransportTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: FluentTheme.of(context).typography.caption),
        const SizedBox(height: 4),
        TextBox(
          key: ValueKey('transport-field-${widget.label}'),
          controller: _controller,
          placeholder: widget.placeholder,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
