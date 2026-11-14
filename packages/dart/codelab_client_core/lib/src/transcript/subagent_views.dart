/// Опознание вызова `agent` и его итог в представлении kit.
///
/// Почему: агент CodeLab отдаёт субагента обычным вызовом `think`, а клиенту
/// нужно отличить его от «мысли» стороннего агента и показать итог работы
/// (число вызовов, токены, время) без разбора заголовка и строки прогресса
/// (design.md change `add-subagents-and-tasks`, D24, D27, D28; spec
/// acp-client-kit «Итог и хвост субагента»).
///
/// Для чего: [SubagentCallView] и [SubagentSummaryView] — поля
/// `ToolCallView.subagentCall` и `ToolCallView.subagentSummary`; обе строки
/// итога ([SubagentSummaryView.text], [SubagentSummaryView.shortText]) общие
/// для REPL, TUI и desktop, чтобы формат не расходился.
///
/// Как использовать: хосты читают готовые поля `ToolCallView`; разбор —
/// [parseSubagentCall] и [parseSubagentSummary] — вызывает проекция
/// транскрипта по `_meta.codelab.subagent` вызова. Любая неверная форма даёт
/// `null` без отказа (терпимый разбор: `_meta` необязателен).
library;

/// Признак вызова `agent`: `_meta.codelab.subagent {id, type}` первого кадра
/// (D28). Вызов без признака — обычный `think` (сторонний агент).
///
/// При реплее отклонённого вызова агент шлёт `{type}` без `id` (D36, Т15):
/// ребёнка не было, id придумывать нельзя — строка остаётся строкой `agent`.
final class SubagentCallView {
  const SubagentCallView({this.id, required this.type});

  /// Id субагента (`sub_xxxxxxxx`); им помечены пункты плана и запросы.
  /// `null` — реплей отклонённого вызова (Т15).
  final String? id;

  /// Тип субагента: `explore`, `review` и т. д.
  final String type;

  @override
  bool operator ==(Object other) =>
      other is SubagentCallView && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'SubagentCallView($id, $type)';
}

/// Итог субагента из `_meta.codelab.subagent.summary` финального обновления
/// (D24). Токены — сумма `input + output`.
final class SubagentSummaryView {
  const SubagentSummaryView({
    required this.toolCalls,
    required this.inputTokens,
    required this.outputTokens,
    required this.duration,
  });

  final int toolCalls;
  final int inputTokens;
  final int outputTokens;
  final Duration duration;

  int get totalTokens => inputTokens + outputTokens;

  /// Время: `48s`, `2m 05s`, `1h 02m`.
  String get durationText => formatSubagentDuration(duration);

  String get _calls => '$toolCalls tool call${toolCalls == 1 ? '' : 's'}';

  /// Полная строка итога: `4 tool calls · 18.2k tokens · 48s`.
  String get text => '$_calls · ${_tokens(totalTokens)} tokens · $durationText';

  /// Сокращённый вид свёрнутой строки (D27): `4 tool calls · 18.2k · 48s`.
  String get shortText => '$_calls · ${_tokens(totalTokens)} · $durationText';

  @override
  bool operator ==(Object other) =>
      other is SubagentSummaryView &&
      other.toolCalls == toolCalls &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.duration == duration;

  @override
  int get hashCode =>
      Object.hash(toolCalls, inputTokens, outputTokens, duration);

  @override
  String toString() => 'SubagentSummaryView($text)';
}

/// `18200` → `18.2k`; меньше тысячи — число как есть (`850`).
String _tokens(int total) =>
    total < 1000 ? '$total' : '${(total / 1000).toStringAsFixed(1)}k';

/// Формат длительности субагента: `48s`, `2m 05s`, `1h 02m` (D24, D27).
String formatSubagentDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return '${seconds}s';
  }
  final minutes = duration.inMinutes;
  if (minutes < 60) {
    return '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${duration.inHours}h '
      '${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// Признак вызова из накопленного `_meta.codelab.subagent`; `null` без
/// строкового `type` или с `id` неверной формы. `id` необязателен (Т15).
SubagentCallView? parseSubagentCall(Map<String, Object?>? meta) {
  final id = meta?['id'];
  final type = meta?['type'];
  if (type is! String || type.isEmpty) {
    return null;
  }
  if (id == null) {
    return SubagentCallView(type: type);
  }
  return id is String && id.isNotEmpty
      ? SubagentCallView(id: id, type: type)
      : null;
}

/// Итог из накопленного `_meta.codelab.subagent`; `null` при неверной форме
/// любого обязательного поля, неизвестные ключи игнорируются.
SubagentSummaryView? parseSubagentSummary(Map<String, Object?>? meta) {
  final summary = meta?['summary'];
  if (summary is! Map) {
    return null;
  }
  final calls = summary['toolCalls'];
  final tokens = summary['tokens'];
  final duration = summary['durationMs'];
  if (calls is! int || tokens is! Map || duration is! int) {
    return null;
  }
  final input = tokens['input'];
  final output = tokens['output'];
  if (input is! int || output is! int) {
    return null;
  }
  return SubagentSummaryView(
    toolCalls: calls,
    inputTokens: input,
    outputTokens: output,
    duration: Duration(milliseconds: duration),
  );
}
