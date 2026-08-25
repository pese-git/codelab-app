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
              inspectorPane: _CodeLabInspectorPane(state: state, cubit: cubit),
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
              key: const ValueKey('command-bar-connect'),
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

class _CodeLabInspectorPane extends StatelessWidget {
  const _CodeLabInspectorPane({required this.state, required this.cubit});

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: AcpText('Inspector', role: AcpTextRole.subtitle),
                ),
                AcpIconButton(
                  icon: FluentIcons.clear,
                  tooltip: 'Clear diagnostics',
                  onPressed: cubit.clearDiagnostics,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final entry in state.inspectorEntries) ...[
                  _InspectorEntryCard(entry: entry),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 260,
                  child: AcpDebugLogPanel(
                    entries: state.diagnostics,
                    onClear: cubit.clearDiagnostics,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorEntryCard extends StatelessWidget {
  const _InspectorEntryCard({required this.entry});

  final CodeLabInspectorEntry entry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _toneColor.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _toneColor.withAlpha(56)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AcpBadge(label: _categoryLabel, tone: _tone),
                const SizedBox(width: 8),
                Expanded(
                  child: AcpText(
                    entry.title,
                    role: AcpTextRole.strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AcpText(
              entry.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (entry.risk != null || entry.status != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (entry.risk != null)
                    AcpBadge(label: 'Risk ${entry.risk}', tone: _riskTone),
                  if (entry.status != null)
                    AcpBadge(label: entry.status!, tone: AcpTone.neutral),
                ],
              ),
            ],
            if (entry.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final detail in entry.details)
                _InspectorDetailLine(detail: detail),
            ],
            if (entry.rawInput != null) ...[
              const SizedBox(height: 8),
              _InspectorRawBlock(label: 'Raw input', value: entry.rawInput!),
            ],
            if (entry.rawOutput != null) ...[
              const SizedBox(height: 8),
              _InspectorRawBlock(label: 'Raw output', value: entry.rawOutput!),
            ],
          ],
        ),
      ),
    );
  }

  String get _categoryLabel {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => 'Approval',
      CodeLabInspectorCategory.toolCall => 'Tool',
      CodeLabInspectorCategory.protocol => 'Protocol',
      CodeLabInspectorCategory.diagnostic => 'Diagnostic',
    };
  }

  AcpTone get _tone {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => AcpTone.warning,
      CodeLabInspectorCategory.toolCall => AcpTone.accent,
      CodeLabInspectorCategory.protocol => AcpTone.neutral,
      CodeLabInspectorCategory.diagnostic => AcpTone.danger,
    };
  }

  AcpTone get _riskTone {
    return switch (entry.risk) {
      'readOnly' => AcpTone.success,
      'localWrite' || 'network' => AcpTone.warning,
      'shell' || 'destructive' => AcpTone.danger,
      _ => AcpTone.neutral,
    };
  }

  Color get _toneColor {
    return switch (entry.category) {
      CodeLabInspectorCategory.approval => Colors.orange,
      CodeLabInspectorCategory.toolCall => Colors.blue,
      CodeLabInspectorCategory.protocol => Colors.grey,
      CodeLabInspectorCategory.diagnostic => Colors.red,
    };
  }
}

class _InspectorDetailLine extends StatelessWidget {
  const _InspectorDetailLine({required this.detail});

  final CodeLabInspectorDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: AcpText(detail.label, role: AcpTextRole.caption),
          ),
          Expanded(
            child: AcpText(
              detail.value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorRawBlock extends StatelessWidget {
  const _InspectorRawBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AcpText(label, role: AcpTextRole.caption),
            const SizedBox(height: 4),
            AcpText(value, maxLines: 8, overflow: TextOverflow.ellipsis),
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
        if (state.pendingApproval case final approval?) ...[
          const SizedBox(height: 12),
          AcpApprovalPanel(
            title: approval.title,
            risk: approval.risk,
            options: approval.options,
            command: approval.command,
            cwd: approval.cwd,
            enabled: !state.isRespondingToApproval,
            onOptionSelected: cubit.respondToApproval,
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
