// Тесты по ревью итерации 5 change `add-subagents-and-tasks`: операция со
// списком задач в хвосте работающего `agent` — тихая строка, а не «Think»
// (D48 п. 3; acp-client-kit «Итог и хвост субагента»).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallItem _call(String id, {ToolKind kind = ToolKind.read}) => ToolCallItem(
  id: 't1/tool-call_1/$id',
  toolCallId: ToolCallId('call_1/$id'),
  title: kind == ToolKind.read ? 'Read' : 'task_update',
  details: ToolCallView(
    kind: kind,
    status: ToolCallStatusView.succeeded,
    rawInput: const {'path': '/work/lib/a.dart'},
    parentToolCallId: 'call_1',
  ),
);

ToolCallItem _agentWithTail(ToolCallItem read, ToolCallItem op) {
  final ops = TaskOpsItem(id: op.id, completed: const ['1']);
  return ToolCallItem(
    id: 't1/tool-call_1',
    toolCallId: const ToolCallId('call_1'),
    title: 'agent',
    details: const ToolCallView(
      kind: ToolKind.think,
      status: ToolCallStatusView.running,
      rawInput: {'type': 'explore', 'description': 'Find auth code'},
      subagentCall: SubagentCallView(id: 'sub_a1', type: 'explore'),
    ),
    children: [read, ops],
    tail: SubagentTailView(calls: [read, op], operations: {op.toolCallId: ops}),
    subtreeCalls: 2,
  );
}

void main() {
  final read = _call('call_2');
  final op = _call('call_3', kind: ToolKind.think);
  final agent = _agentWithTail(read, op);

  List<CodeLabTranscriptRow> rows() => transcriptRowsOf(
    [agent],
    cwd: '/work',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
  );

  test('the tail keeps an operation as a quiet task row', () {
    final root = rows().single as CodeLabToolCallRow;

    expect(root.subagent?.tail, hasLength(2));
    expect(root.subagent?.tail[0], isA<CodeLabToolCallRow>());
    expect(root.subagent?.tail[1], isA<CodeLabTaskOpsRow>());
    expect((root.subagent?.tail[1] as CodeLabTaskOpsRow).text, 'Task #1 done');
  });

  testWidgets('a running agent shows the operation in the tail as a quiet '
      'line, not as Think', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 700,
          height: 400,
          child: CodeLabTranscriptPanel(rows: rows()),
        ),
      ),
    );

    expect(find.text('Task #1 done'), findsOneWidget);
    expect(find.textContaining('Think'), findsNothing);
  });
}
