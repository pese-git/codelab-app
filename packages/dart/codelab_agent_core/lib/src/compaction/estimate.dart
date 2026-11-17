/// Оценка размера контекста в токенах (`agent-core-architecture` §9.3).
///
/// Почему эвристика: точного токенайзера для всех провайдеров в Dart нет,
/// а на web он слишком тяжёл. «4 символа UTF-16 ≈ 1 токен» ошибается на
/// коде и не-латинице, поэтому [estimateContextTokens] якорится на точном
/// `usage` последнего ответа провайдера и оценивает только хвост после
/// него; недооценку ловит аварийный путь `overflow` (CMP-8).
///
/// Как использовать: порог сжатия, проверка payload перед запросом и
/// `ModelRequested.estimatedTokens` считают окно одной функцией
/// [effectiveContextWindow] (CMP-6).
library;

import 'dart:convert';
import 'dart:math' as math;

import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../session/projections.dart';

/// Стоимость картинки — константа: размер base64 не говорит о числе
/// токенов изображения у провайдера (§9.3).
const imageTokens = 1200;

/// Служебные поля сообщения (роль, разделители).
const _messageOverhead = 4;

int _chars(int length) => (length / 4).ceil();

int _block(ContentBlock block) => switch (block) {
  TextContent(:final text) => _chars(text.length),
  ThinkingContent(:final thinking, :final signature, :final redacted) => _chars(
    redacted ? (signature ?? '').length : thinking.length,
  ),
  ToolCall(:final name, :final arguments) => _chars(
    name.length + jsonEncode(arguments).length,
  ),
  ImageContent() => imageTokens,
};

/// Оценка одного сообщения: блоки, `+4` на сообщение, у результата
/// инструмента — ещё имя инструмента.
int estimateMessageTokens(Message message) {
  final blocks = message.content.fold(0, (sum, b) => sum + _block(b));
  return switch (message) {
    ToolResultMessage(:final toolName) =>
      blocks + _chars(toolName.length) + _messageOverhead,
    _ => blocks + _messageOverhead,
  };
}

/// Оценка по символам: сообщения, системный промпт и схемы инструментов.
int estimateTokens(
  List<Message> messages, {
  String? systemPrompt,
  List<ToolSchema> tools = const [],
}) =>
    _chars(systemPrompt?.length ?? 0) +
    (tools.isEmpty ? 0 : _chars(_schemasJson(tools).length)) +
    messages.fold(0, (sum, m) => sum + estimateMessageTokens(m));

/// Якорь на последнее сжатие: пара чисел, зафиксированная в момент записи
/// сжатия (§9.3 «Якорь на последнее сжатие»; design.md change
/// `anchor-context-estimate-after-compaction`, D1).
///
/// Почему: после сжатия в контексте нет ответа с usage провайдера (§8.7), и
/// оценка падала на чистую эвристику, которая завышает постоянную часть
/// (промпт, схемы). `tokens` — `tokensAfter` записи (согласованная оценка
/// компактора), `raw` — эвристика [estimateTokens] ровно по тому, что
/// `tokensAfter` покрывает: промпт, схемы и первые `compactionCovered`
/// сообщений проекции.
///
/// Как использовать: сессия получает его из [compactionAnchorOf] и хранит
/// вместе с транскриптом (D3); оценщик применяет как смещение
/// `tokens − raw`. Из бареля не экспортируется.
typedef CompactionAnchor = ({int tokens, int raw});

/// Якорь сжатия по проекции [projection] активной ветки (D1, D6).
///
/// Почему отдельная функция: якорь строит и сессия (после записи сжатия, при
/// загрузке), и тесты; `raw` обязан считаться теми же [systemPrompt] и
/// [tools], что видела оценка, иначе смещение потеряет смысл.
///
/// Возвращает `null`, если сжатия нет или `tokensAfter ≤ 0` (вырожденная
/// запись, ручная правка файла): оценка остаётся чистой эвристикой — безопасная
/// сторона, завышение ловит аварийное сжатие (D6).
CompactionAnchor? compactionAnchorOf(
  LlmContextProjection projection, {
  required String systemPrompt,
  required List<ToolSchema> tools,
}) {
  final record = projection.lastCompaction;
  if (record == null || record.tokensAfter <= 0) {
    return null;
  }
  return (
    tokens: record.tokensAfter,
    raw: estimateTokens(
      projection.messages.take(projection.compactionCovered).toList(),
      systemPrompt: systemPrompt,
      tools: tools,
    ),
  );
}

