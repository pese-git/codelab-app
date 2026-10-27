import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import '../atomics/atomics.dart';

typedef CodeLabApprovalOptionSelected = void Function(String optionId);

/// Mirrors the ACP protocol's `PermissionOptionKind` — a hint for choosing
/// keyboard shortcuts and UI treatment, independent of the option's
/// agent-provided [CodeLabApprovalOption.label] text (which may be in any
/// language and is not a reliable source for that decision).
enum CodeLabApprovalOptionKind {
  allowOnce('allow_once'),
  allowAlways('allow_always'),
  rejectOnce('reject_once'),
  rejectAlways('reject_always');

  const CodeLabApprovalOptionKind(this.wireName);

  /// Значение `PermissionOptionKind` в ACP (`allow_once` и так далее).
  final String wireName;
}

/// Ключ кнопки варианта одобрения по его виду.
///
/// Почему: по ACP `name` варианта — свободный текст агента (`Allow always`
/// у одного, `Always allow <pattern>` у другого), смысл несёт только `kind`.
/// Для чего: тесты и автоматизация находят вариант по виду, не завися от
/// подписи агента. Как использовать: `find.byKey(approvalOptionKey(
/// CodeLabApprovalOptionKind.allowAlways))`; ключ стоит на кнопке в обеих
/// [CodeLabApprovalOptionGroup] и на кнопке или пункте меню строки решения
/// в ленте. Если агент прислал два варианта одного вида, ключ найдёт оба.
ValueKey<String> approvalOptionKey(CodeLabApprovalOptionKind kind) =>
    ValueKey('approval-option-${kind.wireName}');

class CodeLabApprovalOption {
  const CodeLabApprovalOption({
    required this.id,
    required this.label,
    required this.kind,
    this.description,
    this.tone = CodeLabTone.neutral,
  });

  final String id;
  final String label;
  final CodeLabApprovalOptionKind kind;
  final String? description;
  final CodeLabTone tone;
}

class CodeLabApprovalOptionGroup extends StatelessWidget {
  const CodeLabApprovalOptionGroup({
    required this.options,
    required this.onSelected,
    this.selectedOptionId,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
    super.key,
  });

  final List<CodeLabApprovalOption> options;
  final String? selectedOptionId;
  final CodeLabApprovalOptionSelected onSelected;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;

  @override
  Widget build(BuildContext context) {
    final shortcuts = CodeLabApprovalShortcuts(
      options,
      approveOptionId: approveOptionId,
      rejectOptionId: rejectOptionId,
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options) ...[
          _AcpApprovalOptionTile(
            key: approvalOptionKey(option.kind),
            option: option,
            selected: option.id == selectedOptionId,
            enabled: enabled,
            onSelected: () => onSelected(option.id),
          ),
          if (option != options.last) const SizedBox(height: 8),
        ],
      ],
    );

    if (!shortcutsEnabled) {
      return body;
    }

    return CallbackShortcuts(
      bindings: shortcuts.bindings(_selectIfEnabled),
      child: Focus(autofocus: true, child: body),
    );
  }

  void _selectIfEnabled(String optionId) {
    if (!enabled) {
      return;
    }

    onSelected(optionId);
  }
}

