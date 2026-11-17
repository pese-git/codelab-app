// Операция со списком задач в хвосте работающего субагента (находка 1 ревью
// итерации 5 `add-subagents-and-tasks`; acp-client-kit «Итог и хвост
// субагента», D48 п. 3): операция потомка входит в хвост и рисуется тихой
// строкой (`TaskOpsItem.text`, приглушённая), а не обычным вызовом `think`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

final _sgr = RegExp('\x1b\\[[0-9;]*m');

ToolCallItem _call(
  String id,
  String title, {
  ToolCallStatusView status = ToolCallStatusView.succeeded,
  ToolKind kind = ToolKind.read,
  String? parent,
  List<TranscriptItem> children = const [],
  SubagentCallView? subagentCall,
  SubagentSummaryView? summary,
  List<String> textOutput = const [],
  SubagentTailView tail = const SubagentTailView(),
  int subtreeCalls = 0,
}) => ToolCallItem(
  id: 'item-${id.replaceAll('/', '-')}',
  toolCallId: ToolCallId(id),
  title: title,
  details: ToolCallView(
    kind: kind,
    status: status,
    parentToolCallId: parent,
    rawInput: subagentCall == null
        ? null
        : {'type': subagentCall.type, 'description': 'Map callers'},
    subagentCall: subagentCall,
    subagentSummary: summary,
    textOutput: textOutput,
  ),
  children: children,
  tail: tail,
  subtreeCalls: subtreeCalls,
);

const _agentCall = SubagentCallView(id: 'sub_a1', type: 'explore');

ToolCallItem _read(String n, {ToolCallStatusView? status}) => _call(
  'call_1/call_$n',
  'Read lib/f$n.dart',
  parent: 'call_1',
  status: status ?? ToolCallStatusView.succeeded,
);

void main() {
  test('an operation in the tail is a quiet row, not a think call', () {
    final op = TaskOpsItem(id: 'item-op', added: const ['1']);
    final operation = _call(
      'call_1/call_2',
      'Think',
      parent: 'call_1',
      kind: ToolKind.think,
    );
    final running = _call(
      'call_1',
      'Subagent explore: Map callers',
      status: ToolCallStatusView.running,
      kind: ToolKind.think,
      subagentCall: _agentCall,
      tail: SubagentTailView(
        calls: [_read('1'), operation, _read('3')],
        operations: {operation.toolCallId: op},
      ),
      subtreeCalls: 3,
    );

    final out = TranscriptLayout()
        .lines(
          SessionView(
            revision: 1,
            status: SessionStatusView.running,
            transcript: [running],
          ),
          width: 120,
        )
        .map((l) => l.replaceAll(_sgr, ''))
        .toList();

    expect(out, hasLength(4));
    expect(out[1], contains('lib/f1.dart'));
    expect(out[2].trimRight(), '  ↳ Task #1 added to the plan');
    expect(out[3], contains('lib/f3.dart'));
  });
}
