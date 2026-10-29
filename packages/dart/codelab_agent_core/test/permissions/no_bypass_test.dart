import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../tools/fake_shell.dart';
import '../tools/fake_tools.dart';
import 'fake_gate.dart';

/// `core/no-tool-bypasses-gate` (P-01, PERM-1, TOOL-1; agent-permissions
/// «MCP-вызов только после решения политики»): ни один инструмент реестра
/// сессии — встроенный или MCP — не исполняется, пока политика не
/// разрешила вызов.
void main() {
  test('with a rejecting gate no tool of the session executes', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    final shell = FakeShellEnv(memory, (_, _) async {
      throw StateError('exec must not run');
    });
    final mcpTools = [
      FakeTool('mcp__fake__read_only', kind: ToolKind.read),
      FakeTool('mcp__fake__delete', kind: ToolKind.execute),
      FakeTool('mcp__fake__fetch', kind: ToolKind.fetch),
    ];
    final gate = FakeGate((_) => PermissionDecision.rejectOnce);
    final h = CoreHarness.build(
      baseEnv: shell,
      gate: gate,
      mcp: FakeMcpConnector(toolsOf: (_) => mcpTools),
      steps: [
        {
          'reply': [
            for (final (i, call) in <(String, Map<String, Object?>)>[
              ('read', {'path': 'a.txt'}),
              ('write', {'path': 'a.txt', 'content': 'x'}),
              ('edit', {'path': 'a.txt', 'oldText': 'a', 'newText': 'b'}),
              ('exec', {'command': 'echo hi'}),
              ('ls', {'path': '.'}),
              ('search', {'pattern': 'x'}),
              (
                'update_plan',
                {
                  'entries': [
                    {'content': 'c', 'priority': 'low', 'status': 'pending'},
                  ],
                },
              ),
              ('mcp__fake__read_only', <String, Object?>{}),
              ('mcp__fake__delete', <String, Object?>{}),
              ('mcp__fake__fetch', <String, Object?>{}),
            ].indexed)
              {
                'toolCall': {
                  'id': 'c$i',
                  'name': call.$1,
                  'arguments': call.$2,
                },
              },
          ],
        },
        textStep('done'),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(
        cwd: '/proj',
        mode: ModeId.ask,
        mcpServers: [const McpStdioServerConfig(name: 'fake', command: 'x')],
      ),
    );
    final finished = <ToolCallFinished>[];
    session.events.listen((e) {
      if (e is ToolCallFinished) {
        finished.add(e);
      }
    });

    await session.prompt([const TextContent('go')]);

    expect(finished, hasLength(10));
    expect(finished.map((f) => f.outcome).toSet(), {ToolOutcome.rejected});
    for (final tool in mcpTools) {
      expect(tool.executed, isEmpty, reason: tool.name);
    }
    expect(shell.commands, isEmpty);
    expect(gate.requests, hasLength(10));
    expect(
      (await memory.readText('/proj/a.txt')),
      isA<Err<String, FileError>>(),
    );
  });
}
