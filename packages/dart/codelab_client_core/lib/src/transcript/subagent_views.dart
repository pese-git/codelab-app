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

/// Субагент, который просит разрешение: `_meta.codelab.subagent` в `toolCall`
/// запроса `session/request_permission` (D8, D15, D43 п. 1).
///
/// Почему: ключ `_meta.codelab.subagent` на проводе один, но в запросе он
/// называет спрашивающего потомка, а в `tool_call` — запущенный `agent`
/// (D43 п. 1). Поэтому это отдельный тип, не [SubagentCallView]: запрос не
/// делает `exec` потомка строкой «Subagent …».
///
/// Для чего: хосты показывают, кто спрашивает — строку пути
/// `review › explore wants to run` (D27) и заголовок задачи [description].
///
/// Как использовать: kit кладёт значение в `PendingApprovalView.subagent`,
/// `ResolvedApprovalView.subagent` и `ToolCallView.subagent`. [rootType] —
/// тип вызова `agent` корня; kit заполняет его только при [depth] больше 1
/// (при глубине 1 путь — один тип спрашивающего), хост его не задаёт.
final class SubagentRequester {
  const SubagentRequester({
    required this.id,
    required this.type,
    required this.description,
    required this.depth,
    required this.parentToolCallId,
    this.rootType,
    this.chainTypes,
  });

  /// Id спрашивающего субагента (`sub_xxxxxxxx`).
  final String id;

  /// Тип спрашивающего: `explore`, `review` и т. д.
  final String type;

  /// Заголовок задачи спрашивающего — подсказка и раскрытие блока (D27).
  final String description;

  /// Глубина: 1 — ребёнок корня.
  final int depth;

  /// Вызов `agent` корневого уровня, под строкой которого стоит блок
  /// (D43 п. 2).
  final String parentToolCallId;

  /// Тип вызова `agent` корня (D43 п. 4): `subagentCall.type` → `rawInput.type`;
  /// `null` — kit его не знает (путь покажет `…`).
  final String? rootType;

  /// Типы цепочки от вызова `agent` корня до спрашивающего по дереву вызовов
  /// (итерация 5, D47 Т9); `null` — дерева у запроса нет (клиент без согласия
  /// или вызов без своей строки). Длина равна [depth], неизвестное звено — `…`.
  final List<String>? chainTypes;

  /// Типы цепочки от ребёнка корня до спрашивающего; длина равна [depth].
  ///
  /// Первое звено — [rootType] или `…`, последнее — [type]; промежуточные —
  /// из дерева вызовов ([chainTypes]), а без него неизвестны и дают `…`
  /// (D27, D43 п. 4).
  List<String> get pathTypes =>
      chainTypes ??
      (depth <= 1
          ? [type]
          : [rootType ?? '…', for (var i = 2; i < depth; i++) '…', type]);

  /// Строка пути для представлений: `review › explore`.
  String get pathText => pathTypes.join(' › ');

  SubagentRequester withRootType(String? rootType) => SubagentRequester(
    id: id,
    type: type,
    description: description,
    depth: depth,
    parentToolCallId: parentToolCallId,
    rootType: rootType,
    chainTypes: chainTypes,
  );

  /// Копия с цепочкой типов, найденной подъёмом по дереву вызовов.
  SubagentRequester withChainTypes(List<String> chainTypes) =>
      SubagentRequester(
        id: id,
        type: type,
        description: description,
        depth: depth,
        parentToolCallId: parentToolCallId,
        rootType: rootType,
        chainTypes: chainTypes,
      );

  @override
  bool operator ==(Object other) =>
      other is SubagentRequester &&
      other.chainTypes?.join('\u0000') == chainTypes?.join('\u0000') &&
      other.id == id &&
      other.type == type &&
      other.description == description &&
      other.depth == depth &&
      other.parentToolCallId == parentToolCallId &&
      other.rootType == rootType;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    description,
    depth,
    parentToolCallId,
    rootType,
    chainTypes?.join('\u0000'),
  );

  @override
  String toString() => 'SubagentRequester($id, $pathText)';
}

/// Счётчик вызовов `N tool calls` / `1 tool call`.
///
/// Почему: один формат у счётчика работающего `agent`
/// (`ToolRowView.runningCounter`) и у итога ([SubagentSummaryView]), чтобы
/// строка не меняла вид при завершении (D25, D27).
String subagentCallsText(int count) =>
    '$count tool call${count == 1 ? '' : 's'}';

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

  /// Сумма токенов `input + output`: `850`, `18.2k` (общий формат для
  /// [text], [shortText] и строк панели Agents).
  String get tokensText => totalTokens < 1000
      ? '$totalTokens'
      : '${(totalTokens / 1000).toStringAsFixed(1)}k';

  /// Время: `48s`, `2m 05s`, `1h 02m`.
  String get durationText => formatSubagentDuration(duration);

  String get _calls => subagentCallsText(toolCalls);

  /// Полная строка итога: `4 tool calls · 18.2k tokens · 48s`.
  String get text => '$_calls · $tokensText tokens · $durationText';

  /// Сокращённый вид свёрнутой строки (D27): `4 tool calls · 18.2k · 48s`.
  String get shortText => '$_calls · $tokensText · $durationText';

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

/// Причина отказа из накопленного `_meta.codelab.subagent.failure`; `null`,
/// если ключа нет или это не непустая строка (терпимый разбор).
String? parseSubagentFailure(Map<String, Object?>? meta) {
  final failure = meta?['failure'];
  return failure is String && failure.isNotEmpty ? failure : null;
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

/// Спрашивающий из `ApprovalRequest.subagentRequester` (сырой
/// `_meta.codelab.subagent` запроса); `null` при неверной форме обязательных
/// полей — запрос показывается как обычный (терпимый разбор, D43 п. 1).
///
/// [rootType] — тип вызова `agent` корня; применяется только при глубине
/// больше 1 (см. [SubagentRequester.rootType]).
SubagentRequester? parseSubagentRequester(
  Map<String, Object?>? meta, {
  String? rootType,
}) {
  final id = meta?['id'];
  final type = meta?['type'];
  final depth = meta?['depth'];
  final parent = meta?['parentToolCallId'];
  final description = meta?['description'];
  if (id is! String ||
      id.isEmpty ||
      type is! String ||
      type.isEmpty ||
      depth is! int ||
      depth < 1 ||
      parent is! String ||
      parent.isEmpty) {
    return null;
  }
  return SubagentRequester(
    id: id,
    type: type,
    description: description is String ? description : '',
    depth: depth,
    parentToolCallId: parent,
    rootType: depth > 1 ? rootType : null,
  );
}
