import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/shell_cubit.dart';

class TransportSetupPanel extends StatelessWidget {
  const TransportSetupPanel({
    required this.state,
    required this.cubit,
    super.key,
  });

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
            // Wrap, а не Row: три кнопки типов не помещаются в узком диалоге
            // (640 px) в одну строку.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Transport', style: theme.typography.bodyStrong),
                CodeLabButton(
                  label: 'stdio',
                  icon: FluentIcons.command_prompt,
                  emphasis: state.transportType == CodeLabTransportType.stdio
                      ? CodeLabButtonEmphasis.primary
                      : CodeLabButtonEmphasis.secondary,
                  onPressed: () =>
                      cubit.selectTransport(CodeLabTransportType.stdio),
                ),
                CodeLabButton(
                  label: 'WebSocket',
                  icon: FluentIcons.plug,
                  emphasis:
                      state.transportType == CodeLabTransportType.webSocket
                      ? CodeLabButtonEmphasis.primary
                      : CodeLabButtonEmphasis.secondary,
                  onPressed: () =>
                      cubit.selectTransport(CodeLabTransportType.webSocket),
                ),
                CodeLabButton(
                  label: CodeLabTransportType.embedded.label,
                  icon: FluentIcons.robot,
                  emphasis: state.transportType == CodeLabTransportType.embedded
                      ? CodeLabButtonEmphasis.primary
                      : CodeLabButtonEmphasis.secondary,
                  onPressed: () =>
                      cubit.selectTransport(CodeLabTransportType.embedded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            switch (state.transportType) {
              CodeLabTransportType.stdio => _StdioTransportFields(
                state: state,
                cubit: cubit,
              ),
              CodeLabTransportType.webSocket => _WebSocketTransportFields(
                state: state,
                cubit: cubit,
              ),
              CodeLabTransportType.embedded => const _EmbeddedTransportNote(),
            },
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
        _TransportTextField(
          label: 'Args',
          value: state.stdioArgs,
          onChanged: cubit.updateStdioArgs,
        ),
        const SizedBox(height: 8),
        _TransportTextField(
          label: 'Environment',
          value: state.stdioEnv,
          minLines: 1,
          maxLines: 2,
          onChanged: cubit.updateStdioEnv,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Run agent from project directory',
                style: FluentTheme.of(context).typography.body,
              ),
            ),
            ToggleSwitch(
              key: const ValueKey('run-agent-from-project-directory-toggle'),
              checked: state.runAgentFromProjectDirectory,
              onChanged: cubit.toggleRunAgentFromProjectDirectory,
            ),
          ],
        ),
      ],
    );
  }
}

/// У встроенного агента нет полей: проект выбирается «Open Project», а
/// конфигурацию агент читает сам (design.md change `add-embedded-agent-mode`,
/// D9). Подсказка говорит, где её искать, чтобы отказ подключения из-за
/// конфигурации не был неожиданным.
class _EmbeddedTransportNote extends StatelessWidget {
  const _EmbeddedTransportNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'The agent runs inside CodeLab, without a child process. '
      'Its configuration is read from \$CODELAB_HOME/config.yaml and '
      'the project\'s .codelab/config.yaml.',
      style: FluentTheme.of(context).typography.caption,
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
