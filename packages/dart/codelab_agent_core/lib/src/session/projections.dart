/// Проекции журнала: контекст модели, реплей, сводка и ремонт прерванного
/// хода (`agent-core-architecture` §8.3, §8.7, §8.8, §8.10).
///
/// Почему проекции, а не отдельные копии истории: журнал — единственный
/// источник истины (§8.1). Транскрипт `Agent`, события `session/load` и
/// строка списка сессий строятся из него чистыми функциями, поэтому
/// одинаковый снимок всегда даёт одинаковый результат (SES-7).
///
/// Как использовать: сессия вызывает [buildLlmContext] при загрузке и после
/// сжатия, [buildReplay] для `replay()`, [findInterruptedCalls] и
/// [healInterruptedTurn] сразу после открытия журнала; хранилища вызывают
/// [summarize] для списка.
library;

import '../llm/messages.dart';
import '../llm/usage.dart';
import '../loop/agent_events.dart';
import '../permissions/modes.dart';
import '../prompts/prompts.g.dart';
import '../tools/agent_tool.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import 'ids.dart';
import 'records.dart';
import 'session_store.dart';
import 'tree.dart';
import 'user_words.dart';

/// Контекст модели из журнала (§8.7).
final class LlmContextProjection {
  LlmContextProjection({
    required List<Message> messages,
    required Map<String, String> config,
    this.model,
    this.modeId,
    this.lastCompaction,
  }) : messages = List.unmodifiable(messages),
       config = Map.unmodifiable(config);

  /// То, что уйдёт модели (до `transformContext`).
  final List<Message> messages;

  /// Последняя `model_change` ветки.
  final ModelChangeRecord? model;

  /// Последняя `mode_change` ветки.
  final String? modeId;

  /// Последние `config_change` по `optionId`.
  final Map<String, String> config;
  final CompactionRecord? lastCompaction;
}

/// Сообщения активной ветки для модели (§8.7).
///
/// После последнего сжатия записи до `firstKeptId` заменяются резюме.
/// Usage ответов до сжатия в проекции обнуляется: оценка токенов (§9.3)
/// якорится на usage последнего ответа, а ответы до сжатия несут размер
/// несжатого контекста — без обнуления сжатие запускалось бы снова и снова.
/// Ремонт парности здесь не делается: он применяется только к payload
/// запроса (§6.3).
LlmContextProjection buildLlmContext(
  SessionSnapshot snapshot, {
  Logger? logger,
}) {
  final path = pathToLeaf(snapshot, logger: logger);
  ModelChangeRecord? model;
  String? modeId;
  final config = <String, String>{};
  var compactionIndex = -1;
  for (final (i, record) in path.indexed) {
    switch (record) {
      case ModelChangeRecord():
        model = record;
      case ModeChangeRecord(modeId: final mode):
        modeId = mode;
      case ConfigChangeRecord(:final optionId, :final value):
        config[optionId] = value;
      case CompactionRecord():
        compactionIndex = i;
      default:
        break;
    }
  }
  var kept = path;
  CompactionRecord? compaction;
  if (compactionIndex >= 0) {
    compaction = path[compactionIndex] as CompactionRecord;
    final firstKept = path.indexWhere((r) => r.id == compaction!.firstKeptId);
    final before = firstKept >= 0 && firstKept < compactionIndex
        ? path.sublist(firstKept, compactionIndex)
        : const <SessionRecord>[];
    if (firstKept < 0) {
      logger?.log(
        LogLevel.warning,
        'session.compaction.lost_anchor',
        fields: {'first_kept_id': compaction.firstKeptId},
      );
    }
    kept = [compaction, ...before, ...path.sublist(compactionIndex + 1)];
  }
  final position = {for (final (i, r) in path.indexed) r.id: i};
  final messages = <Message>[];
  for (final record in kept) {
    switch (record) {
      case MessageRecord(:final message):
        messages.add(
          message is AssistantMessage && position[record.id]! < compactionIndex
              ? message.copyWith(usage: Usage.zero)
              : message,
        );
      case CompactionRecord(:final summary, :final timestamp):
        messages.add(
          UserMessage([
            TextContent(
              Prompts.compactionSummaryWrapper.render({'summary': summary}),
            ),
          ], timestamp: timestamp),
        );
      default:
        break;
    }
  }
  return LlmContextProjection(
    messages: messages,
    config: config,
    model: model,
    modeId: modeId,
    lastCompaction: compaction,
  );
}

