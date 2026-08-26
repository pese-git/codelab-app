import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';
import '../organisms/acp_command_palette_surface.dart';
import 'acp_command_action.dart';

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
    this.shortcutsEnabled = true,
    this.commandActions = const [],
    this.onCommandSelected,
    super.key,
  });

  static const inlineCommandPaletteKey = ValueKey(
    'composer-inline-command-palette',
  );

  final AcpPromptSubmitCallback onSubmit;
  final VoidCallback? onCancel;
  final String initialPrompt;
  final String placeholder;
  final bool isSubmitting;
  final bool canCancel;
  final bool enabled;
  final bool shortcutsEnabled;

  /// Commands available for the inline `/` trigger. An empty list (the
  /// default) disables the trigger entirely, preserving prior behavior for
  /// callers that don't opt in.
  final List<AcpCommandAction> commandActions;

  /// Called when the user selects an available command from the inline
  /// palette. The `/word` fragment that triggered it has already been
  /// removed from the composer text by the time this fires.
  final ValueChanged<AcpCommandAction>? onCommandSelected;

  @override
  State<AcpPromptComposer> createState() => _AcpPromptComposerState();
}

class _AcpPromptComposerState extends State<AcpPromptComposer> {
  late final TextEditingController _controller;
  late final FocusNode _textFocusNode;
  int? _triggerStart;
  int _selectedIndex = 0;

  bool get _canSubmit =>
      widget.enabled &&
      !widget.isSubmitting &&
      _controller.text.trim().isNotEmpty;

  bool get _inlineTriggerEnabled =>
      widget.commandActions.isNotEmpty && widget.onCommandSelected != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
    _controller.addListener(_handleTextChanged);
    _textFocusNode = FocusNode();
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
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCommands = _filteredCommandActions();
    final showInlinePalette = _inlineTriggerEnabled && _triggerStart != null;
    final selectedIndex = filteredCommands.isEmpty
        ? -1
        : _selectedIndex.clamp(0, filteredCommands.length - 1);

    final body = DecoratedBox(
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
                key: const ValueKey('composer-text-box'),
                controller: _controller,
                focusNode: _textFocusNode,
                enabled: widget.enabled && !widget.isSubmitting,
                minLines: 1,
                maxLines: 4,
                placeholder: widget.placeholder,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            AcpButton(
              key: const ValueKey('composer-send-button'),
              label: 'Send',
              icon: FluentIcons.send,
              emphasis: AcpButtonEmphasis.primary,
              isLoading: widget.isSubmitting,
              onPressed: _canSubmit ? _submit : null,
            ),
            if (widget.onCancel != null && widget.canCancel) ...[
              const SizedBox(width: 8),
              AcpButton(
                key: const ValueKey('composer-cancel-button'),
                label: 'Cancel',
                icon: FluentIcons.cancel,
                onPressed: widget.enabled ? widget.onCancel : null,
              ),
            ],
          ],
        ),
      ),
    );

    final shortcutBoundBody = widget.shortcutsEnabled
        ? CallbackShortcuts(
            bindings: _shortcutBindings(showInlinePalette, filteredCommands),
            child: Focus(autofocus: true, child: body),
          )
        : body;

    if (!showInlinePalette) {
      return shortcutBoundBody;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AcpCommandPaletteSurface(
            key: AcpPromptComposer.inlineCommandPaletteKey,
            actions: widget.commandActions,
            showSearchField: false,
            queryOverride: _activeQuery(),
            selectedActionId: selectedIndex < 0
                ? null
                : filteredCommands[selectedIndex].id,
            onActionSelected: _handlePaletteSelection,
          ),
        ),
        shortcutBoundBody,
      ],
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings(
    bool showInlinePalette,
    List<AcpCommandAction> filteredCommands,
  ) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
    };

    if (showInlinePalette) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter)] = () =>
          _handleInlineEnter(filteredCommands);
      bindings[const SingleActivator(LogicalKeyboardKey.arrowDown)] = () =>
          _moveInlineSelection(1, filteredCommands.length);
      bindings[const SingleActivator(LogicalKeyboardKey.arrowUp)] = () =>
          _moveInlineSelection(-1, filteredCommands.length);
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] =
          _closeInlinePalette;
    } else if (widget.onCancel != null && widget.canCancel) {
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] = _cancel;
    }

    return bindings;
  }

  void _handleTextChanged() {
    if (_inlineTriggerEnabled) {
      final detected = _detectTriggerStart();
      if (detected != _triggerStart) {
        _selectedIndex = 0;
      }
      _triggerStart = detected;
    }
    setState(() {});
  }

  /// Scans backward from the cursor for an active `/` trigger: a slash
  /// that starts the composer text or is immediately preceded by
  /// whitespace, with no whitespace between it and the cursor. Recomputing
  /// this from scratch on every keystroke (rather than tracking an index
  /// across edits) means deleting the triggering slash, or typing a space
  /// that ends the word, is detected automatically without extra bookkeeping.
  int? _detectTriggerStart() {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      return null;
    }

    var index = cursor - 1;
    while (index >= 0) {
      final char = text[index];
      if (char == '/') {
        break;
      }
      if (_isWhitespace(char)) {
        return null;
      }
      index -= 1;
    }

    if (index < 0 || text[index] != '/') {
      return null;
    }
    if (index > 0 && !_isWhitespace(text[index - 1])) {
      return null;
    }

    return index;
  }

  bool _isWhitespace(String char) =>
      char == ' ' || char == '\n' || char == '\t';

  String _activeQuery() {
    final start = _triggerStart;
    if (start == null) {
      return '';
    }

    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final end = (cursor < 0 ? text.length : cursor).clamp(start, text.length);
    return text.substring(start, end);
  }

  List<AcpCommandAction> _filteredCommandActions() {
    if (_triggerStart == null) {
      return const [];
    }
    return AcpCommandAction.filter(widget.commandActions, _activeQuery());
  }

  void _moveInlineSelection(int delta, int length) {
    if (length == 0) {
      return;
    }
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % length;
      if (_selectedIndex < 0) {
        _selectedIndex += length;
      }
    });
  }

  void _handleInlineEnter(List<AcpCommandAction> filteredCommands) {
    if (filteredCommands.isEmpty) {
      return;
    }
    final index = _selectedIndex.clamp(0, filteredCommands.length - 1);
    _handlePaletteSelection(filteredCommands[index]);
  }

  void _handlePaletteSelection(AcpCommandAction action) {
    if (!action.isAvailable) {
      // Unavailable commands stay highlighted-but-inert: the palette stays
      // open, the composer text is untouched, and nothing is emitted.
      return;
    }

    final start = _triggerStart;
    if (start == null) {
      return;
    }

    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final end = (cursor < 0 ? text.length : cursor).clamp(start, text.length);
    final newText = text.replaceRange(start, end, '');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
    );
    _triggerStart = null;
    _textFocusNode.requestFocus();
    widget.onCommandSelected?.call(action);
  }

  void _closeInlinePalette() {
    setState(() {
      _triggerStart = null;
    });
  }

  void _submit() {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || widget.isSubmitting || !widget.enabled) {
      return;
    }

    widget.onSubmit(prompt);
    _controller.clear();
  }

  void _cancel() {
    if (!widget.enabled || !widget.canCancel) {
      return;
    }

    widget.onCancel?.call();
  }
}
