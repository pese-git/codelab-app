import 'package:codelab_client_core/codelab_client_core.dart';

import 'sanitize.dart';

/// Строка вызова инструмента: `<значок> <название> <команда?> <время?>`.
///
/// Почему: в построчном выводе вызов должен читаться одной строкой, а
/// сериализованные аргументы (`rawInput`) в ней недопустимы — их видят
/// только по запросу (§12.2.4, §12.2.11, TUI-6; spec codelab-cli «Рендер
/// хода в REPL»; design.md change `add-codelab-cli`, D6).
///
/// Как использовать: рендер вызывает функцию, когда вызов появился и когда
/// получил итоговый статус; [elapsed] — время от появления до итога по
/// часам рендера, только для итоговой строки. [unicode] `false` — ASCII-
/// значки для терминала без UTF-8. Текст агента проходит
/// `sanitizeTerminalText`.
String toolRow(ToolCallItem item, {bool unicode = true, Duration? elapsed}) {
  final icon = _icon(_stateOf(item), unicode);
  final title = _firstLine(sanitizeTerminalText(item.title));
  final command = item.details?.command;
  final detail = command == null
      ? null
      : _firstLine(sanitizeTerminalText(command));
  // Итог субагента (D24) — в скобках сразу за заголовком и без слова «Done»;
  // у бегущего вызова и у стороннего агента без `summary` скобок нет.
  final summary = isFinalToolCall(item) && item.details?.subagentCall != null
      ? item.details?.subagentSummary?.text
      : null;
  return [
    icon,
    title,
    if (summary != null) '($summary)',
    if (detail != null && detail.isNotEmpty && !title.contains(detail)) detail,
    if (elapsed != null) _seconds(elapsed),
  ].join(' ');
}

/// Строка вызова `agent` в статусе TUI: `✓ <заголовок>  <итог>` (D24, D27).
///
/// Почему: в TUI итог стоит в самой строке статуса, а не в скобках REPL:
/// глиф ✓ и сокращённый итог без «tokens» и без слова «Done»; неуспех и
/// отмена называются явно (`Failed`, `Cancelled`), чтобы не полагаться на
/// один глиф (spec codelab-tui «Субагенты и список задач в TUI», «Итог в
/// статусе»).
///
/// Как использовать: транскрипт вызывает её для вызова с
/// `ToolCallView.subagentCall`; пока вызов идёт, в конце строки — последняя
/// строка прогресса, итога нет. Без `subagentSummary` (сторонний агент,
/// сорванный вызов) итога в строке нет. Текст агента проходит
/// `sanitizeTerminalText`.
String subagentStatusRow(ToolCallItem item, {bool unicode = true}) {
  final state = _stateOf(item);
  final row = ToolRowFormatter.format(item, cwd: '');
  // Заголовок — из kit (`Subagent <type>: <description>`), как в app, а не
  // из `title` агента.
  final title = _firstLine(
    sanitizeTerminalText('${row.label} ${row.detail}'.trim()),
  );
  final word = switch ((state, item.details?.status)) {
    (_RowState.pending || _RowState.done, _) => null,
    (_, ToolCallStatusView.failed) => 'Failed',
    _ => 'Cancelled',
  };
  final tail = state == _RowState.pending ? row.progress : row.summaryShort;
  final segments = [
    ?word,
    if (tail != null && tail.isNotEmpty) sanitizeTerminalText(tail),
  ];
  return '${_icon(state, unicode)} $title'
      '${segments.isEmpty ? '' : '  ${segments.join('  ')}'}';
}

/// Итоговый ли статус: после него строка вызова печатается последний раз.
bool isFinalToolCall(ToolCallItem item) => switch (_stateOf(item)) {
  _RowState.pending => false,
  _ => true,
};

enum _RowState { pending, done, failed, rejected }

_RowState _stateOf(ToolCallItem item) {
  // Отклонённое одобрение — итог вызова, даже если агент ещё не прислал
  // статус: пользователь должен видеть, что действие не выполнялось.
  if (item.approval case ResolvedApprovalView(
    outcome: ApprovalOutcomeView.rejected || ApprovalOutcomeView.cancelled,
  )) {
    return _RowState.rejected;
  }
  return switch (item.details?.status) {
    null ||
    ToolCallStatusView.queued ||
    ToolCallStatusView.running => _RowState.pending,
    ToolCallStatusView.succeeded => _RowState.done,
    ToolCallStatusView.failed => _RowState.failed,
    ToolCallStatusView.cancelled => _RowState.rejected,
  };
}

/// Значки design.md, D6: `…` выполняется, `✓` успех, `✗` ошибка, `⊘`
/// отменён или отклонён; ASCII-замена `*`, `+`, `x`, `-`.
String _icon(_RowState state, bool unicode) => switch (state) {
  _RowState.pending => unicode ? '…' : '*',
  _RowState.done => unicode ? '✓' : '+',
  _RowState.failed => unicode ? '✗' : 'x',
  _RowState.rejected => unicode ? '⊘' : '-',
};

/// Первая строка: многострочная команда не должна ломать строку вызова.
String _firstLine(String text) {
  final end = text.indexOf('\n');
  return end < 0 ? text : '${text.substring(0, end)} …';
}

String _seconds(Duration elapsed) =>
    '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';
