import '../llm/messages.dart';

/// Pairing of tool calls and results in the payload
/// (`agent-core-architecture` §6.3.3): no request to the model contains a
/// result without its call or a call without a result (TOOL-6). The repair
/// works on the payload only; the transcript is never changed (LOOP-7).

const interruptedResultText =
    'Tool call was interrupted before it produced a result.';

final class PairingReport {
  PairingReport(List<String> actions) : actions = List.unmodifiable(actions);

  /// One line per action: `synthesized <id>`, `moved <id>`,
  /// `dropped orphan <id>`, `renamed duplicate <id> to <new>`.
  final List<String> actions;

  bool get isEmpty => actions.isEmpty;
}

final class PairingRepair {
  PairingRepair(List<Message> messages, this.report)
    : messages = List.unmodifiable(messages);

  final List<Message> messages;
  final PairingReport report;
}

PairingRepair repairToolPairing(List<Message> messages) {
  final actions = <String>[];
  final renamed = _renameDuplicates(messages, actions);
  final out = <Message>[];
  final consumed = <int>{};
  for (final (i, message) in renamed.indexed) {
    switch (message) {
      case AssistantMessage() when message.toolCalls.isNotEmpty:
        out.add(message);
        final pending = [for (final call in message.toolCalls) call.id];
        final found = <String, int>{};
        var adjacent = true;
        for (var j = i + 1; j < renamed.length; j++) {
          final next = renamed[j];
          if (next is AssistantMessage && next.toolCalls.isNotEmpty) {
            break;
          }
          if (next is! ToolResultMessage) {
            adjacent = false;
            continue;
          }
          if (pending.contains(next.toolCallId) &&
              !found.containsKey(next.toolCallId) &&
              !consumed.contains(j)) {
            found[next.toolCallId] = j;
            if (!adjacent) {
              actions.add('moved ${next.toolCallId}');
            }
          }
        }
        for (final call in message.toolCalls) {
          final index = found[call.id];
          if (index != null) {
            consumed.add(index);
            out.add(renamed[index]);
          } else {
            actions.add('synthesized ${call.id}');
            out.add(
              ToolResultMessage(
                toolCallId: call.id,
                toolName: call.name,
                content: const [TextContent(interruptedResultText)],
                isError: true,
                timestamp: message.timestamp,
              ),
            );
          }
        }
      case ToolResultMessage(:final toolCallId, :final toolName):
        if (consumed.contains(i)) {
          continue;
        }
        actions.add('dropped orphan $toolCallId');
        out.add(
          UserMessage([
            TextContent(
              '[Note: a tool result without a matching call was removed: '
              '$toolName $toolCallId]',
            ),
          ], timestamp: message.timestamp),
        );
      default:
        out.add(message);
    }
  }
  return PairingRepair(
    actions.isEmpty ? messages : out,
    PairingReport(actions),
  );
}

/// A second call with an already used id, and the results after it, get
/// `_dup<N>` (old journals may contain them).
List<Message> _renameDuplicates(List<Message> messages, List<String> actions) {
  final seen = <String, int>{};
  final current = <String, String>{};
  final out = <Message>[];
  for (final message in messages) {
    switch (message) {
      case AssistantMessage() when message.toolCalls.isNotEmpty:
        var changed = false;
        final content = [
          for (final block in message.content)
            if (block is ToolCall)
              () {
                final count = (seen[block.id] ?? 0) + 1;
                seen[block.id] = count;
                if (count == 1) {
                  current[block.id] = block.id;
                  return block;
                }
                final name = '${block.id}_dup$count';
                current[block.id] = name;
                changed = true;
                actions.add('renamed duplicate ${block.id} to $name');
                return ToolCall(
                  id: name,
                  name: block.name,
                  arguments: block.arguments,
                  signature: block.signature,
                );
              }()
            else
              block,
        ];
        out.add(changed ? message.copyWith(content: content) : message);
      case ToolResultMessage(:final toolCallId)
          when current[toolCallId] != null && current[toolCallId] != toolCallId:
        out.add(
          ToolResultMessage(
            toolCallId: current[toolCallId]!,
            toolName: message.toolName,
            content: message.content,
            isError: message.isError,
            timestamp: message.timestamp,
          ),
        );
      default:
        out.add(message);
    }
  }
  return out;
}
