import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';
import '../tools/fake_shell.dart';
import '../tools/fake_tools.dart';

final _other = ModelRef(
  provider: 'test',
  id: 'other',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

MarkdownFile _agentFile(
  String name, {
  Map<String, Object?> extra = const {},
  String body = 'Do the job.',
}) => MarkdownFile(
  path: '/home/.codelab/agents/$name.md',
  scope: ExtensionScope.user,
  body: body,
  bodyLine: 6,
  frontmatter: ConfigTree(
    kind: ConfigLayerKind.user,
    source: '/home/.codelab/agents/$name.md',
    values: {'name': name, 'description': 'The $name agent', ...extra},
  ),
);

final _reviewer = _agentFile(
  'reviewer',
  extra: {'model': 'test/other', 'mode': 'plan'},
);
final _writer = _agentFile('writer');

final class _Port implements ProjectFilesSource {
  _Port(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}

/// Порядок и согласованность смен конфигурации сессии: режим, модель, агент
/// (agent-definitions «Выбор агента»; design.md change
/// `add-agent-project-files`, D11; ревью итерации 3).
void main() {
  late MemorySessionStore store;
  late FakeGate gate;
  late MemoryExecutionEnv env;

  CoreHarness build(
    List<MarkdownFile> agents, {
    List<Map<String, Object?>> steps = const [],
    PermissionsConfig? permissions,
    ExecutionEnv? baseEnv,
    Map<HostCapability, CapabilityState> narrow = noExec,
    FakeGate? useGate,
    McpConnector? mcp,
  }) {
    gate = useGate ?? FakeGate();
    env = MemoryExecutionEnv(cwd: '/proj');
    return CoreHarness.build(
      baseEnv: baseEnv ?? env,
      narrow: narrow,
      gate: gate,
      sessions: store,
      steps: steps,
      models: FixedModelCatalog([testModel, _other]),
      permissions: permissions,
      mcp: mcp,
      projectFiles: _Port(agents),
    );
  }

  List<Map<String, Object?>> records(SessionId id) => [
    for (final line in const LineSplitter().convert(store.textOf(id)!))
      jsonDecode(line) as Map<String, Object?>,
  ];

  setUp(() => store = MemorySessionStore());

  group('serialization of config changes', () {
    test('setAgent(default) and setMode(ask) in parallel: the later call '
        'wins, both complete', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('reviewer');

      final back = session.setAgent('default');
      final ask = session.setMode(ModeId.ask);
      await Future.wait([back, ask]);

      expect(session.agent, 'default');
      expect(session.mode, ModeId.ask);
    });

    test('setAgent(default) and setAgent(writer) in parallel: the base is '
        'not corrupted and the journal is consistent', () async {
      final h = build([_reviewer, _writer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('reviewer');

      final back = session.setAgent('default');
      final next = session.setAgent('writer');
      await Future.wait([back, next]);

      expect(session.agent, 'writer');
      expect(session.mode, ModeId.standard);
      expect(session.model.id, 'model-1');
      await session.setAgent('default');
      expect(session.mode, ModeId.standard);
      expect(session.model.id, 'model-1');
      final journal = records(session.id);
      expect(
        [
          for (final r in journal)
            if (r['type'] == 'config_change') r['value'],
        ],
        ['reviewer', 'default', 'writer', 'default'],
      );
      // Согласованность: последняя запись режима и модели равна состоянию.
      expect(
        journal.where((r) => r['type'] == 'mode_change').last['modeId'],
        'standard',
      );
      expect(
        journal.where((r) => r['type'] == 'model_change').last['modelId'],
        'model-1',
      );
    });

    test('setModel and setEffort queue behind a setAgent', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      final agent = session.setAgent('reviewer');
      final model = session.setModel(const ModelId('test/model-1'));
      final effort = session.setEffort(ReasoningEffort.low);
      await Future.wait([agent, model, effort]);

      expect(session.model.id, 'model-1');
      expect(session.effort, ReasoningEffort.low);
      expect(session.mode, ModeId.plan);
    });

    test('a failed call does not block the queue', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      final bad = session.setAgent('nope');
      final good = session.setMode(ModeId.ask);

      await expectLater(bad, throwsArgumentError);
      await good;
      expect(session.mode, ModeId.ask);
    });
  });

  group('close', () {
    test('waits for the running change; the queued ones fail with '
        'StateError', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      final first = session.setMode(ModeId.ask);
      // Первая смена уже началась (ждёт запись журнала), вторая стоит в очереди.
      await Future<void>.value();
      final second = session.setMode(ModeId.plan);
      final closing = session.close();

      await first;
      await expectLater(second, throwsStateError);
      await closing;
      expect(session.mode, ModeId.ask);
    });
  });

  group('order of mixed calls', () {
    test('setAgent, setMode, setAgent(default) without waiting: executed in '
        'order, the base is the mode before the first call', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      final calls = [
        session.setAgent('reviewer'),
        session.setMode(ModeId.acceptEdits),
        session.setAgent('default'),
      ];
      await Future.wait(calls);

      expect(session.mode, ModeId.standard);
      expect(session.model.id, 'model-1');
      expect(
        [
          for (final r in records(session.id))
            if (r['type'] == 'config_change' ||
                r['type'] == 'mode_change' ||
                r['type'] == 'model_change')
              '${r['type']}',
        ].skip(1).toList(), // первая model_change — запись создания сессии
        [
          'config_change',
          'model_change',
          'mode_change',
          'mode_change',
          'config_change',
          'model_change',
          'mode_change',
        ],
      );
    });
  });

  group('result of a change (for the ACP adapter)', () {
    test('setMode returns its own change id and the mode', () async {
      final h = build([_reviewer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final events = <ModeChanged>[];
      session.events
          .where((e) => e is ModeChanged)
          .cast<ModeChanged>()
          .listen(events.add);

      final a = await session.setMode(ModeId.ask);
      final b = await session.setMode(ModeId.plan);

      expect(a.mode, ModeId.ask);
      expect(b.mode, ModeId.plan);
      expect(a.changeId, isNot(b.changeId));
      await pumpEventQueue();
      expect([for (final e in events) e.changeId], [a.changeId, b.changeId]);
    });

    test('setAgent tells whether the mode and the model changed; the echo '
        'carries the same id', () async {
      final h = build([
        _reviewer,
        _agentFile('daring', extra: {'mode': 'bypass'}),
        _writer,
      ]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final events = <ModeChanged>[];
      session.events
          .where((e) => e is ModeChanged)
          .cast<ModeChanged>()
          .listen(events.add);

      final changed = await session.setAgent('reviewer');
      final refused = await session.setAgent('daring');
      final noop = await session.setAgent('daring');

      await pumpEventQueue();
      expect(changed.mode, ModeId.plan);
      expect(changed.model?.id, 'other');
      expect(events.first.changeId, changed.changeId);
      expect(events.last.changeId, refused.changeId);
      // `daring` мягче пола: режим не применяется, хотя модель вернулась к базе.
      expect(refused.mode, ModeId.standard);
      expect(refused.model?.id, 'model-1');
      expect(noop.mode, isNull);
      expect(noop.model, isNull);
      final plain = await session.setAgent('writer');
      expect(plain.mode, isNull);
    });
  });

  group('mid-turn', () {
    test('a mode of the new agent applies from the next step: the rest of '
        'the package is decided by the old mode', () async {
      late final AgentSession session;
      final trigger = FakeTool(
        'mcp__github__issue',
        executionMode: ToolExecutionMode.sequential,
        onExecute: (_, _) async {
          await session.setAgent('planner');
          return const ToolExecutionResult([TextContent('issue read')]);
        },
      );
      final h = build(
        [
          _agentFile('planner', extra: {'mode': 'plan'}),
        ],
        mcp: FakeMcpConnector(toolsOf: (_) => [trigger]),
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'c1',
                  'name': 'mcp__github__issue',
                  'arguments': <String, Object?>{},
                },
              },
              {
                'toolCall': {
                  'id': 'c2',
                  'name': 'write',
                  'arguments': {'path': 'a.txt', 'content': 'x'},
                },
              },
            ],
          },
          callStep('c3', 'write', {'path': 'b.txt', 'content': 'y'}),
          textStep('done'),
        ],
      );
      session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('github')]),
      );

      await session.prompt([const TextContent('go')]);

      // c2 того же пакета решён прежним режимом (`standard` разрешает write).
      expect(await env.readText('/proj/a.txt'), isA<Ok<String, FileError>>());
      // c3 — следующий шаг: режим `plan` действует.
      expect(await env.readText('/proj/b.txt'), isA<Err<String, FileError>>());
      final results = h.requestedContexts.last.messages
          .whereType<ToolResultMessage>()
          .last;
      expect(
        results.content.whereType<TextContent>().single.text,
        startsWith('Permission denied for write'),
      );
      expect(session.mode, ModeId.plan);
    });

    test('setMode mid-turn stays immediate: the next call of the package '
        'already follows it', () async {
      late final AgentSession session;
      final trigger = FakeTool(
        'mcp__github__issue',
        executionMode: ToolExecutionMode.sequential,
        onExecute: (_, _) async {
          await session.setMode(ModeId.plan);
          return const ToolExecutionResult([TextContent('issue read')]);
        },
      );
      final h = build(
        const [],
        mcp: FakeMcpConnector(toolsOf: (_) => [trigger]),
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'c1',
                  'name': 'mcp__github__issue',
                  'arguments': <String, Object?>{},
                },
              },
              {
                'toolCall': {
                  'id': 'c2',
                  'name': 'write',
                  'arguments': {'path': 'a.txt', 'content': 'x'},
                },
              },
            ],
          },
          textStep('done'),
        ],
      );
      session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('github')]),
      );

      await session.prompt([const TextContent('go')]);

      expect(await env.readText('/proj/a.txt'), isA<Err<String, FileError>>());
    });

    test('a pending mode of a turn that ended without another step is '
        'applied before the next turn', () async {
      late final AgentSession session;
      final trigger = FakeTool(
        'mcp__github__issue',
        executionMode: ToolExecutionMode.sequential,
        onExecute: (_, _) async {
          await session.setAgent('planner');
          return const ToolExecutionResult([TextContent('issue read')]);
        },
      );
      final h = build(
        [
          _agentFile('planner', extra: {'mode': 'plan'}),
        ],
        mcp: FakeMcpConnector(toolsOf: (_) => [trigger]),
        steps: [
          callStep('c1', 'mcp__github__issue', const {}),
          textStep('done'),
          callStep('c2', 'write', {'path': 'a.txt', 'content': 'x'}),
          textStep('done'),
        ],
      );
      session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('github')]),
      );
      await session.prompt([const TextContent('go')]);

      await session.prompt([const TextContent('again')]);

      expect(await env.readText('/proj/a.txt'), isA<Err<String, FileError>>());
    });
  });

  group('mid-turn tool set', () {
    test('the rest of the package is checked by the old set; the next step '
        'by the new one', () async {
      late final AgentSession session;
      final trigger = FakeTool(
        'mcp__github__issue',
        executionMode: ToolExecutionMode.sequential,
        onExecute: (_, _) async {
          await session.setAgent('b');
          return const ToolExecutionResult([TextContent('switched')]);
        },
      );
      Map<String, Object?> call(
        String id,
        String name,
        Map<String, Object?> a,
      ) => {
        'toolCall': {'id': id, 'name': name, 'arguments': a},
      };
      final h = build(
        [
          _agentFile(
            'a',
            extra: {
              'tools': ['read', 'mcp__github__issue'],
            },
          ),
          _agentFile(
            'b',
            extra: {
              'tools': ['write'],
            },
          ),
        ],
        mcp: FakeMcpConnector(toolsOf: (_) => [trigger]),
        steps: [
          {
            'reply': [
              call('c1', 'mcp__github__issue', const {}),
              call('c2', 'read', {'path': 'a.txt'}),
              call('c3', 'write', {'path': 'w1.txt', 'content': 'x'}),
            ],
          },
          callStep('c4', 'read', {'path': 'a.txt'}),
          callStep('c5', 'write', {'path': 'w2.txt', 'content': 'x'}),
          textStep('done'),
        ],
      );
      await env.writeText('/proj/a.txt', 'hello');
      session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj', mcpServers: [_stdio('github')]),
      );
      await session.setAgent('a');

      await session.prompt([const TextContent('go')]);

      final results = {
        for (final m
            in h.requestedContexts.last.messages.whereType<ToolResultMessage>())
          m.toolCallId: m,
      };
      String text(String id) =>
          results[id]!.content.whereType<TextContent>().single.text;
      expect(results['c2']!.isError, isFalse);
      expect(text('c3'), 'Tool not available for agent a: write');
      expect(text('c4'), 'Tool not available for agent b: read');
      expect(results['c5']!.isError, isFalse);
      expect(await env.readText('/proj/w1.txt'), isA<Err<String, FileError>>());
      expect(await env.readText('/proj/w2.txt'), isA<Ok<String, FileError>>());
    });
  });

  group('the floor on restore (fail-closed)', () {
    test(
      'a base recorded under bypass is clamped by a stricter config',
      () async {
        final h0 = build([
          _writer,
        ], permissions: const PermissionsConfig(mode: ModeId.bypass));
        final session = await h0.core.runtime.createSession(
          SessionSpec(cwd: '/proj'),
        );
        await session.setMode(ModeId.bypass);
        await session.setAgent('writer');
        await session.close();
        final h = build([
          _writer,
        ], permissions: const PermissionsConfig(mode: ModeId.standard));

        final loaded = await h.core.runtime.loadSession(
          session.id,
          const SessionHostPorts(),
        );
        expect(loaded.agent, 'writer');
        await loaded.setAgent('default');

        expect(loaded.mode, ModeId.standard);
      },
    );

    test('a base stricter than the config stays as it was', () async {
      final h0 = build([_writer]);
      final session = await h0.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setMode(ModeId.ask);
      await session.setAgent('writer');
      await session.close();
      final h = build([_writer]);

      final loaded = await h.core.runtime.loadSession(
        session.id,
        const SessionHostPorts(),
      );
      await loaded.setAgent('default');

      expect(loaded.mode, ModeId.ask);
    });
  });

  group('a missing definition (journal)', () {
    test('is written as config_change default: the base is counted from the '
        'state after the first load', () async {
      final h0 = build([_reviewer, _writer]);
      final session = await h0.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('reviewer');
      await session.close();

      final h1 = build([_writer]);
      final first = await h1.core.runtime.loadSession(
        session.id,
        const SessionHostPorts(),
      );
      expect(first.agent, 'default');
      expect(first.mode, ModeId.plan);
      await first.setMode(ModeId.ask);
      await first.setAgent('writer');
      await first.close();

      final h2 = build([_reviewer, _writer]);
      final second = await h2.core.runtime.loadSession(
        session.id,
        const SessionHostPorts(),
      );
      expect(second.agent, 'writer');
      await second.setAgent('default');

      expect(second.mode, ModeId.ask);
      expect(
        [
          for (final r in records(session.id))
            if (r['type'] == 'config_change' && r['optionId'] == 'agent')
              r['value'],
        ],
        ['reviewer', 'default', 'writer', 'default'],
      );
    });

    test('a second load of the same journal does not log the missing '
        'definition again', () async {
      final h0 = build([_reviewer]);
      final session = await h0.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('reviewer');
      await session.close();
      final first = await build(
        const [],
      ).core.runtime.loadSession(session.id, const SessionHostPorts());
      await first.close();

      final h = build(const []);
      await h.core.runtime.loadSession(session.id, const SessionHostPorts());

      expect(h.logger.eventsOf('agent.definition.missing'), isEmpty);
    });
  });

  group('log and breaker (D11, D14)', () {
    test('agent.selected for default has no source; a definition without '
        'a mode counts as applied', () async {
      final h = build([_writer]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      await session.setAgent('writer');
      await session.setAgent('default');

      final logs = h.logger.eventsOf('agent.selected');
      expect(logs[0].fields['mode_applied'], isTrue);
      expect(logs[1].fields['source'], isNull);
      expect(logs[1].fields['mode_applied'], isTrue);
    });

    test('a call outside the set counts in the misuse breaker like an '
        'unknown tool', () async {
      final h = build(
        [
          _agentFile(
            'readonly',
            extra: {
              'tools': ['read'],
            },
          ),
        ],
        steps: [
          for (var i = 0; i < 7; i++)
            callStep('c$i', 'write', {'path': 'a.txt', 'content': 'x'}),
          textStep('done'),
        ],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('readonly');

      await session.prompt([const TextContent('go')]);

      final texts = [
        for (final m
            in h.requestedContexts.last.messages.whereType<ToolResultMessage>())
          m.content.whereType<TextContent>().single.text,
      ];
      expect(texts, hasLength(7));
      expect(texts[2], contains('Tool not available for agent readonly'));
      expect(texts[2].length, greaterThan(texts[0].length));
      expect(texts[6], isNot(texts[0]));
      expect(gate.requests, isEmpty);
    });
  });

  group('prompt', () {
    test('the mcp section names only servers with available tools; the body '
        'is trimmed at the edges', () async {
      final h = build(
        [
          _agentFile(
            'gh',
            body: '\n\n  Use github.  \n\n',
            extra: {
              'tools': ['read', 'mcp__github__*'],
            },
          ),
        ],
        mcp: FakeMcpConnector(
          toolsOf: (_) => [
            FakeTool('mcp__github__ping'),
            FakeTool('mcp__jira__ping'),
          ],
        ),
        steps: [textStep('ok')],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(
          cwd: '/proj',
          mcpServers: [_stdio('github'), _stdio('jira')],
        ),
      );
      await session.setAgent('gh');

      await session.prompt([const TextContent('go')]);

      final prompt = h.requestedContexts.single.systemPrompt;
      expect(prompt, contains('github'));
      expect(prompt, isNot(contains('jira')));
      expect(prompt, endsWith('# Agent profile: gh\n\nUse github.\n'));
    });
  });

  group('security', () {
    test('a bypass agent does not lift permissions.deny', () async {
      final h = build(
        [
          _agentFile('daring', extra: {'mode': 'bypass'}),
        ],
        permissions: PermissionsConfig(
          mode: ModeId.bypass,
          rules: PolicyRules(
            denyPatterns: {const PermissionKey('write', 'secret.txt')},
          ),
        ),
        steps: [
          callStep('c1', 'write', {'path': 'secret.txt', 'content': 'x'}),
          textStep('done'),
        ],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('daring');

      await session.prompt([const TextContent('go')]);

      final result = h.requestedContexts.last.messages
          .whereType<ToolResultMessage>()
          .single;
      expect(
        result.content.whereType<TextContent>().single.text,
        startsWith('Permission denied for write'),
      );
      expect(
        await env.readText('/proj/secret.txt'),
        isA<Err<String, FileError>>(),
      );
    });

    test('a bypass agent still asks for a critical command and for agent '
        'configuration (PERM-11)', () async {
      final shell = FakeShellEnv(
        MemoryExecutionEnv(cwd: '/proj'),
        answering('ran'),
      );
      final h = build(
        [
          _agentFile('daring', extra: {'mode': 'bypass'}),
        ],
        permissions: const PermissionsConfig(mode: ModeId.bypass),
        baseEnv: shell,
        narrow: const {},
        useGate: FakeGate((_) => PermissionDecision.rejectOnce),
        steps: [
          callStep('c1', 'exec', {'command': 'rm -rf /'}),
          callStep('c2', 'write', {
            'path': '.codelab/config.yaml',
            'content': 'x',
          }),
          textStep('done'),
        ],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.setAgent('daring');

      await session.prompt([const TextContent('go')]);

      expect(gate.requests, hasLength(2));
      expect(gate.requests[0].criticalLabel, isNotNull);
      expect(gate.requests[0].allowAlwaysOffered, isFalse);
      expect(gate.requests[1].allowAlwaysOffered, isFalse);
      expect(shell.commands, isEmpty);
    });

    for (final forged in <Object?>['ghost', 42, '', null]) {
      test('a forged config_change agent $forged does not apply a '
          'definition', () async {
        final h0 = build([_reviewer]);
        final session = await h0.core.runtime.createSession(
          SessionSpec(cwd: '/proj'),
        );
        await session.close();
        final line = jsonEncode({
          'type': 'config_change',
          'id': 'forged1',
          'parentId': _leafOf(store, session.id),
          'timestamp': '2026-01-01T00:00:00.000Z',
          'optionId': 'agent',
          'value': forged,
        });
        store.putText(session.id, '${store.textOf(session.id)}$line\n');
        final h = build([_reviewer]);

        final loaded = await h.core.runtime.loadSession(
          session.id,
          const SessionHostPorts(),
        );

        expect(loaded.agent, 'default');
        expect(loaded.mode, ModeId.standard);
        expect(loaded.model.id, 'model-1');
      });
    }
  });
}

String? _leafOf(MemorySessionStore store, SessionId id) {
  final last = const LineSplitter()
      .convert(store.textOf(id)!)
      .map((l) => jsonDecode(l) as Map<String, Object?>)
      .last;
  return last['id'] as String?;
}

McpStdioServerConfig _stdio(String name) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  origin: McpServerOrigin.session,
);
