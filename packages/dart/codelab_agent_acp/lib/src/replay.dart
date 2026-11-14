import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'event_projection.dart';

/// История сессии для `session/load` (`agent-core-architecture` §13.5,
/// шаг 5).
///
/// Почему отдельно от живой проекции: живой ход передаёт вызов несколькими
/// кадрами (`pending` → `in_progress` → итог) и дельтами текста, а реплей —
/// одним кадром на блок и на вызов, сразу с итоговым статусом. Таблицы
/// разные, а помощники кадров вызова общие с §13.7.
///
/// Как использовать: мост сессии передаёт [replayUpdates] события
/// `AgentSession.replay()` и ставит кадры в очередь до хвоста (план, режим,
/// опции, команды, заголовок) и ответа `session/load`.
///
/// `replay()` уже пропустил служебные user-записи (§8.2.5); `compaction`,
/// план, режим и заголовок посреди истории не отправляются — последние
/// значения идут хвостом (§13.5, шаг 6).
List<acp.SessionUpdate> replayUpdates(Iterable<AgentEvent> events) {
  final started = <String, ToolCallStarted>{};
  // Итог ребёнка приходит до `ToolCallFinished(agent)` (SUB-10, D24).
  final subagentDone = <String, SubagentFinished>{};
  final updates = <acp.SessionUpdate>[];
  for (final event in events) {
    switch (event) {
      case MessageEnded(message: UserMessage(:final content)):
        for (final block in content) {
          updates.add(
            acp.SessionUpdate.userMessageChunk(content: acpContent(block)),
          );
        }
      case MessageEnded(message: AssistantMessage(:final content)):
        for (final block in content) {
          switch (block) {
            case ThinkingContent(:final thinking) when thinking.isNotEmpty:
              updates.add(
                acp.SessionUpdate.agentThoughtChunk(
                  content: acp.ContentBlock.text(text: thinking),
                ),
              );
            case TextContent() || ImageContent():
              updates.add(
                acp.SessionUpdate.agentMessageChunk(content: acpContent(block)),
              );
            // Вызов уходит одним tool_call по его результату.
            case ThinkingContent() || ToolCall():
              break;
          }
        }
      case ToolCallStarted(:final toolCallId):
        started[toolCallId] = event;
      case SubagentFinished(:final parentToolCallId):
        subagentDone[parentToolCallId] = event;
      case ToolCallFinished(:final toolCallId):
        final call = started.remove(toolCallId);
        final done = subagentDone.remove(toolCallId);
        // Отклонённый проверкой вызов `agent`: записи `subagent` нет, а живой
        // кадр нёс резерв id. Id при реплее не выдумывается (он ни на что не
        // ссылается), `type` — из аргументов вызова (D28, Т15).
        final callMeta =
            call != null && call.tool == 'agent' && call.subagent == null
            ? {
                'codelab': {
                  'subagent': {
                    'type': switch (call.input['type']) {
                      final String type => type,
                      _ => 'general',
                    },
                  },
                },
              }
            : subagentCallMeta(call?.subagent);
        final finishMeta = finishedMeta(event, subagentResult: done);
        updates.add(
          acp.SessionUpdate.toolCall(
            toolCall: acp.ToolCall(
              toolCallId: acp.ToolCallId(toolCallId),
              title: call?.title ?? toolCallId,
              kind: acp.ToolKind.values.byName(
                (call?.kind ?? ToolKind.other).name,
              ),
              status: finishedStatus(event),
              rawInput: call?.input,
              locations: acpLocations(call?.locations ?? const []),
              content: finishedContent(event, subagentResult: done),
              meta: _mergeMeta(callMeta, finishMeta),
            ),
          ),
        );
      default:
        break;
    }
  }
  return updates;
}

/// Сливает `_meta.codelab` первого кадра (`{id, type}`, D28) и итога
/// (`outcome`, `summary`, `failure`, D24): реплей отдаёт вызов одним
/// `tool_call`, поэтому `subagent` получает поля обоих.
Map<String, Object?>? _mergeMeta(
  Map<String, Object?>? call,
  Map<String, Object?>? finished,
) {
  if (call == null || finished == null) {
    return call ?? finished;
  }
  final callCodelab = call['codelab']! as Map<String, Object?>;
  final finishedCodelab = finished['codelab']! as Map<String, Object?>;
  final callSub = callCodelab['subagent'] as Map<String, Object?>?;
  final finishedSub = finishedCodelab['subagent'] as Map<String, Object?>?;
  return {
    'codelab': {
      ...callCodelab,
      ...finishedCodelab,
      if (callSub != null || finishedSub != null)
        'subagent': {...?callSub, ...?finishedSub},
    },
  };
}
