import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';

typedef AcpApprovalOptionSelected = void Function(String optionId);

/// How [AcpApprovalOptionGroup] arranges its options.
///
/// `list` (default) is the full-detail vertical list — selection badge
/// column, tone badge, description — used for the standalone/docked
/// [AcpApprovalPanel]. `compactRow` is the dense horizontal row (label +
/// real shortcut hint, no description) used when the panel is embedded
/// inline in a transcript entry, where vertical space is at a premium —
/// see embed-approval-in-thread/design.md.
enum AcpApprovalOptionsLayout { list, compactRow }

/// Mirrors the ACP protocol's `PermissionOptionKind` — a hint for choosing
/// keyboard shortcuts and UI treatment, independent of the option's
/// agent-provided [AcpApprovalOption.label] text (which may be in any
/// language and is not a reliable source for that decision).
enum AcpApprovalOptionKind { allowOnce, allowAlways, rejectOnce, rejectAlways }

class AcpApprovalOption {
  const AcpApprovalOption({
    required this.id,
    required this.label,
    required this.kind,
    this.description,
    this.tone = AcpTone.neutral,
  });

  final String id;
  final String label;
  final AcpApprovalOptionKind kind;
  final String? description;
  final AcpTone tone;
}

class AcpApprovalOptionGroup extends StatelessWidget {
  const AcpApprovalOptionGroup({
    required this.options,
    required this.onSelected,
    this.selectedOptionId,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
    this.layout = AcpApprovalOptionsLayout.list,
    super.key,
  });

  final List<AcpApprovalOption> options;
  final String? selectedOptionId;
  final AcpApprovalOptionSelected onSelected;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;
  final AcpApprovalOptionsLayout layout;

  @override
  Widget build(BuildContext context) {
    final allowOnceId =
        approveOptionId ?? _idForKind(AcpApprovalOptionKind.allowOnce);
    final allowAlwaysId = _idForKind(AcpApprovalOptionKind.allowAlways);
    final rejectOnceId =
        rejectOptionId ?? _idForKind(AcpApprovalOptionKind.rejectOnce);
    final rejectAlwaysId = _idForKind(AcpApprovalOptionKind.rejectAlways);
    final showShortcutHints = shortcutsEnabled;

    final body = switch (layout) {
      AcpApprovalOptionsLayout.list => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options) ...[
            _AcpApprovalOptionTile(
              option: option,
              selected: option.id == selectedOptionId,
              enabled: enabled,
              onSelected: () => onSelected(option.id),
            ),
            if (option != options.last) const SizedBox(height: 8),
          ],
        ],
      ),
      AcpApprovalOptionsLayout.compactRow => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in options) ...[
              Expanded(
                child: _AcpApprovalCompactOptionButton(
                  option: option,
                  selected: option.id == selectedOptionId,
                  enabled: enabled,
                  shortcutLabel: !showShortcutHints
                      ? null
                      : _shortcutLabelFor(
                          option.id,
                          allowOnceId: allowOnceId,
                          allowAlwaysId: allowAlwaysId,
                          rejectOnceId: rejectOnceId,
                          rejectAlwaysId: rejectAlwaysId,
                        ),
                  onSelected: () => onSelected(option.id),
                ),
              ),
              if (option != options.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    };

    if (!shortcutsEnabled) {
      return body;
    }

    return CallbackShortcuts(
      bindings: {
        if (allowOnceId != null) ...{
          SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              _selectIfEnabled(allowOnceId),
          SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
              _selectIfEnabled(allowOnceId),
        },
        if (allowAlwaysId != null) ...{
          SingleActivator(
            LogicalKeyboardKey.enter,
            control: true,
            alt: true,
          ): () =>
              _selectIfEnabled(allowAlwaysId),
          SingleActivator(
            LogicalKeyboardKey.enter,
            meta: true,
            alt: true,
          ): () =>
              _selectIfEnabled(allowAlwaysId),
        },
        if (rejectOnceId != null) ...{
          SingleActivator(LogicalKeyboardKey.backspace, control: true): () =>
              _selectIfEnabled(rejectOnceId),
          SingleActivator(LogicalKeyboardKey.backspace, meta: true): () =>
              _selectIfEnabled(rejectOnceId),
        },
        if (rejectAlwaysId != null) ...{
          SingleActivator(
            LogicalKeyboardKey.backspace,
            control: true,
            alt: true,
          ): () =>
              _selectIfEnabled(rejectAlwaysId),
          SingleActivator(
            LogicalKeyboardKey.backspace,
            meta: true,
            alt: true,
          ): () =>
              _selectIfEnabled(rejectAlwaysId),
        },
      },
      child: Focus(autofocus: true, child: body),
    );
  }

  String? _idForKind(AcpApprovalOptionKind kind) {
    for (final option in options) {
      if (option.kind == kind) {
        return option.id;
      }
    }

    return null;
  }

  String? _shortcutLabelFor(
    String optionId, {
    required String? allowOnceId,
    required String? allowAlwaysId,
    required String? rejectOnceId,
    required String? rejectAlwaysId,
  }) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final mod = isMac ? '⌘' : 'Ctrl+';
    final alt = isMac ? '⌥' : 'Alt+';

    if (optionId == allowOnceId) return '$mod⏎';
    if (optionId == allowAlwaysId) return '$alt$mod⏎';
    if (optionId == rejectOnceId) return '$mod⌫';
    if (optionId == rejectAlwaysId) return '$alt$mod⌫';
    return null;
  }

  void _selectIfEnabled(String optionId) {
    if (!enabled) {
      return;
    }

    onSelected(optionId);
  }
}

