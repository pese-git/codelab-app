import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../render/sanitize.dart';

/// Блок одобрения в REPL и выбор варианта клавишей.
///
/// Почему: решение о действии агента принимает человек, и он должен видеть,
/// что именно разрешает, а выбрать — только из вариантов, которые предложил
/// агент; сериализованный объект аргументов в блоке не показывается, только
/// по `?` (spec codelab-cli «Одобрение в REPL»; U-02; §12.2.11, TUI-6;
/// design.md change `add-codelab-cli`, D8).
///
/// Как использовать: REPL и зона одобрения TUI строят промпт [first] на
/// первый запрос `SessionView.pendingApprovals`, показывают [block], на
/// клавишу вызывают [optionFor] и отвечают `SessionHandle.respond`; `?`
/// показывает [details]. [title] — заголовок вызова из транскрипта, [cwd] —
/// папка сессии.
final class ApprovalPrompt {
  const ApprovalPrompt(this.approval, {required this.title, required this.cwd});

  /// Промпт первого ожидающего одобрения [view]; `null` — одобрений нет.
  /// Заголовок — у вызова инструмента в транскрипте, иначе `tool call`.
  /// Общий для REPL и TUI (design.md change `add-cli-tui`, D9).
  static ApprovalPrompt? first(SessionView view, {required String cwd}) {
    final approval = view.pendingApprovals.firstOrNull;
    return approval == null
        ? null
        : ApprovalPrompt(approval, title: _titleOf(view, approval), cwd: cwd);
  }

  final PendingApprovalView approval;
  final String title;
  final String cwd;

  /// Клавиши вариантов по виду; несколько вариантов одного вида — первый.
  static const _keys = [
    ('y', PermissionOptionKind.allowOnce, 'allow once'),
    ('a', PermissionOptionKind.allowAlways, 'allow always'),
    ('n', PermissionOptionKind.rejectOnce, 'reject once'),
    ('N', PermissionOptionKind.rejectAlways, 'reject always'),
  ];

  List<String> get block {
    final command = _command();
    return [
      'Permission: ${sanitizeTerminalText(title)} '
          '(${_risk(approval.risk)}${approval.critical ? ', critical' : ''})',
      if (command != null) '  command: $command',
      '  cwd: ${sanitizeTerminalText(cwd)}',
      hint,
    ];
  }

  /// Подсказка только с клавишами предложенных вариантов.
  String get hint => [
    '  ',
    [
      for (final (key, kind, label) in _keys)
        if (approval.options.any((o) => o.kind == kind)) '[$key] $label',
      '[?] details',
      '[Esc] cancel',
    ].join('  '),
  ].join();

  /// Вариант клавиши [key]; `null` — клавиша не выбирает предложенный
  /// вариант, и отвечать нечем.
  PermissionOptionId? optionFor(String key) {
    for (final (candidate, kind, _) in _keys) {
      if (candidate == key) {
        return approval.options
            .where((o) => o.kind == kind)
            .firstOrNull
            ?.optionId;
      }
    }
    return null;
  }

  /// `rawInput` целиком, с редакцией секретов (`formatRedactedJson` kit).
  String get details =>
      sanitizeTerminalText(formatRedactedJson(approval.rawInput) ?? '{}');

  /// Команда вызова или первая строка `rawInput`, без сериализации
  /// объекта (D8).
  String? _command() {
    final command = approval.command;
    if (command != null && command.isNotEmpty) {
      return _firstLine(command);
    }
    for (final value in (approval.rawInput ?? const {}).values) {
      if (value is String && value.isNotEmpty) {
        return _firstLine(value);
      }
    }
    return null;
  }

  static String _firstLine(String text) {
    final clean = sanitizeTerminalText(text);
    final end = clean.indexOf('\n');
    return end < 0 ? clean : '${clean.substring(0, end)} …';
  }

  static String _risk(ApprovalRiskLevel risk) => switch (risk) {
    ApprovalRiskLevel.readOnly => 'read-only',
    ApprovalRiskLevel.localWrite => 'local write',
    ApprovalRiskLevel.network => 'network',
    ApprovalRiskLevel.shell => 'shell',
    ApprovalRiskLevel.destructive => 'destructive',
  };

  static String _titleOf(SessionView view, PendingApprovalView approval) {
    for (final item in view.transcript) {
      if (item case ToolCallItem(
        :final title,
        approval: PendingApprovalView(:final approvalId),
      ) when approvalId == approval.approvalId) {
        return title;
      }
    }
    return 'tool call';
  }
}
