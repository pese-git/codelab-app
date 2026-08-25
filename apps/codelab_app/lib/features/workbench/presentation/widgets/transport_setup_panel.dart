import 'package:acp_ui/acp_ui.dart';
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