class _AcpApprovalOptionTile extends StatelessWidget {
  const _AcpApprovalOptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final AcpApprovalOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: enabled ? onSelected : null,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 58, child: _SelectionBadge(selected: selected)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AcpText(
                          option.label,
                          role: AcpTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (option.tone != AcpTone.neutral) ...[
                        const SizedBox(width: 8),
                        AcpBadge(
                          label: _toneLabel(option.tone),
                          tone: option.tone,
                        ),
                      ],
                    ],
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 4),
                    AcpText(
                      option.description!,
                      role: AcpTextRole.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dense horizontal button used by [AcpApprovalOptionsLayout.compactRow]
/// — label, a real keyboard-shortcut hint (only for whichever option the
/// group actually binds `Ctrl/Cmd+Enter`/`Escape` to), and the option's tone
/// conveyed as text color rather than a separate badge (no room for one at
/// this density).
class _AcpApprovalCompactOptionButton extends StatelessWidget {
  const _AcpApprovalCompactOptionButton({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.shortcutLabel,
  });

  final AcpApprovalOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
  final String? shortcutLabel;

  @override
  Widget build(BuildContext context) {
    final toneColor = _toneForegroundColor(option.tone);

    return Button(
      onPressed: enabled ? onSelected : null,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: selected ? BorderSide(color: Colors.blue) : BorderSide.none,
          ),
        ),
        backgroundColor: !selected
            ? null
            : WidgetStateProperty.all(Colors.blue.withAlpha(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AcpText(
              option.label,
              role: AcpTextRole.strong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: toneColor,
            ),
            if (shortcutLabel != null) ...[
              const SizedBox(height: 3),
              AcpText(shortcutLabel!, role: AcpTextRole.caption),
            ],
          ],
        ),
      ),
    );
  }
}

Color? _toneForegroundColor(AcpTone tone) {
  return switch (tone) {
    AcpTone.neutral => null,
    AcpTone.accent => Colors.blue,
    AcpTone.success => Colors.green,
    AcpTone.warning => Colors.warningPrimaryColor,
    AcpTone.danger => Colors.red,
  };
}

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return const SizedBox(height: 22);
    }

    return const AcpBadge(label: 'Selected', tone: AcpTone.success);
  }
}

String _toneLabel(AcpTone tone) {
  return switch (tone) {
    AcpTone.neutral => 'Info',
    AcpTone.accent => 'Option',
    AcpTone.success => 'Safe',
    AcpTone.warning => 'Review',
    AcpTone.danger => 'Risk',
  };
}