/// События журнала активной ветки для `session/load` (design.md, D4).
///
/// Служебные user-сообщения (подсказки цикла и прочие без слов
/// пользователя) пропускаются: клиент не должен показывать их репликой
/// человека. Записи до сжатия реплей показывает — журнал их хранит.
List<AgentEvent> buildReplay(SessionSnapshot snapshot, {Logger? logger}) {
  final session = snapshot.header.id;
  final calls = <String, ToolCall>{};
  final events = <AgentEvent>[];
  for (final record in pathToLeaf(snapshot, logger: logger)) {
    switch (record) {
      case MessageRecord(message: final ToolResultMessage result):
        final call = calls[result.toolCallId];
        final meta = record.toolMeta;
        events
          ..add(
            ToolCallStarted(
              session,
              toolCallId: result.toolCallId,
              tool: result.toolName,
              kind: meta?.kind ?? ToolKind.other,
              title: meta?.title ?? result.toolName,
              input: call?.arguments ?? const {},
              locations: meta?.locations ?? const [],
            ),
          )
          ..add(
            ToolCallFinished(
              session,
              toolCallId: result.toolCallId,
              outcome: _outcome(record.outcome, result),
              content: result.content,
              diffs: [?record.diff],
              interrupted: record.outcome == 'interrupted',
            ),
          );
      case MessageRecord(:final message):
        if (message is UserMessage && !isUserWords(record, logger: logger)) {
          continue;
        }
        if (message is AssistantMessage) {
          for (final call in message.toolCalls) {
            calls[call.id] = call;
          }
        }
        events
          ..add(MessageStarted(session, message: message))
          ..add(MessageEnded(session, message: message));
      case PlanRecord(:final entries):
        events.add(PlanUpdated(session, entries: entries));
      case ModeChangeRecord(:final modeId):
        if (ModeId.values.where((m) => m.value == modeId).firstOrNull
            case final mode?) {
          events.add(ModeChanged(session, mode: mode));
        }
      case CompactionRecord(:final tokensBefore, :final tokensAfter):
        events.add(
          ContextCompacted(
            session,
            tokensBefore: tokensBefore,
            tokensAfter: tokensAfter,
          ),
        );
      case SessionInfoRecord(title: final title?, :final timestamp)
          when title.isNotEmpty:
        events.add(
          SessionTitleChanged(session, title: title, updatedAt: timestamp),
        );
      default:
        break;
    }
  }
  return events;
}

ToolOutcome _outcome(String? outcome, ToolResultMessage result) =>
    switch (outcome) {
      'completed' => ToolOutcome.completed,
      'cancelled' => ToolOutcome.cancelled,
      'rejected' => ToolOutcome.rejected,
      'failed' || 'interrupted' => ToolOutcome.failed,
      _ => result.isError ? ToolOutcome.failed : ToolOutcome.completed,
    };

/// Текст синтетического результата прерванного вызова (§8.8).
const interruptedResultText =
    'Tool call was interrupted: the agent process stopped before the result '
    'was recorded. The tool may have partially run. Check the current state '
    '(for example, re-read the file) before retrying.';

/// Вызовы последнего ответа ветки без результата (§8.8, шаг 1).
List<ToolCall> findInterruptedCalls(SessionSnapshot snapshot) {
  final path = pathToLeaf(snapshot);
  final last = path.lastIndexWhere(
    (r) => r is MessageRecord && r.message is AssistantMessage,
  );
  if (last < 0) {
    return const [];
  }
  final answer = (path[last] as MessageRecord).message as AssistantMessage;
  final answered = {
    for (final record in path.skip(last + 1))
      if (record case MessageRecord(message: final ToolResultMessage result))
        result.toolCallId,
  };
  return [
    for (final call in answer.toolCalls)
      if (!answered.contains(call.id)) call,
  ];
}

/// Синтетические результаты `interrupted` для вызовов без результата
/// (§8.8, шаг 2; SES-10).
///
/// Почему не повтор: `exec` или `write` могли быть неидемпотентны;
/// повторить `git push` после сбоя опаснее, чем потерять шаг. Модель
/// получает честный результат и решает сама.
///
/// Записи идут цепочкой от листа снимка; [meta] — заголовки вызовов,
/// которые сессия получила от `present()`; без него — имя инструмента.
List<MessageRecord> healInterruptedTurn(
  SessionSnapshot snapshot,
  IdGenerator ids,
  Clock clock, {
  Map<String, ToolMeta> meta = const {},
}) {
  final taken = {...snapshot.byId.keys};
  var parent = snapshot.leafId;
  final now = clock.now();
  final healed = <MessageRecord>[];
  for (final call in findInterruptedCalls(snapshot)) {
    final id = newRecordId(ids, taken.contains);
    taken.add(id);
    healed.add(
      MessageRecord(
        id: id,
        parentId: parent,
        timestamp: now,
        outcome: 'interrupted',
        toolMeta:
            meta[call.id] ?? ToolMeta(title: call.name, kind: ToolKind.other),
        message: ToolResultMessage(
          toolCallId: call.id,
          toolName: call.name,
          content: const [TextContent(interruptedResultText)],
          isError: true,
          timestamp: now,
        ),
      ),
    );
    parent = id;
  }
  return healed;
}
