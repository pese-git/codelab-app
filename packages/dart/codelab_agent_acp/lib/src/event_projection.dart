import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'connection/acp_error.dart';
import 'subagent_chain.dart';

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
  // Usage уходит не в `session/update`, а уведомлением
  // `_codelab/session/usage` соединению, объявившему `usage`; его строит мост
  // (`SessionBridge`), а не `projectEvent` (change `add-usage-extension`,
  // D1, D18 Т5): `step` — после каждого `StepEnded`.
  StepEnded: 'not sent as session/update: _codelab/session/usage, step',
  // Список задач целиком, у entry `_meta.codelab.task`; `op: restore` (список
  // новой ветки, D29) проецируется так же (agent-acp-server «Проекция
  // субагентов и списка задач»).
  TaskListChanged: 'plan',
  ModeChanged: 'current_mode_update and config_option_update',
  AgentError: 'not sent: the turn result carries the failure',
  ContextCompacted:
      'not sent as session/update: _codelab/session/usage, compaction',
  SessionTitleChanged: 'session_info_update',
  TurnEnded:
      'the answer to session/prompt; _codelab/session/usage, turn, before it',
  ModelOptionsChanged: 'config_option_update',
  // События субагентов (change `add-subagents-and-tasks`, D24): клиент видит
  // один вызов `agent`; строку прогресса несёт `ToolCallProgress(agent)`, итог
  // уходит в `ToolCallFinished(agent)` из `SubagentFinished`, а вызовы
  // потомков (`SubagentActivity`) уходят только клиенту с согласием
  // `subagentToolCalls`: `tool_call`/`tool_call_update` с цепочкой
  // `toolCallId` и `_meta.codelab.parentToolCallId` (D47 Т2); без согласия
  // не отправляются (SUB-12).
  SubagentStarted: 'not sent: log subagent.start',
  SubagentProgress: 'not sent: the progress line is ToolCallProgress(agent)',
  SubagentFinished: 'not sent: its data go into ToolCallFinished(agent)',
  SubagentActivity:
      'tool_call/tool_call_update of the call by the subagentToolCalls '
      'consent, a chained toolCallId; not sent without it',
};

