import 'dart:convert';

import '../loop/turn_budget.dart';
import 'subagent_model.dart';

/// Отчёт ребёнка для модели родителя и для журнала (`agent-core/
/// 17-3-subagents.md` §17.3.5; design.md change `add-subagents-and-tasks`,
/// D24).

/// Текст, который видит модель родителя: один блок `<subagent-report …>`.
///
/// Почему такая обёртка: отчёт — пересказ того, что ребёнок прочёл в файлах и
/// выводе команд, поэтому он остаётся недоверенным; общая ограда
/// `untrusted-content source="agent"` ставится единой точкой исполнения, а
/// здесь экранируются вхождения `</subagent-report` (SUB-7), чтобы текст
/// отчёта не закрыл обёртку.
///
/// Атрибуты идут в фиксированном порядке: `id`, `agent`, `status`, `steps`,
/// `tool_calls`, затем `truncated` или `reason`. [withSteps] `false` — у
/// отчёта, восстановленного из записи журнала, числа шагов нет.
String wrapSubagentReport(SubagentReport report, {bool withSteps = true}) {
  final reason = switch (report.failure) {
    null => null,
    SubagentFailure.budgetExceeded => failureWire(
      report.failure,
      report.budgetExceeded,
    ),
    SubagentFailure.invalidOutput => 'invalid_output',
    SubagentFailure.refused => 'refused',
    SubagentFailure.error || SubagentFailure.interrupted => 'error',
  };
  final body = switch ((report.status, report.failure)) {
    (SubagentState.completed, _) => report.text,
    (_, SubagentFailure.budgetExceeded) =>
      report.text.isEmpty
          ? 'Subagent stopped: its budget was exhausted before it finished.'
          : report.text,
    (SubagentState.failed, _) =>
      'Subagent failed: ${report.failureMessage ?? report.text}',
    _ => 'Tool call was cancelled',
  };
  final attributes = [
    'id="${_attribute(report.id)}"',
    'agent="${_attribute(report.agent)}"',
    'status="${report.status.name}"',
    if (withSteps) 'steps="${report.steps}"',
    'tool_calls="${report.toolCalls}"',
    if (report.truncated) 'truncated="true"',
    if (reason != null) 'reason="${_attribute(reason)}"',
  ];
  final escaped = body.replaceAllMapped(
    RegExp(r'</subagent-report', caseSensitive: false),
    (m) => '&lt;${m[0]!.substring(1)}',
  );
  return '<subagent-report ${attributes.join(' ')}>\n$escaped\n'
      '</subagent-report>';
}

String _attribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

/// Усекает [text] до [maxBytes] байт UTF-8 по границе строки и дописывает
/// пометку (§17.3.5, шаг 4). Возвращает исходный текст, если он помещается.
({String text, bool truncated}) truncateReport(String text, int maxBytes) {
  final total = utf8.encode(text).length;
  if (total <= maxBytes) {
    return (text: text, truncated: false);
  }
  var shown = '';
  var shownBytes = 0;
  for (final line in text.split('\n')) {
    final bytes = utf8.encode(shown.isEmpty ? line : '\n$line').length;
    if (shownBytes + bytes > maxBytes) {
      break;
    }
    shown = shown.isEmpty ? line : '$shown\n$line';
    shownBytes += bytes;
  }
  if (shown.isEmpty) {
    // Первая строка длиннее предела: режем по символам.
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final next = utf8.encode(String.fromCharCode(rune)).length;
      if (shownBytes + next > maxBytes) {
        break;
      }
      buffer.writeCharCode(rune);
      shownBytes += next;
    }
    shown = buffer.toString();
  }
  return (
    text:
        '$shown\n[report truncated: $shownBytes of $total bytes shown; the '
        'full report is in the subagent journal]',
    truncated: true,
  );
}

/// `failure` из записи журнала (`budget_exceeded:tokens`, `interrupted`, …).
({SubagentFailure? failure, BudgetLimit? limit}) parseFailure(String? wire) {
  if (wire == null) {
    return (failure: null, limit: null);
  }
  if (wire.startsWith('budget_exceeded:')) {
    final name = wire.substring('budget_exceeded:'.length);
    return (
      failure: SubagentFailure.budgetExceeded,
      limit: BudgetLimit.values.asNameMap()[name],
    );
  }
  return (
    failure: switch (wire) {
      'invalid_output' => SubagentFailure.invalidOutput,
      'refused' => SubagentFailure.refused,
      'interrupted' => SubagentFailure.interrupted,
      _ => SubagentFailure.error,
    },
    limit: null,
  );
}

/// Значение `failure` записи `subagent` и `_meta` ACP (`17-3-subagents.md`
/// §17.3.6): `budget_exceeded:<limit>`, `invalid_output`, `error`,
/// `refused`, `interrupted`; `null` — сбоя нет.
String? failureWire(SubagentFailure? failure, BudgetLimit? limit) =>
    switch (failure) {
      null => null,
      SubagentFailure.budgetExceeded =>
        'budget_exceeded:${(limit ?? BudgetLimit.steps).name}',
      SubagentFailure.invalidOutput => 'invalid_output',
      SubagentFailure.error => 'error',
      SubagentFailure.refused => 'refused',
      SubagentFailure.interrupted => 'interrupted',
    };
