import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'connection/acp_error.dart';

/// Проекция событий ядра в `session/update` и итог хода в ответ
/// `session/prompt` (`agent-core-architecture` §13.7, §13.8).
///
/// Почему отдельные функции: ядро не знает протокола (LOOP-6), а таблица
/// проекции — контракт ACP-сервера. Чистые функции без состояния
/// проверяются строка за строкой, а мост сессии только ставит их кадры в
/// очередь.
///
/// Как использовать: мост вызывает [projectEvent] на каждое событие сессии,
/// [inProgressUpdate] — из хука `markInProgress`, [turnResponse] — по
/// `TurnEnded`.

/// Таблица §13.7: подтип `AgentEvent` → что получает клиент. Тест ACP-6
/// сверяет её ключи со всеми подтипами иерархии.
const projectionTable = <Type, String>{
  TurnStarted: 'not sent',
  StepStarted: 'not sent',
  ModelRequested: 'not sent',
  MessageStarted: 'not sent: chunks come from deltas',
  MessageDelta: 'agent_message_chunk',
  ThoughtDelta: 'agent_thought_chunk',
  MessageEnded: 'not sent: everything went out as deltas',
  ToolCallStarted: 'tool_call, status pending',
  ToolCallProgress: 'tool_call_update with content',
  ToolCallFinished: 'tool_call_update, completed or failed with outcome',
  ToolPairingRepaired: 'not sent',
  StepEnded: 'not sent',
  PlanUpdated: 'plan',
  ModeChanged: 'current_mode_update and config_option_update',
  AgentError: 'not sent: the turn result carries the failure',
  ContextCompacted: 'not sent',
  SessionTitleChanged: 'session_info_update',
  TurnEnded: 'the answer to session/prompt',
};

/// Кадры события [event]; пустой список — событие не передаётся.
///
/// [configOptions] — текущий снимок опций сессии для
/// `config_option_update`. `switch` исчерпывающий без `default`: новый
/// подтип `AgentEvent` не компилируется без своей строки (ACP-6).
List<acp.SessionUpdate> projectEvent(
  AgentEvent event, {
  required List<acp.SessionConfigOption> Function() configOptions,
}) => switch (event) {
  TurnStarted() ||
  StepStarted() ||
  ModelRequested() ||
  MessageStarted() ||
  MessageEnded() ||
  ToolPairingRepaired() ||
  StepEnded() ||
  AgentError() ||
  ContextCompacted() ||
  TurnEnded() => const [],
  MessageDelta(:final delta) => [
    acp.SessionUpdate.agentMessageChunk(content: _text(delta)),
  ],
  ThoughtDelta(:final delta) => [
    acp.SessionUpdate.agentThoughtChunk(content: _text(delta)),
  ],
  ToolCallStarted() => [
    acp.SessionUpdate.toolCall(
      toolCall: acp.ToolCall(
        toolCallId: acp.ToolCallId(event.toolCallId),
        title: event.title,
        kind: acp.ToolKind.values.byName(event.kind.name),
        status: acp.ToolCallStatus.pending,
        rawInput: event.input,
        locations: acpLocations(event.locations),
      ),
    ),
  ],
  // Прогресс приходит только от исполняемого вызова: статус in_progress
  // (фикстура acp/tool-exec-terminal-embed).
  ToolCallProgress(:final toolCallId, :final content) => [
    acp.SessionUpdate.toolCallUpdate(
      toolCallUpdate: acp.ToolCallUpdate(
        toolCallId: acp.ToolCallId(toolCallId),
        status: acp.ToolCallStatus.inProgress,
        content: [for (final item in content) _toolContent(item)],
      ),
    ),
  ],
  ToolCallFinished() => [_finished(event)],
  PlanUpdated(:final entries) => [
    acp.SessionUpdate.plan(
      entries: [
        for (final entry in entries)
          acp.PlanEntry(
            content: entry.content,
            priority: acp.PlanEntryPriority.values.byName(entry.priority.name),
            status: acp.PlanEntryStatus.values.byName(entry.status.name),
          ),
      ],
    ),
  ],
  ModeChanged(:final mode) => [
    acp.SessionUpdate.currentModeUpdate(
      currentModeId: acp.SessionModeId(mode.value),
    ),
    acp.SessionUpdate.configOptionUpdate(configOptions: configOptions()),
  ],
  SessionTitleChanged(:final title, :final updatedAt) => [
    acp.SessionUpdate.sessionInfoUpdate(
      title: title,
      updatedAt: formatJournalTime(updatedAt),
    ),
  ],
};

/// Вызов прошёл проверку разрешений и все хуки и сейчас начнёт
/// исполняться (§13.7, «Статусы вызова»).
acp.SessionUpdate inProgressUpdate(String toolCallId) =>
    acp.SessionUpdate.toolCallUpdate(
      toolCallUpdate: acp.ToolCallUpdate(
        toolCallId: acp.ToolCallId(toolCallId),
        status: acp.ToolCallStatus.inProgress,
      ),
    );