/// Кадры события [event]; пустой список — событие не передаётся.
///
/// [configOptions] — текущий снимок опций сессии для
/// `config_option_update`. [replay] — кадр уходит при `session/load`: у `plan`
/// тогда нет `_meta.codelab.taskChange`, потому что реплей показывает
/// состояние, а не операцию (design.md change `add-subagents-and-tasks`,
/// D35). `switch` исчерпывающий без `default`: новый подтип `AgentEvent` не
/// компилируется без своей строки (ACP-6).
///
/// [subagentResult] — `SubagentFinished` вызова `agent`, которое ядро
/// эмитит до его `ToolCallFinished` (SUB-10): проекция событий без
/// состояния, поэтому мост запоминает итог по `parentToolCallId` и передаёт
/// сюда вместе с финальным событием, а `_meta.codelab.subagent.summary`
/// (D24) строится из него.
///
/// [subagentPrefix] — цепочка `toolCallId` вызова `agent`, запустившего
/// потомка события `SubagentActivity` (design.md change
/// `add-subagents-and-tasks`, D47 Т2), передаваемая только клиенту с
/// согласием `subagentToolCalls`. `null` — согласия нет или префикс
/// неизвестен: `SubagentActivity` кадров не даёт (SUB-12). Префикс
/// вычисляет мост помощником `SubagentChains`, общим с реплеем. Для
/// вложенного `agent` [subagentResult] — итог его потомка (D47 Т3).
List<acp.SessionUpdate> projectEvent(
  AgentEvent event, {
  required List<acp.SessionConfigOption> Function() configOptions,
  bool replay = false,
  SubagentFinished? subagentResult,
  String? subagentPrefix,
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
  TurnEnded() ||
  SubagentStarted() ||
  SubagentProgress() ||
  SubagentFinished() => const [],
  SubagentActivity(:final event) =>
    subagentPrefix == null
        ? const []
        : _chained(
            event,
            subagentPrefix,
            configOptions: configOptions,
            subagentResult: subagentResult,
          ),
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
        meta: subagentCallMeta(event.subagent),
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
  ToolCallFinished() => [_finished(event, subagentResult)],
  TaskListChanged(:final items, :final change) => [
    acp.SessionUpdate.plan(
      // Привязка операции к вызову `task_*` без эвристики порядка кадров
      // (D35, §17.16.5): уходит всегда, как `_meta.codelab.task`; `toolCallId`
      // опускается у `restore`, `assign` и изменений не от вызова.
      meta: replay
          ? null
          : {
              'codelab': {
                'taskChange': {
                  'op': change.op,
                  'actor': change.actor.wire,
                  'toolCallId': ?change.toolCallId,
                  'changed': [for (final item in change.changed) item.id],
                  'deleted': change.deleted,
                },
              },
            },
      entries: [
        for (final item in items)
          acp.PlanEntry(
            // `description` в ACP не уходит (§17.16.5).
            content: item.subject,
            priority: acp.PlanEntryPriority.values.byName(item.priority.name),
            status: acp.PlanEntryStatus.fromJson(item.status.wire),
            // Расширение `task` (§13.12, change `add-subagents-and-tasks`):
            // уходит всегда, независимо от объявления клиента (D9).
            meta: {
              'codelab': {
                'task': {
                  'id': item.id,
                  'owner': item.owner.value,
                  'blockedBy': item.blockedBy,
                },
              },
            },
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
  // Опции сессии изменились без запроса клиента: после применённой
  // перезагрузки конфигурации (design.md change `add-config-writer-and-reload`,
  // D8) или после смены модели командой `/model` (design.md change
  // `add-agent-builtin-slash-commands`, D6). Клиент получает полный снимок
  // опций сессии, строящийся из текущего состояния. Ни до ответа на
  // `session/new`/`session/load` (ACP-8), ни при неудачной перезагрузке
  // событие не публикуется; команда публикует его в ходе, до ответа на
  // `session/prompt` (ACP-3): порядок гарантирует мост и ядро.
  ModelOptionsChanged() => [
    acp.SessionUpdate.configOptionUpdate(configOptions: configOptions()),
  ],
  SessionTitleChanged(:final title, :final updatedAt) => [
    acp.SessionUpdate.sessionInfoUpdate(
      title: title,
      updatedAt: formatJournalTime(updatedAt),
    ),
  ],
};

/// Кадры вызова потомка с цепочкой `toolCallId` (D47 Т2, Т3).
///
/// Почему через проекцию вложенного события: статус, контент, `outcome` и
/// `summary` вызова потомка — по тем же правилам, что у вызова корня
/// (agent-acp-server «Шаги потомков деревом»); меняются только `toolCallId`
/// (цепочка) и `_meta.codelab.parentToolCallId` (префикс). Текст, мысли и
/// прочие события потомка не отправляются: проекция даёт для них пустой
/// список.
List<acp.SessionUpdate> _chained(
  AgentEvent inner,
  String prefix, {
  required List<acp.SessionConfigOption> Function() configOptions,
  SubagentFinished? subagentResult,
}) {
  if (inner is! ToolCallStarted &&
      inner is! ToolCallProgress &&
      inner is! ToolCallFinished) {
    return const [];
  }
  return [
    for (final update in projectEvent(
      inner,
      configOptions: configOptions,
      subagentResult: subagentResult,
    ))
      switch (update) {
        acp.ToolCallSessionUpdate(:final toolCall) =>
          acp.SessionUpdate.toolCall(
            toolCall: toolCall.copyWith(
              toolCallId: acp.ToolCallId(
                SubagentChains.chainOf(prefix, toolCall.toolCallId.value),
              ),
              meta: withParentToolCallId(toolCall.meta, prefix),
            ),
          ),
        acp.ToolCallUpdateSessionUpdate(:final toolCallUpdate) =>
          acp.SessionUpdate.toolCallUpdate(
            toolCallUpdate: toolCallUpdate.copyWith(
              toolCallId: acp.ToolCallId(
                SubagentChains.chainOf(prefix, toolCallUpdate.toolCallId.value),
              ),
              meta: withParentToolCallId(toolCallUpdate.meta, prefix),
            ),
          ),
        _ => update,
      },
  ];
}

/// `_meta` с добавленным `codelab.parentToolCallId` (D47 Т2): рядом с
/// `subagent` и `outcome` того же объекта `codelab`, не вместо них.
Map<String, Object?> withParentToolCallId(
  Map<String, Object?>? meta,
  String prefix,
) => {
  ...?meta,
  'codelab': {
    ...?(meta?['codelab'] as Map?)?.cast<String, Object?>(),
    'parentToolCallId': prefix,
  },
};

/// Кадр закрытия висящего вызова потомка: `failed` с
/// `_meta.codelab.outcome: "cancelled"` (D21, D47 Т3), как у отменённого
/// вызова корня; вызывается мостом до итога вызова `agent`, чьё поддерево
/// закрывается.
///
/// [isAgentCall] — закрываемый вызов сам является `agent` (вложенный ребёнок
/// или внук): клиент уже мог получить его строку прогресса, поэтому кадр несёт
/// `content: []`, как финальный кадр отменённого `agent` корня (D52 п. 1,
/// `_finished`). У прочих вызовов поддерева ключа `content` нет.
acp.SessionUpdate closedDescendantUpdate(
  String chain,
  String prefix, {
  bool isAgentCall = false,
}) => acp.SessionUpdate.toolCallUpdate(
  toolCallUpdate: acp.ToolCallUpdate(
    toolCallId: acp.ToolCallId(chain),
    status: acp.ToolCallStatus.failed,
    content: isAgentCall ? const [] : null,
    meta: {
      'codelab': {'parentToolCallId': prefix, 'outcome': 'cancelled'},
    },
  ),
);

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

acp.SessionUpdate _finished(
  ToolCallFinished event,
  SubagentFinished? subagentResult,
) => acp.SessionUpdate.toolCallUpdate(
  toolCallUpdate: acp.ToolCallUpdate(
    toolCallId: acp.ToolCallId(event.toolCallId),
    status: finishedStatus(event),
    // §13.7: у отменённого вызова — только статус и outcome; текст об
    // отмене — для модели, клиент уже видит вывод в терминале.
    // Исключение — `agent` с итогом ребёнка (D52 п. 1): клиент уже получил
    // строку прогресса `explore · …`, и без ключа `content` в финальном кадре
    // она осталась бы в состоянии `running`. Пустой список (`content: []`,
    // «only the fields being changed», ACP `08-Tool Calls.md`) снимает её;
    // у отменённого вызова другого инструмента ключа по-прежнему нет.
    content: event.outcome == ToolOutcome.cancelled
        ? (subagentResult != null ? const [] : null)
        : finishedContent(event, subagentResult: subagentResult),
    meta: finishedMeta(event, subagentResult: subagentResult),
  ),
);

/// Итоговый статус вызова: в ACP нет `cancelled` и `rejected`, поэтому
/// всё, кроме исполненного вызова, — `failed` (§13.7).
acp.ToolCallStatus finishedStatus(ToolCallFinished event) =>
    event.outcome == ToolOutcome.completed && !event.interrupted
    ? acp.ToolCallStatus.completed
    : acp.ToolCallStatus.failed;

/// Контент результата и по одному `diff` на каждый изменённый файл.
///
/// [subagentResult] — итог ребёнка вызова `agent`: клиент показывает человеку
/// тело отчёта без обёртки `<subagent-report>` и ограды `untrusted-content`,
/// которые нужны только модели (§17.3.7, D24). Ребёнок без отчёта
/// (`failed`) или с пустым отчётом (`completed`) даёт пустой список: текст
/// результата в журнале — это та же обёртка, а `SubagentFinished` текста сбоя
/// не несёт. Вызов `agent` без итога (отклонён проверкой) — как любой вызов.
///
/// Отмена (D52 п. 1): живая проекция (`_finished`) и реплей (`replay.dart`)
/// для отменённого `agent` с итогом сами подставляют `[]` и эту функцию не
/// вызывают — частичный текст ребёнка клиенту не уходит. У отменённого
/// не-`agent` живая проекция ключа `content` не шлёт вовсе.
List<acp.ToolCallContent> finishedContent(
  ToolCallFinished event, {
  SubagentFinished? subagentResult,
}) => [
  // Вызов `agent` с итогом: тело отчёта, а при пустом отчёте — ничего.
  if (subagentResult != null && subagentResult.report.isNotEmpty)
    acp.ToolCallContent.content(
      content: acp.ContentBlock.text(text: subagentResult.report),
    ),
  // Любой другой вызов, в том числе отклонённый `agent` без итога.
  if (subagentResult == null)
    for (final block in event.content)
      acp.ToolCallContent.content(content: acpContent(block)),
  for (final diff in event.diffs) acpDiff(diff),
];

/// `_meta.codelab.outcome` — исход, которого нет в статусах ACP (D10);
/// `null` — исход передаёт сам статус.
///
/// [subagentResult] — итог ребёнка вызова `agent`: добавляет
/// `_meta.codelab.subagent {id, summary, failure?}` (D24).
Map<String, Object?>? finishedMeta(
  ToolCallFinished event, {
  SubagentFinished? subagentResult,
}) {
  final outcome = event.interrupted
      ? 'interrupted'
      : switch (event.outcome) {
          ToolOutcome.completed || ToolOutcome.failed => null,
          ToolOutcome.cancelled => 'cancelled',
          ToolOutcome.rejected => 'rejected',
        };
  if (outcome == null && subagentResult == null) {
    return null;
  }
  return {
    'codelab': {
      'outcome': ?outcome,
      if (subagentResult != null)
        'subagent': subagentSummaryMeta(subagentResult),
    },
  };
}

/// `_meta.codelab.subagent` первого кадра вызова `agent` (D28): `{id, type}`;
/// `null` у любого другого вызова — расширение не протекает в чужие кадры.
Map<String, Object?>? subagentCallMeta(SubagentCallRef? ref) => ref == null
    ? null
    : {
        'codelab': {
          'subagent': {'id': ref.id, 'type': ref.type},
        },
      };

/// `_meta.codelab.subagent` финального обновления (D24): `id`, `summary` с
/// транзитивными `toolCalls`, токенами и `durationMs` из [done] и, у
/// `failed`, `failure` (формат записи `subagent`, §17.3.6).
Map<String, Object?> subagentSummaryMeta(SubagentFinished done) => {
  'id': done.subagentId,
  'summary': {
    'toolCalls': done.toolCalls,
    'tokens': {'input': done.usage.input, 'output': done.usage.output},
    'durationMs': done.duration.inMilliseconds,
  },
  if (done.status == SubagentState.failed && done.failure != null)
    'failure': ?failureWire(done.failure, done.budgetExceeded),
};

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
