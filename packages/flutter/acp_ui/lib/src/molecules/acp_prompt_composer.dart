import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

typedef AcpPromptSubmitCallback = void Function(String prompt);

class AcpPromptComposer extends StatefulWidget {
  const AcpPromptComposer({
    required this.onSubmit,
    this.onCancel,
    this.initialPrompt = '',
    this.placeholder = 'Message the agent',
    this.isSubmitting = false,
    this.canCancel = false,
    this.enabled = true,
    super.key,
  });

  final AcpPromptSubmitCallback onSubmit;
  final VoidCallback? onCancel;
  final String initialPrompt;
  final String placeholder;
  final bool isSubmitting;
  final bool canCancel;
  final bool enabled;

  @override
  State<AcpPromptComposer> createState() => _AcpPromptComposerState();
}

class _AcpPromptComposerState extends State<AcpPromptComposer> {
  late final TextEditingController _controller;

  bool get _canSubmit =>
      widget.enabled &&
      !widget.isSubmitting &&
      _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(AcpPromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPrompt != widget.initialPrompt &&
        widget.initialPrompt != _controller.text) {
      _controller.text = widget.initialPrompt;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).micaBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(64)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextBox(
                controller: _controller,
                enabled: widget.enabled && !widget.isSubmitting,
                minLines: 1,
                maxLines: 4,
                placeholder: widget.placeholder,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            AcpButton(
              label: 'Send',
              icon: FluentIcons.send,
              emphasis: AcpButtonEmphasis.primary,
              isLoading: widget.isSubmitting,
              onPressed: _canSubmit ? _submit : null,
            ),
            if (widget.onCancel != null && widget.canCancel) ...[
              const SizedBox(width: 8),
              AcpButton(
                label: 'Cancel',
                icon: FluentIcons.cancel,
                onPressed: widget.enabled ? widget.onCancel : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleTextChanged() => setState(() {});

  void _submit() {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || widget.isSubmitting || !widget.enabled) {
      return;
    }

    widget.onSubmit(prompt);
    _controller.clear();
  }
}
