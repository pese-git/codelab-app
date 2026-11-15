/// Реплей дерева субагентов для `session/load` (`agent-core/17-3-subagents.md`
/// §17.3.3, `agent-core/08-sessions.md` §8.3; design.md change
/// `add-subagents-and-tasks`, D47 Т5, Т6).
library;

import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../tools/agent_tool.dart';
import '../util/logger.dart';
import 'projections.dart';
import 'records.dart';
import 'session_store.dart';
import 'tree.dart';

/// Наибольшая глубина потомка: верхняя граница `subagents.max_depth`
/// (конфигурация ограничивает его диапазоном 1..3, D45).
const int replayTreeMaxDepth = 3;

/// События корня ([buildReplay]) и `SubagentActivity` всех потомков,
/// прочитанные из их журналов (D47 Т6).
///
/// Почему отдельная функция, а не расширение [buildReplay]: тот синхронный и
/// прежний (D1) — им пользуется реплей клиенту без согласия
/// `subagentToolCalls`; журналы потомков читаются через порт и потому
/// асинхронны.
///
/// Для чего: события журнала ребёнка идут сразу после `ToolCallFinished`
/// вызова `agent`, обёрнутые адресом так же, как вживую: `parentToolCallId` —
/// сырой id вызова в сессии родителя, `path` — предки без самого потомка,
/// `depth` — глубина потомка; обёртка плоская, `sessionId` обёртки — корень.
/// Вызов без результата в журнале потомка (пережил `cancel_grace`)
/// проигрывается `cancelled`: вживую адаптер закрыл его так же.
///
/// Как использовать: `AgentSession.replayTree()` передаёт снимок корня,
/// взятый синхронно, и хранилище. Журналы читаются только через
/// `openChildReadOnly` — без записи и без lease, поэтому живой потомок не
/// страдает. Обход не глубже [replayTreeMaxDepth] и с памятью посещённых
/// адресов (цикл в подложенных ссылках). Журнал, который не открылся,
/// даёт лог `subagent.replay_failed` (`session_id`, `subagent_id`,
/// `error_class`, без пути и текста ошибки) и реплей без потомков этого
/// вызова; `session/load` не падает.
Future<List<AgentEvent>> buildReplayTree(
  SessionSnapshot root, {
  required SessionStore store,
  required Logger logger,
  int maxDepth = replayTreeMaxDepth,
}) async {
  final rootId = root.header.id;
  final visited = <String>{};

  // События одного журнала [snapshot] плюс потомки его вызовов `agent`.
  Future<List<AgentEvent>> expand(
    SessionSnapshot snapshot,
    List<AgentEvent> events, {
    required int depth,
    required List<String> path,
    required String? ownId,
  }) async {
    final children = <String, SubagentRecord>{
      for (final record in pathToLeaf(snapshot, logger: logger))
        if (record is SubagentRecord) record.toolCallId: record,
    };
    // Предки потомков этого журнала: путь владельца плюс он сам (у корня —
    // пусто); это же `path` обёртки и `path` владельца для следующего уровня.
    final ownPath = [...path, ?ownId];
    final out = <AgentEvent>[];
    for (final event in events) {
      out.add(event);
      if (event is! ToolCallFinished) {
        continue;
      }
      final child = children[event.toolCallId];
      final journal = child?.journal;
      if (child == null || journal == null || depth + 1 > maxDepth) {
        continue;
      }
      // Адрес читается один раз: повторная ссылка — цикл или подмена.
      if (!visited.add(journal)) {
        continue;
      }
      final SessionSnapshot childSnapshot;
      try {
        childSnapshot = await store.openChildReadOnly(
          journal,
          rootSessionId: rootId,
        );
      } on Object catch (error) {
        logger.log(
          LogLevel.warning,
          'subagent.replay_failed',
          fields: {
            'session_id': rootId.value,
            'subagent_id': child.subagentId,
            'error_class': error.runtimeType.toString(),
          },
        );
        continue;
      }
      final inner = await expand(
        childSnapshot,
        [
          ...buildReplay(childSnapshot, logger: logger),
          ..._unfinishedCalls(childSnapshot, logger),
        ],
        depth: depth + 1,
        path: ownPath,
        ownId: child.subagentId,
      );
      for (final innerEvent in inner) {
        out.add(
          innerEvent is SubagentActivity
              ? SubagentActivity(
                  rootId,
                  subagentId: innerEvent.subagentId,
                  parentToolCallId: innerEvent.parentToolCallId,
                  path: innerEvent.path,
                  depth: innerEvent.depth,
                  event: innerEvent.event,
                )
              : SubagentActivity(
                  rootId,
                  subagentId: child.subagentId,
                  parentToolCallId: child.toolCallId,
                  path: ownPath,
                  depth: depth + 1,
                  event: innerEvent,
                ),
        );
      }
    }
    return out;
  }

  return expand(
    root,
    buildReplay(root, logger: logger),
    depth: 0,
    path: const [],
    ownId: null,
  );
}

/// Вызовы активной ветки без результата: `started` и `cancelled` пара на
/// каждый (D47 Т6). Лечение журнал потомка не трогает (запись `subagent`
/// итоговая), поэтому без этого реплей потерял бы строку, которую вживую
/// закрыли так же.
List<AgentEvent> _unfinishedCalls(SessionSnapshot snapshot, Logger logger) {
  final calls = <String, ToolCall>{};
  final answered = <String>{};
  for (final record in pathToLeaf(snapshot, logger: logger)) {
    if (record case MessageRecord(:final message)) {
      if (message is AssistantMessage) {
        for (final call in message.toolCalls) {
          calls[call.id] = call;
        }
      } else if (message is ToolResultMessage) {
        answered.add(message.toolCallId);
      }
    }
  }
  final session = snapshot.header.id;
  return [
    for (final call in calls.values)
      if (!answered.contains(call.id)) ...[
        ToolCallStarted(
          session,
          toolCallId: call.id,
          tool: call.name,
          kind: ToolKind.other,
          title: call.name,
          input: call.arguments,
        ),
        ToolCallFinished(
          session,
          toolCallId: call.id,
          outcome: ToolOutcome.cancelled,
          content: const [],
        ),
      ],
  ];
}