/// Ответ `session/prompt` по итогу хода (§13.8).
///
/// [failure] — последняя окончательная ошибка хода (`AgentError` без
/// `retrying`); [cancelRequested] — клиент прислал `session/cancel`: тогда
/// ответ `cancelled`, даже если отмена вызвала ошибки (ACP-5). Сбой хода —
/// исключение [AcpRequestError] `-32603` с `data.codelab`, а не `end_turn`
/// (ACP-7).
acp.PromptResponse turnResponse(
  TurnEnded ended, {
  AgentError? failure,
  bool cancelRequested = false,
}) {
  if (cancelRequested) {
    return const acp.PromptResponse(stopReason: acp.StopReason.cancelled);
  }
  return switch (ended.reason) {
    TurnEndReason.completed => switch (ended.budgetExceeded) {
      null => const acp.PromptResponse(stopReason: acp.StopReason.endTurn),
      final limit => acp.PromptResponse(
        stopReason: acp.StopReason.maxTurnRequests,
        meta: {
          'codelab': {'budgetExceeded': limit.name},
        },
      ),
    },
    TurnEndReason.maxTokens => const acp.PromptResponse(
      stopReason: acp.StopReason.maxTokens,
    ),
    TurnEndReason.refused => const acp.PromptResponse(
      stopReason: acp.StopReason.refusal,
    ),
    TurnEndReason.cancelled => const acp.PromptResponse(
      stopReason: acp.StopReason.cancelled,
    ),
    TurnEndReason.failed => throw _turnFailed(failure),
  };
}

AcpRequestError _turnFailed(AgentError? failure) {
  final errorClass = failure == null
      ? 'unknown'
      : failure.errorClass?.name ?? failure.cls.name;
  final message = failure?.message ?? 'the turn failed';
  return AcpRequestError(
    acp.jsonRpcInternalErrorCode,
    'Turn failed: $message',
    data: {
      'codelab': {
        'errorClass': errorClass,
        'message': message,
        'retryable': _retryable.contains(failure?.errorClass),
      },
    },
  );
}

/// Классы сбоя провайдера, после которых повтор того же хода может пройти
/// (сеть, таймаут, лимит запросов, сервер, §2.9). Сбой хоста (`hook`,
/// `storage`, `compaction`) повтором не лечится.
const _retryable = {
  LlmErrorClass.network,
  LlmErrorClass.timeout,
  LlmErrorClass.rateLimited,
  LlmErrorClass.server,
};

acp.SessionUpdate _finished(ToolCallFinished event) =>
    acp.SessionUpdate.toolCallUpdate(
      toolCallUpdate: acp.ToolCallUpdate(
        toolCallId: acp.ToolCallId(event.toolCallId),
        status: finishedStatus(event),
        // §13.7: у отменённого вызова — только статус и outcome; текст об
        // отмене — для модели, клиент уже видит вывод в терминале.
        content: event.outcome == ToolOutcome.cancelled
            ? null
            : finishedContent(event),
        meta: finishedMeta(event),
      ),
    );

/// Итоговый статус вызова: в ACP нет `cancelled` и `rejected`, поэтому
/// всё, кроме исполненного вызова, — `failed` (§13.7).
acp.ToolCallStatus finishedStatus(ToolCallFinished event) =>
    event.outcome == ToolOutcome.completed && !event.interrupted
    ? acp.ToolCallStatus.completed
    : acp.ToolCallStatus.failed;

/// Контент результата и по одному `diff` на каждый изменённый файл.
List<acp.ToolCallContent> finishedContent(ToolCallFinished event) => [
  for (final block in event.content)
    acp.ToolCallContent.content(content: acpContent(block)),
  for (final diff in event.diffs) acpDiff(diff),
];

/// `_meta.codelab.outcome` — исход, которого нет в статусах ACP (D10);
/// `null` — исход передаёт сам статус.
Map<String, Object?>? finishedMeta(ToolCallFinished event) {
  final outcome = event.interrupted
      ? 'interrupted'
      : switch (event.outcome) {
          ToolOutcome.completed || ToolOutcome.failed => null,
          ToolOutcome.cancelled => 'cancelled',
          ToolOutcome.rejected => 'rejected',
        };
  return outcome == null
      ? null
      : {
          'codelab': {'outcome': outcome},
        };
}

acp.ToolCallContent _toolContent(ToolCallContent item) => switch (item) {
  ToolCallBlock(:final block) => acp.ToolCallContent.content(
    content: acpContent(block),
  ),
  ToolCallDiff(:final diff) => acpDiff(diff),
  ToolCallTerminal(:final terminalId) => acp.ToolCallContent.terminal(
    terminalId: terminalId,
  ),
};

acp.ContentBlock _text(String text) => acp.ContentBlock.text(text: text);

/// Блок ядра на проводе. Рассуждения и вызовы в контент вызова не попадают;
/// если попали — текстом, а не потерей данных.
acp.ContentBlock acpContent(ContentBlock block) => switch (block) {
  TextContent(:final text) => acp.ContentBlock.text(text: text),
  ImageContent(:final base64, :final mimeType) => acp.ContentBlock.image(
    data: base64,
    mimeType: mimeType,
  ),
  ThinkingContent(:final thinking) => acp.ContentBlock.text(text: thinking),
  ToolCall(:final name) => acp.ContentBlock.text(text: '[tool call $name]'),
};

/// Правка одного файла: `{"type":"diff","path","oldText","newText"}`.
acp.ToolCallContent acpDiff(FileDiff diff) => acp.ToolCallContent.diff(
  diff: acp.Diff(path: diff.path, oldText: diff.oldText, newText: diff.newText),
);

/// Места вызова; пустой список — ключа нет: фикстуры и клиенты не ждут
/// `locations: []` (§14.8).
List<acp.ToolCallLocation>? acpLocations(List<Location> locations) =>
    locations.isEmpty ? null : [for (final l in locations) acpLocation(l)];

acp.ToolCallLocation acpLocation(Location location) =>
    acp.ToolCallLocation(path: location.path, line: location.line);
