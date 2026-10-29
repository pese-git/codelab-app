// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/core_stack.dart';

/// P-01, TOOL-1, PERM-1 (agent-permissions «MCP-вызов только после решения
/// политики»; design.md change `add-agent-mcp-client`, D6, D7): вызов MCP
/// доходит до сервера только после решения политики.
void main() {
  Future<List<ToolCallFinished>> run(AgentSession session, String text) async {
    final finished = <ToolCallFinished>[];
    session.events.listen((e) {
      if (e is ToolCallFinished) {
        finished.add(e);
      }
    });
    await session.prompt([TextContent(text)]);
    return finished;
  }

  test('MCP tool is not executed without a permission decision', () async {
    final server = FakeMcpServer(tools: [const FakeMcpTool('delete_issue')]);
    late RecordingGate gate;
    final stack = CoreStack.build(
      server: server,
      steps: [
        toolCallStep('c1', 'mcp__fake__delete_issue', {'id': 1}),
        endStep(),
      ],
      gate: (s) =>
          gate = RecordingGate(s, (_) => PermissionDecision.rejectOnce),
    );
    final session = await stack.session();

    final finished = await run(session, 'delete it');

    // Вопрос задан до любого обращения к серверу, итог — `rejected`,
    // ход продолжился (закрывает F5.1, P-01).
    expect(gate.requests, hasLength(1));
    expect(gate.requests.single.tool, 'mcp__fake__delete_issue');
    expect(gate.requests.single.tier, ToolTier.exec);
    expect(gate.callsAtAsk, [0]);
    expect(server.calls, isEmpty);
    expect(finished.single.outcome, ToolOutcome.rejected);
    stack.model.verify();
  });

  test('an allowed call reaches the server after the question', () async {
    final server = FakeMcpServer(tools: [const FakeMcpTool('echo')]);
    late RecordingGate gate;
    final stack = CoreStack.build(
      server: server,
      steps: [
        toolCallStep('c1', 'mcp__fake__echo', {'text': 'hi'}),
        endStep(),
      ],
      gate: (s) => gate = RecordingGate(s, (_) => PermissionDecision.allowOnce),
    );
    final session = await stack.session();

    final finished = await run(session, 'echo');

    expect(gate.callsAtAsk, [0]);
    expect(server.calls, [
      {
        'name': 'echo',
        'arguments': {'text': 'hi'},
      },
    ]);
    expect(finished.single.outcome, ToolOutcome.completed);
  });

  test(
    'plan mode rejects a falsely read-only tool without a question',
    () async {
      final server = FakeMcpServer(
        tools: [
          const FakeMcpTool('write_note', annotations: {'readOnlyHint': true}),
        ],
      );
      late RecordingGate gate;
      final stack = CoreStack.build(
        server: server,
        steps: [
          toolCallStep('c1', 'mcp__fake__write_note', {'text': 'x'}),
          endStep(),
        ],
        gate: (s) =>
            gate = RecordingGate(s, (_) => PermissionDecision.allowOnce),
      );
      final session = await stack.session(mode: ModeId.plan);

      final finished = await run(session, 'write');

      // Аннотация меняет `kind`, а не решение политики (D7).
      expect(gate.requests, isEmpty);
      expect(server.calls, isEmpty);
      expect(finished.single.outcome, ToolOutcome.rejected);
    },
  );

  test('read-only hint does not spare the question in standard mode', () async {
    final server = FakeMcpServer(
      tools: [
        const FakeMcpTool('peek', annotations: {'readOnlyHint': true}),
      ],
    );
    late RecordingGate gate;
    final stack = CoreStack.build(
      server: server,
      steps: [toolCallStep('c1', 'mcp__fake__peek', {}), endStep()],
      gate: (s) =>
          gate = RecordingGate(s, (_) => PermissionDecision.rejectOnce),
    );
    final session = await stack.session();

    await run(session, 'peek');

    expect(gate.requests, hasLength(1));
    expect(gate.requests.single.kind, ToolKind.read);
    expect(server.calls, isEmpty);
  });

  test('allow-always covers the same arguments only', () async {
    final server = FakeMcpServer(tools: [const FakeMcpTool('echo')]);
    late RecordingGate gate;
    final stack = CoreStack.build(
      server: server,
      steps: [
        toolCallStep('c1', 'mcp__fake__echo', {'text': 'a'}),
        toolCallStep('c2', 'mcp__fake__echo', {'text': 'a'}),
        toolCallStep('c3', 'mcp__fake__echo', {'text': 'b'}),
        endStep(),
      ],
      gate: (s) =>
          gate = RecordingGate(s, (_) => PermissionDecision.allowAlways),
    );
    final session = await stack.session();

    await run(session, 'echo');

    // Второй вызов с теми же аргументами не спрашивался, третий — спросили.
    expect(gate.requests.map((r) => r.rawInput['text']), ['a', 'b']);
    expect(server.calls, hasLength(3));
  });
}
