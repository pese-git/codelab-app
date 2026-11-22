import 'package:codelab_client_acp/codelab_client_acp.dart' show SecretRedactor;
import 'package:codelab_client_core/codelab_client_core.dart';

import 'sanitize.dart';

/// Маскирует секреты в тексте агента строки вызова (D4 change
/// `redact-tool-row-text`); те же правила, что у клиентского слоя, а не своя
/// копия (§14).
const _redactor = SecretRedactor();

/// CSI-последовательность целиком (как в `_clean` kit): заменяется пробелом
/// до санитизации (D4, шаг 0).
final _csi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

/// Текст агента для строки: CSI — пробел, остальное управляющее вырезано,
/// секреты замаскированы. Порядок D4: без шага 0 `sanitizeTerminalText`
/// вырезал бы только ESC и оставил `[0m` в тексте, а `Bearer\u001b[0m t0k3n`
/// превращался бы в `Bearer[0m t0k3n`, на который шаблон заголовка не
/// срабатывает и токен остаётся виден.
String _safe(String text) =>
    _redactor.redactText(sanitizeTerminalText(text.replaceAll(_csi, ' ')));

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
/// значки для терминала без UTF-8. Текст агента (название и команда)
/// проходит `sanitizeTerminalText` и `SecretRedactor` (design.md change
/// `redact-tool-row-text`, D4, VIEW-9).
///
/// Порядок: CSI-последовательности заменяются пробелом, затем санитизация,
/// маскирование всего значения и только потом первая строка — многострочная
/// команда с `Authorization:` на второй строке маскируется до обрезки, и
/// результат не зависит от того, где лежит секрет. Проверка повтора
/// `title.contains(detail)` идёт по замаскированным значениям: одинаковый
/// секрет маскируется одинаково, повтор по-прежнему опознаётся.
String toolRow(ToolCallItem item, {bool unicode = true, Duration? elapsed}) {
  final icon = _icon(_stateOf(item), unicode);
  final title = _firstLine(_safe(item.title));
  final command = item.details?.command;
  final detail = command == null ? null : _firstLine(_safe(command));
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
String subagentStatusRow(
  ToolCallItem item, {
  bool unicode = true,
  bool showProgress = true,
}) {
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
  final tail = state == _RowState.pending
      ? (showProgress ? row.progress : null)
      : row.summaryShort;
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

/// Строки исхода одобрений потомков под строкой `agent` корня: `  <путь>:
/// <метка решения>` на каждое решённое (D43 п. 2).
///
/// Почему: без дерева вызовов (клиент без согласия) у вызова потомка при
/// строке корня нет своей строки, и без этих строк решение пользователя в
/// ленте не видно; с деревом строка вызова потомка есть, но блок решения
/// остаётся у корня (D47 Т9, Т10).
/// Как использовать: REPL и TUI печатают строки сразу после строки вызова.
/// Путь берётся из решённого одобрения, а без него — из типа вызова корня.
/// Возвращает пары (индекс в `childApprovals`, строка).
List<(int, String)> childOutcomeLines(ToolCallItem item) => [
  for (final (index, approval) in item.childApprovals.indexed)
    if (approval case ResolvedApprovalView(:final label, :final subagent))
      (
        index,
        '  ${sanitizeTerminalText(subagent?.pathText ?? item.details?.subagentCall?.type ?? '…')}: '
            '${sanitizeTerminalText(label)}',
      ),
];
