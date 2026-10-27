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
  return [
    icon,
    title,
    if (detail != null && detail.isNotEmpty && !title.contains(detail)) detail,
    if (elapsed != null) _seconds(elapsed),
  ].join(' ');
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
