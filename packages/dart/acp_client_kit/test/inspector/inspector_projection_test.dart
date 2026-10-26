// Тесты проекции инспектора (tasks 6.1; design D9): перенос
// `_inspectorEntriesFor*` из `CodeLabShellCubit`.

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;
  const inspector = InspectorProjection();

  setUp(() async {
    agent = KitAgent();
    await agent.start();
  });
  tearDown(() => agent.dispose());

  AcpSession session(String id) =>
      agent.application.sessionById(SessionId(id))!;

  test('a session without turns shows one session entry', () async {
    await agent.newSession('s-1');

    final entries = inspector.project(session('s-1'));

    expect(entries.single.category, InspectorCategory.protocol);
    expect(entries.single.title, 'Session s-1');
    expect(
      entries.single.details,
      contains(const InspectorDetail(label: 'CWD', value: '/work')),
    );
  });

  test('the last turn shows approvals, tool calls, updates and the turn '
      'itself, in that order', () async {
    final handle = await agent.newSession('s-1');
    final turn = await agent.prompt(handle, 'go');
    agent.update('s-1', {
      'sessionUpdate': 'tool_call',
      'toolCallId': 'call-1',
      'title': 'Run tests',
      'kind': 'execute',
      'status': 'in_progress',
      'locations': [
        {'path': '/work/a.dart', 'line': 3},
      ],
    });
    agent.requestPermission(
      id: 1,
      sessionId: 's-1',
      toolCallId: 'call-1',
      rawInput: const {'command': 'dart test', 'api_key': 'sk-123'},
    );

    final entries = inspector.project(session('s-1'));

    expect(entries.map((entry) => entry.category), [
      InspectorCategory.approval,
      InspectorCategory.toolCall,
      InspectorCategory.protocol,
      InspectorCategory.protocol,
    ]);
    final approval = entries.first;
    expect(approval.title, 'Approval permission-1');
    expect(approval.status, 'pending');
    expect(
      approval.details,
      contains(
        const InspectorDetail(
          label: 'Options',
          value: 'Allow once (allow_once), Reject (reject_once)',
        ),
      ),
    );
    expect(approval.rawInput, contains('dart test'));
    expect(approval.rawInput, isNot(contains('sk-123')));

    final toolCall = entries[1];
    expect(toolCall.title, 'Run tests');
    expect(
      toolCall.details,
      contains(
        const InspectorDetail(label: 'Location', value: '/work/a.dart:3'),
      ),
    );
    expect(entries[2].title, 'session/update tool_call');
    expect(entries.last.title, 'Prompt turn turn-1');
    expect(entries.last.status, 'awaitingApproval');

    await handle.respond(
      handle.current.pendingApprovals.single.approvalId,
      const PermissionOptionId('allow-once'),
    );
    agent.respond(turn.request, const {'stopReason': 'end_turn'});
    await turn.done;

    final finished = inspector.project(session('s-1'));
    expect(finished.last.status, 'end_turn');
    expect(
      finished.last.details,
      contains(const InspectorDetail(label: 'Stop reason', value: 'end_turn')),
    );
  });
}