/// Оценка контекста с якорями (§9.3).
///
/// Три ветви по порядку (D1, D2):
/// 1. якорь на `usage`: последний ответ модели с ненулевым
///    `input + cacheRead + cacheWrite` — `input` провайдера уже включает
///    системный промпт, схемы и все сообщения до него. Ответы до сжатия в
///    проекции несут `Usage.zero` (§8.7) и якорем не служат — поэтому любой
///    ответ с usage в сообщениях получен после сжатия и точнее якоря сжатия;
/// 2. иначе, если задан [compaction], — `max(0, tokens + H − raw)`: смещение
///    эвристики, зафиксированное при сжатии; сразу после записи оценка равна
///    `tokensAfter` (CMP-11). Ответы без usage якорь сжатия не снимают;
/// 3. иначе — чистая эвристика всего контекста.
int estimateContextTokens(
  List<Message> messages, {
  required String systemPrompt,
  required List<ToolSchema> tools,
  CompactionAnchor? compaction,
}) {
  final anchor = messages.lastIndexWhere(
    (m) =>
        m is AssistantMessage &&
        m.usage.input + m.usage.cacheRead + m.usage.cacheWrite > 0,
  );
  if (anchor < 0) {
    final heuristic = estimateTokens(
      messages,
      systemPrompt: systemPrompt,
      tools: tools,
    );
    return compaction == null
        ? heuristic
        : math.max(0, compaction.tokens + heuristic - compaction.raw);
  }
  final usage = (messages[anchor] as AssistantMessage).usage;
  return usage.input +
      usage.cacheRead +
      usage.cacheWrite +
      usage.output +
      estimateTokens(messages.sublist(anchor + 1));
}

/// Согласованная оценка контекста после прохода сжатия (§9.3 «Оценка после
/// сжатия»; design.md change `fix-compaction-estimate-and-no-gain`, D1).
///
/// Почему: «до» ([before]) якорится на точном `usage` провайдера, а после
/// сжатия якоря в проекции нет (§8.7), и «после» было бы чистой эвристикой
/// `chars / 4`. Эвристика завышает постоянную часть (промпт и схемы
/// инструментов — JSON, а не проза), поэтому оценка «после» могла оказаться
/// выше «до», хотя контекст уменьшился.
///
/// Для чего: считает «после» от той же базы, что и «до». Системный промпт,
/// схемы и сохранённый хвост входят в обе проекции одинаково, так что
/// эвристикой оценивается только разница — убранный регион против резюме с
/// обёрткой и сообщением навыков. Без якоря [before] равен [rawBefore], и
/// результат — [rawAfter], как прежде. Нижняя граница 0: scripted-модели
/// задают usage произвольно, а отрицательной оценке в записи журнала не
/// место (недооценку ловит аварийный путь `overflow`, CMP-8).
///
/// Как использовать: единственный потребитель — компактор; [before] — оценка
/// контекста перед проходом (на первом проходе [estimateContextTokens], на
/// следующих — результат прошлого прохода, D2), [rawBefore] и [rawAfter] —
/// [estimateTokens] без якоря по проекциям до прохода и после (с ещё не
/// записанной записью). Из бареля не экспортируется.
int estimateAfterCompaction({
  required int before,
  required int rawBefore,
  required int rawAfter,
}) => math.max(0, before + rawAfter - rawBefore);

/// Окно для порога, проверки перед запросом и индикатора (CMP-6).
int effectiveContextWindow(ModelRef model, {int? cap}) =>
    cap == null || cap > model.contextWindow ? model.contextWindow : cap;

String _schemasJson(List<ToolSchema> tools) => jsonEncode([
  for (final t in tools)
    {'name': t.name, 'description': t.description, 'parameters': t.parameters},
]);
