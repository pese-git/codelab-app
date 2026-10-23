import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/pairing.dart';
import 'package:test/test.dart';

import '../support/models.dart';

final _time = DateTime.utc(2026);

UserMessage _user(String text) =>
    UserMessage([TextContent(text)], timestamp: _time);

AssistantMessage _assistant(List<String> callIds) => AssistantMessage(
  content: [
    for (final id in callIds)
      ToolCall(id: id, name: 'read', arguments: {'path': id}),
  ],
  model: testModel,
  usage: Usage.zero,
  stopReason: StopReason.toolUse,
  timestamp: _time,
);

ToolResultMessage _result(String id) => ToolResultMessage(
  toolCallId: id,
  toolName: 'read',
  content: [TextContent('result $id')],
  isError: false,
  timestamp: _time,
);

String _describe(Message m) => switch (m) {
  UserMessage(:final content) =>
    'user(${(content.single as TextContent).text})',
  AssistantMessage() => 'assistant(${m.toolCalls.map((c) => c.id).join(', ')})',
  ToolResultMessage(:final toolCallId, :final isError, :final content) =>
    isError
        ? 'result($toolCallId, synthetic: ${(content.single as TextContent).text})'
        : 'result($toolCallId)',
};

void main() {
  test('the example of §6.3.3', () {
    final repair = repairToolPairing([
      _user('go'),
      _assistant(['call_1', 'call_2']),
      _result('call_1'),
      _user('stop'),
      _result('call_9'),
    ]);

    expect(repair.messages.map(_describe), [
      'user(go)',
      'assistant(call_1, call_2)',
      'result(call_1)',
      'result(call_2, synthetic: '
          'Tool call was interrupted before it produced a result.)',
      'user(stop)',
      'user([Note: a tool result without a matching call was removed: '
          'read call_9])',
    ]);
    expect(repair.report.actions, [
      'synthesized call_2',
      'dropped orphan call_9',
    ]);
  });

  test('a result separated from its call is moved to it', () {
    final repair = repairToolPairing([
      _user('go'),
      _assistant(['a', 'b']),
      _result('b'),
      _user('steer'),
      _result('a'),
    ]);

    expect(repair.messages.map(_describe), [
      'user(go)',
      'assistant(a, b)',
      'result(a)',
      'result(b)',
      'user(steer)',
    ]);
    expect(repair.report.actions, ['moved a']);
  });

  test('duplicate ids get _dup<N> on both sides', () {
    final repair = repairToolPairing([
      _user('go'),
      _assistant(['x']),
      _result('x'),
      _assistant(['x']),
      _result('x'),
    ]);

    expect(repair.messages.map(_describe), [
      'user(go)',
      'assistant(x)',
      'result(x)',
      'assistant(x_dup2)',
      'result(x_dup2)',
    ]);
    expect(repair.report.actions, ['renamed duplicate x to x_dup2']);
  });

  test('a valid transcript is left as is with an empty report', () {
    final messages = [
      _user('go'),
      _assistant(['a']),
      _result('a'),
    ];

    final repair = repairToolPairing(messages);

    expect(repair.messages, messages);
    expect(repair.report.isEmpty, isTrue);
  });

  test('the input list is not modified', () {
    final messages = [
      _user('go'),
      _assistant(['a']),
    ];

    repairToolPairing(messages);

    expect(messages, hasLength(2));
  });
}
