// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_tool.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/core_stack.dart';
import 'support/harness.dart';

/// Вид MCP-инструмента не зависит от аннотаций сервера (change
/// `add-provider-setup-ui`, D27, решение Q32 (а); MODIFIED agent-tools
/// «MCP-инструменты», сценарий «Вид не зависит от аннотаций»; задача 6.1c-1).
///
/// Почему: аннотации (`readOnlyHint`, `destructiveHint`, `openWorldHint`)
/// недоверенны. Вид попадает в `tool_call`, `session/request_permission` и
/// журнал сессии, и ложный `read` внушал бы пользователю безопасность вызова.
/// Поэтому `McpTool.kind` всегда `ToolKind.other`, а `tier` всегда `exec`;
/// политика разрешений от вида не зависит.
void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  Future<List<McpTool>> toolsOf(List<FakeMcpTool> tools) async {
    final fake = FakeMcpServer(tools: tools);
    final client = await h.connect(fake, name: 'fake');
    return [
      for (final definition in client.tools)
        ?McpTool.create(
          server: 'fake',
          definition: definition,
          client: client,
          logger: h.logger,
          sessionId: const SessionId('s1'),
        ),
    ];
  }

  group('McpTool.kind', () {
    const annotated = <String, Map<String, Object?>?>{
      'readonly': {'readOnlyHint': true},
      'destructive_closed': {'destructiveHint': true, 'openWorldHint': false},
      'destructive_open': {'destructiveHint': true},
      'destructive_open_world': {
        'destructiveHint': true,
        'openWorldHint': true,
      },
      'both': {'readOnlyHint': true, 'destructiveHint': true},
      'false_hints': {'readOnlyHint': false, 'destructiveHint': false},
      'none': null,
    };

    for (final entry in annotated.entries) {
      test('${entry.key}: kind other, tier exec', () async {
        final tool = (await toolsOf([
          FakeMcpTool(entry.key, annotations: entry.value),
        ])).single;

        expect(tool.kind, ToolKind.other);
        expect(tool.tier, ToolTier.exec);
        expect(tool.tierOf(const {}), ToolTier.exec);
      });
    }

    test('все аннотированные инструменты одного сервера — other', () async {
      final tools = await toolsOf([
        for (final e in annotated.entries)
          FakeMcpTool(e.key, annotations: e.value),
      ]);

      expect(tools, hasLength(annotated.length));
      expect({for (final t in tools) t.kind}, {ToolKind.other});
      expect({for (final t in tools) t.tier}, {ToolTier.exec});
    });
  });

  group('вид в запросе разрешения', () {
    Future<List<PermissionRequest>> requestsFor(
      FakeMcpTool tool,
      String name,
    ) async {
      final server = FakeMcpServer(tools: [tool]);
      late RecordingGate gate;
      final stack = CoreStack.build(
        server: server,
        steps: [toolCallStep('c1', 'mcp__fake__$name', {}), endStep()],
        gate: (s) =>
            gate = RecordingGate(s, (_) => PermissionDecision.rejectOnce),
      );
      final session = await stack.session();
      await session.prompt([TextContent('go')]);
      return gate.requests;
    }

    test('readOnlyHint не делает вопрос «read»: kind other', () async {
      final requests = await requestsFor(
        const FakeMcpTool('peek', annotations: {'readOnlyHint': true}),
        'peek',
      );

      expect(requests.single.kind, ToolKind.other);
      expect(requests.single.tier, ToolTier.exec);
    });

    test('destructiveHint с openWorldHint: false не даёт «edit»', () async {
      final requests = await requestsFor(
        const FakeMcpTool(
          'wipe',
          annotations: {'destructiveHint': true, 'openWorldHint': false},
        ),
        'wipe',
      );

      expect(requests.single.kind, ToolKind.other);
    });

    test('без аннотаций: other', () async {
      final requests = await requestsFor(const FakeMcpTool('echo'), 'echo');

      expect(requests.single.kind, ToolKind.other);
    });
  });
}