/// Сочетания клавиш вариантов одобрения по их виду.
///
/// Почему: сочетание выбирается по `PermissionOptionKind`, а не по подписи
/// агента (требование «Approval options are rendered and bound to shortcuts
/// by kind»). Строка решения в ленте показывает кнопками только два
/// варианта, остальные — в меню, а сочетания всех четырёх должны работать
/// без открытия меню (change `lighten-approval-block`, D2). Поэтому выбор
/// варианта по виду и привязка вынесены из [CodeLabApprovalOptionGroup] в
/// одно место.
///
/// Для чего: какой вариант отвечает на какое сочетание, подсказка сочетания
/// для кнопки или пункта меню и таблица привязок для `CallbackShortcuts`.
///
/// Как использовать: создать по списку вариантов
/// (`CodeLabApprovalShortcuts(options)`), подсказку брать через
/// [labelFor], привязки — `CallbackShortcuts(bindings:
/// shortcuts.bindings(select))`. [approveOptionId] и [rejectOptionId]
/// подменяют варианты `allow_once` и `reject_once`, если владелец выбрал их
/// сам.
final class CodeLabApprovalShortcuts {
  CodeLabApprovalShortcuts(
    List<CodeLabApprovalOption> options, {
    String? approveOptionId,
    String? rejectOptionId,
  }) : allowOnceId =
           approveOptionId ??
           _idForKind(options, CodeLabApprovalOptionKind.allowOnce),
       allowAlwaysId = _idForKind(
         options,
         CodeLabApprovalOptionKind.allowAlways,
       ),
       rejectOnceId =
           rejectOptionId ??
           _idForKind(options, CodeLabApprovalOptionKind.rejectOnce),
       rejectAlwaysId = _idForKind(
         options,
         CodeLabApprovalOptionKind.rejectAlways,
       );

  final String? allowOnceId;
  final String? allowAlwaysId;
  final String? rejectOnceId;
  final String? rejectAlwaysId;

  /// Подсказка сочетания для варианта [optionId] в обозначениях платформы;
  /// `null` — у варианта нет сочетания.
  String? labelFor(String optionId) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final mod = isMac ? '⌘' : 'Ctrl+';
    final alt = isMac ? '⌥' : 'Alt+';

    if (optionId == allowOnceId) return '$mod⏎';
    if (optionId == allowAlwaysId) return '$alt$mod⏎';
    if (optionId == rejectOnceId) return '$mod⌫';
    if (optionId == rejectAlwaysId) return '$alt$mod⌫';
    return null;
  }

  /// Привязки сочетаний к [select]; Ctrl и ⌘ равноправны на всех
  /// платформах.
  Map<ShortcutActivator, VoidCallback> bindings(
    void Function(String optionId) select,
  ) {
    void bind(
      Map<ShortcutActivator, VoidCallback> map,
      String? optionId,
      LogicalKeyboardKey key, {
      bool alt = false,
    }) {
      if (optionId == null) {
        return;
      }
      map[SingleActivator(key, control: true, alt: alt)] = () =>
          select(optionId);
      map[SingleActivator(key, meta: true, alt: alt)] = () => select(optionId);
    }

    final map = <ShortcutActivator, VoidCallback>{};
    bind(map, allowOnceId, LogicalKeyboardKey.enter);
    bind(map, allowAlwaysId, LogicalKeyboardKey.enter, alt: true);
    bind(map, rejectOnceId, LogicalKeyboardKey.backspace);
    bind(map, rejectAlwaysId, LogicalKeyboardKey.backspace, alt: true);
    return map;
  }

  static String? _idForKind(
    List<CodeLabApprovalOption> options,
    CodeLabApprovalOptionKind kind,
  ) {
    for (final option in options) {
      if (option.kind == kind) {
        return option.id;
      }
    }
    return null;
  }
}

class _AcpApprovalOptionTile extends StatelessWidget {
  const _AcpApprovalOptionTile({
    required this.option,
    super.key,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final CodeLabApprovalOption option;
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
                        child: CodeLabText(
                          option.label,
                          role: CodeLabTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (option.tone != CodeLabTone.neutral) ...[
                        const SizedBox(width: 8),
                        CodeLabBadge(
                          label: _toneLabel(option.tone),
                          tone: option.tone,
                        ),
                      ],
                    ],
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 4),
                    CodeLabText(
                      option.description!,
                      role: CodeLabTextRole.caption,
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

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return const SizedBox(height: 22);
    }

    return const CodeLabBadge(label: 'Selected', tone: CodeLabTone.success);
  }
}

String _toneLabel(CodeLabTone tone) {
  return switch (tone) {
    CodeLabTone.neutral => 'Info',
    CodeLabTone.accent => 'Option',
    CodeLabTone.success => 'Safe',
    CodeLabTone.warning => 'Review',
    CodeLabTone.danger => 'Risk',
  };
}
