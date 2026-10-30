import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';
import '../tools/fake_tools.dart';

const _base = ['read', 'write', 'edit', 'update_plan', 'ls', 'search'];

final _other = ModelRef(
  provider: 'test',
  id: 'other',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

/// Выбор агента в `AgentSession` (agent-definitions «Выбор агента»; design.md
/// change `add-agent-project-files`, D11; CFG-7, CFG-8, OQ3; критерий
/// `core/agent-definition-markdown-frontmatter`, R-15).
void main() {
  MarkdownFile agentFile(
    String name, {
    String body = 'Review carefully.',
    Map<String, Object?> extra = const {},
    String dir = '/home/.codelab/agents',
  }) => MarkdownFile(
    path: '$dir/$name.md',
    scope: ExtensionScope.user,
    body: body,
    bodyLine: 6,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '$dir/$name.md',
      values: {'name': name, 'description': 'The $name agent', ...extra},
    ),
  );

  final reviewer = agentFile(
    'reviewer',
    extra: {
      'model': 'test/other',
      'mode': 'plan',
      'tools': ['read', 'search', 'ls', 'mcp__github__*'],
    },
  );

  late FakeGate gate;
  late FakeMcpConnector mcp;
  late MemoryExecutionEnv env;

  CoreHarness build(
    List<Map<String, Object?>> steps, {
    List<MarkdownFile>? agents,
    PermissionsConfig? permissions,
    SessionStore? store,
    FakeMcpConnector? connector,
  }) {
    gate = FakeGate();
    env = MemoryExecutionEnv(cwd: '/proj');
    mcp =
        connector ??
        FakeMcpConnector(
          toolsOf: (_) => [
            FakeTool('mcp__github__issue'),
            FakeTool('mcp__other__ping'),
          ],
        );
    return CoreHarness.build(
      baseEnv: env,
      narrow: noExec,
      gate: gate,
      sessions: store,
      steps: steps,
      mcp: mcp,
      models: FixedModelCatalog([testModel, _other]),
      permissions: permissions,
      projectFiles: _Port(agents ?? [reviewer]),
    );
  }

  Future<AgentSession> open(CoreHarness h) => h.core.runtime.createSession(
    SessionSpec(cwd: '/proj', mcpServers: [_stdio('github')]),
  );

  List<String> toolNames(LlmContext context) => [
    for (final t in context.tools) t.name,
  ];

  group('the list', () {
    test('lists agents of scope session and both by name; the current one '
        'is default', () async {
      final h = build(
        const [],
        agents: [
          agentFile('zed'),
          agentFile('only-task', extra: {'scope': 'subagent'}),
          agentFile('alpha', extra: {'scope': 'session'}),
        ],
      );

      final session = await open(h);

      expect([for (final a in session.agents) a.name], ['alpha', 'zed']);
      expect(session.agent, 'default');
    });

    test('is empty without definitions', () async {
      final h = build(const [], agents: const []);

      final session = await open(h);

      expect(session.agents, isEmpty);
    });

    test(
      'a name outside the list is an ArgumentError, default is fine',
      () async {
        final h = build(const []);
        final session = await open(h);

        await expectLater(session.setAgent('nope'), throwsArgumentError);
        await expectLater(session.setAgent('only-task'), throwsArgumentError);
        await session.setAgent('default');
        expect(session.agent, 'default');
      },
    );

    test('agents.loaded names every loaded definition', () async {
      final h = build(const []);

      final session = await open(h);

      final log = h.logger.eventsOf('agents.loaded').single;
      expect(log.fields, {
        'session_id': session.id.value,
        'names': ['reviewer'],
      });
    });
  });

  group('select and return (R-15)', () {
    test('the profile section, model, mode and only the listed schemas; '
        'default restores everything', () async {
      final h = build([textStep('one'), textStep('two'), textStep('three')]);
      final session = await open(h);
      await session.prompt([const TextContent('go')]);
      final before = h.requestedContexts.first;

      await session.setAgent('reviewer');
      await session.prompt([const TextContent('go')]);
      final during = h.requestedContexts[1];
      expect(session.agent, 'reviewer');
      expect(session.mode, ModeId.plan);
      expect(session.model.id, 'other');
      expect(h.requestedModels[1].id, 'other');
      expect(
        during.systemPrompt,
        endsWith('# Agent profile: reviewer\n\nReview carefully.\n'),
      );
      expect(toolNames(during), ['read', 'ls', 'search', 'mcp__github__issue']);
      expect(during.systemPrompt, contains('You are CodeLab'));
      expect(during.systemPrompt, contains('untrusted-content'));
      expect(during.systemPrompt, isNot(contains('mcp__other__')));

      await session.setAgent('default');
      await session.prompt([const TextContent('go')]);
      final after = h.requestedContexts[2];
      expect(session.agent, 'default');
      expect(session.mode, ModeId.standard);
      expect(session.model.id, 'model-1');
      expect(after.systemPrompt, before.systemPrompt);
      expect(toolNames(after), toolNames(before));
    });

    test('the body is a value: no template processing', () async {
      final h = build(
        [textStep('one')],
        agents: [agentFile('odd', body: 'Use {{name}} and {{ body }} as is.')],
      );
      final session = await open(h);

      await session.setAgent('odd');
      await session.prompt([const TextContent('go')]);

      expect(
        h.requestedContexts.single.systemPrompt,
        endsWith(
          '# Agent profile: odd\n\nUse {{name}} and {{ body }} as is.\n',
        ),
      );
    });

    test('the choice goes to the journal as config_change; the following '
        'model and mode changes are their own records', () async {
      final store = MemorySessionStore();
      final h = build(const [], store: store);
      final session = await open(h);

      await session.setAgent('reviewer');
      await session.setAgent('default');

      final records = [
        for (final line in const LineSplitter().convert(
          store.textOf(session.id)!,
        ))
          jsonDecode(line) as Map<String, Object?>,
      ];
      final types = [for (final r in records) r['type']];
      final first = types.indexOf('config_change');
      expect(records[first]['optionId'], 'agent');
      expect(records[first]['value'], 'reviewer');
      // Запись выбора идёт раньше своих model_change/mode_change: по ней
      // восстановление находит базу (D11).
      expect(types.sublist(first, first + 3), [
        'config_change',
        'model_change',
        'mode_change',
      ]);
      expect(
        [
          for (final r in records)
            if (r['type'] == 'config_change') r['value'],
        ],
        ['reviewer', 'default'],
      );
    });

    test('agent.selected has the facts and never the body', () async {
      final h = build(const []);
      final session = await open(h);

      await session.setAgent('reviewer');

      final log = h.logger.eventsOf('agent.selected').single;
      expect(log.fields, {
        'session_id': session.id.value,
        'agent': 'reviewer',
        'source': '/home/.codelab/agents/reviewer.md',
        'model': 'test/other',
        'mode': 'plan',
        'mode_applied': true,
        'tools': 4,
      });
      expect(
        [for (final r in h.logger.records) r.toString()].join('\n'),
        isNot(contains('Review carefully')),
      );
    });

    test('reselecting the current agent is a no-op', () async {
      final store = MemorySessionStore();
      final h = build(const [], store: store);
      final session = await open(h);
      await session.setAgent('reviewer');
      final size = store.textOf(session.id)!.length;

      await session.setAgent('reviewer');

      expect(store.textOf(session.id)!.length, size);
      expect(h.logger.eventsOf('agent.selected'), hasLength(1));
    });

    test('a switch between agents counts from the same base', () async {
      final h = build(const [], agents: [reviewer, agentFile('plain')]);
      final session = await open(h);

      await session.setAgent('reviewer');
      await session.setAgent('plain');

      // `plain` не задаёт ни модель, ни режим: действует база, а не
      // значения предыдущего агента.
      expect(session.model.id, 'model-1');
      expect(session.mode, ModeId.standard);
      await session.setAgent('default');
      expect(session.model.id, 'model-1');
    });

    test('a mode or model chosen by the user while an agent is active does '
        'not move the base', () async {
      final h = build(const []);
      final session = await open(h);
      await session.setAgent('reviewer');

      await session.setMode(ModeId.acceptEdits);
      await session.setModel(const ModelId('test/model-1'));
      await session.setAgent('default');

      expect(session.mode, ModeId.standard);
      expect(session.model.id, 'model-1');
    });
  });

  group('tools (CFG-7)', () {
    test('a call outside the set is a tool error with no permission request '
        'and no execution', () async {
      final h = build(
        [
          callStep('c1', 'write', {'path': 'a.txt', 'content': 'x'}),
          textStep('done'),
        ],
        agents: [
          agentFile(
            'readonly',
            extra: {
              'tools': ['read'],
            },
          ),
        ],
      );
      final session = await open(h);
      await session.setAgent('readonly');

      await session.prompt([const TextContent('go')]);

      final result = h.requestedContexts.last.messages
          .whereType<ToolResultMessage>()
          .single;
      expect(result.isError, isTrue);
      expect(
        result.content.whereType<TextContent>().single.text,
        'Tool not available for agent readonly: write',
      );
      expect(gate.requests, isEmpty);
      expect(await env.readText('/proj/a.txt'), isA<Err<String, FileError>>());
    });

    test('tools: [] leaves no schemas', () async {
      final h = build(
        [textStep('one')],
        agents: [
          agentFile('mute', extra: {'tools': <Object?>[]}),
        ],
      );
      final session = await open(h);
      await session.setAgent('mute');

      await session.prompt([const TextContent('go')]);

      expect(h.requestedContexts.single.tools, isEmpty);
    });

    test(
      'sections of the tools left out disappear from the prompt (PR-6)',
      () async {
        final h = build([textStep('one')]);
        final session = await open(h);
        await session.setAgent('reviewer');

        await session.prompt([const TextContent('go')]);

        final prompt = h.requestedContexts.single.systemPrompt;
        expect(prompt, isNot(contains('update_plan')));
        expect(prompt, isNot(contains('mcp__other__')));
      },
    );

    test(
      'an MCP tool that appears later is filtered by the same list',
      () async {
        final h = build([textStep('one')]);
        final session = await open(h);
        await session.setAgent('reviewer');

        mcp.sessions.single.pending = McpToolsUpdate(
          tools: [
            FakeTool('mcp__github__issue'),
            FakeTool('mcp__github__pr'),
            FakeTool('mcp__other__ping'),
          ],
          servers: const [
            McpServerSummary(name: 'github', toolCount: 2),
            McpServerSummary(name: 'other', toolCount: 1),
          ],
        );
        await session.prompt([const TextContent('go')]);

        expect(toolNames(h.requestedContexts.single), [
          'read',
          'ls',
          'search',
          'mcp__github__issue',
          'mcp__github__pr',
        ]);
      },
    );
  });

  group('the mode floor (OQ3)', () {
    test('a softer mode than the config is not applied; the rest is', () async {
      final h = build(
        [textStep('one')],
        agents: [
          agentFile(
            'daring',
            extra: {
              'mode': 'bypass',
              'tools': ['read'],
            },
          ),
        ],
      );
      final session = await open(h);

      await session.setAgent('daring');
      await session.prompt([const TextContent('go')]);

      expect(session.mode, ModeId.standard);
      final warn = h.logger.eventsOf('agent.mode.not_applied').single;
      expect(warn.fields, {
        'session_id': session.id.value,
        'agent': 'daring',
        'mode': 'bypass',
        'floor': 'standard',
      });
      expect(
        h.logger.eventsOf('agent.selected').single.fields['mode_applied'],
        isFalse,
      );
      expect(
        h.requestedContexts.single.systemPrompt,
        contains('# Agent profile: daring'),
      );
      expect(toolNames(h.requestedContexts.single), ['read']);
    });

    test('a mode equal to or stricter than the config is applied', () async {
      final h = build(
        const [],
        agents: [
          agentFile('same', extra: {'mode': 'standard'}),
          agentFile('strict', extra: {'mode': 'ask'}),
        ],
      );
      final session = await open(h);

      await session.setAgent('strict');
      expect(session.mode, ModeId.ask);
      await session.setAgent('same');
      expect(session.mode, ModeId.standard);
      expect(h.logger.eventsOf('agent.mode.not_applied'), isEmpty);
    });

    test(
      'plan in the config is the floor: ask and standard are softer',
      () async {
        final h = build(
          const [],
          agents: [
            agentFile('ask-agent', extra: {'mode': 'ask'}),
          ],
          permissions: const PermissionsConfig(mode: ModeId.plan),
        );
        final session = await open(h);
        expect(session.mode, ModeId.plan);

        await session.setAgent('ask-agent');

        expect(session.mode, ModeId.plan);
        expect(h.logger.eventsOf('agent.mode.not_applied'), hasLength(1));
      },
    );

    test('the floor is the config, not the current mode: a user in '
        'accept-edits can still choose an accept-edits agent', () async {
      final h = build(
        const [],
        agents: [
          agentFile('editor', extra: {'mode': 'accept-edits'}),
        ],
        permissions: const PermissionsConfig(mode: ModeId.acceptEdits),
      );
      final session = await open(h);
      await session.setMode(ModeId.ask);

      await session.setAgent('editor');

      expect(session.mode, ModeId.acceptEdits);
    });

    test('extraDeniedTiers still deny after a choice of an agent', () async {
      final h = build(
        [
          callStep('c1', 'write', {'path': 'a.txt', 'content': 'x'}),
          textStep('done'),
        ],
        agents: [
          agentFile('daring', extra: {'mode': 'bypass'}),
        ],
        permissions: const PermissionsConfig(
          mode: ModeId.bypass,
          extraDeniedTiers: {ToolTier.write},
        ),
      );
      final session = await open(h);
      await session.setAgent('daring');

      await session.prompt([const TextContent('go')]);

      final result = h.requestedContexts.last.messages
          .whereType<ToolResultMessage>()
          .single;
      expect(
        result.content.whereType<TextContent>().single.text,
        startsWith('Permission denied for write'),
      );
      expect(gate.requests, isEmpty);
    });
  });

  group('mid-turn', () {
    test('a choice during the first of two steps lets the call finish and '
        'changes the request of the second step', () async {
      late final AgentSession session;
      final trigger = FakeTool(
        'mcp__github__issue',
        onExecute: (_, _) async {
          await session.setAgent('reviewer');
          return const ToolExecutionResult([TextContent('issue read')]);
        },
      );
      final h = build([
        callStep('c1', 'mcp__github__issue', const {}),
        textStep('done'),
      ], connector: FakeMcpConnector(toolsOf: (_) => [trigger]));
      session = await open(h);

      await session.prompt([const TextContent('go')]);

      expect(trigger.executed, hasLength(1));
      final first = h.requestedContexts[0];
      final second = h.requestedContexts[1];
      expect(first.systemPrompt, isNot(contains('# Agent profile')));
      expect(toolNames(first), [..._base, 'mcp__github__issue']);
      expect(second.systemPrompt, contains('# Agent profile: reviewer'));
      expect(toolNames(second), ['read', 'ls', 'search', 'mcp__github__issue']);
      expect(h.requestedModels.map((m) => m.id), ['model-1', 'other']);
    });
  });
}

McpStdioServerConfig _stdio(String name) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  origin: McpServerOrigin.session,
);

final class _Port implements ProjectFilesSource {
  _Port(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}
