import 'package:acp_protocol/acp_protocol.dart' as acp;
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
      case ToolCallFinished(:final toolCallId):
        final call = started.remove(toolCallId);
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
              content: finishedContent(event),
              meta: finishedMeta(event),
            ),
          ),
        );
      default:
        break;
    }
  }
  return updates;
}
