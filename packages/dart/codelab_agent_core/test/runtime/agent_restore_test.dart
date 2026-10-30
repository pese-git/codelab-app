import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

final _other = ModelRef(
  provider: 'test',
  id: 'other',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

/// Восстановление агента в `loadSession` (agent-definitions «Восстановление
/// агента при загрузке»; design.md change `add-agent-project-files`, D11, D14;
/// R-15).
void main() {
  final reviewer = MarkdownFile(
    path: '/home/.codelab/agents/reviewer.md',
    scope: ExtensionScope.user,
    body: 'Review carefully.',
    bodyLine: 6,
    frontmatter: const ConfigTree(
      kind: ConfigLayerKind.user,
      source: '/home/.codelab/agents/reviewer.md',
      values: {
        'name': 'reviewer',
        'description': 'Reviews',
        'model': 'test/other',
        'mode': 'plan',
        'tools': ['read', 'search'],
      },
    ),
  );

  late MemorySessionStore store;

  CoreHarness build(
    List<MarkdownFile> agents, [
    List<Map<String, Object?>>? steps,
  ]) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: FakeGate(),
    sessions: store,
    steps: steps ?? [textStep('ok')],
    models: FixedModelCatalog([testModel, _other]),
    projectFiles: _Port(agents),
  );

  setUp(() => store = MemorySessionStore());

  Future<SessionId> createWithReviewer() async {
    final h = build([reviewer]);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.setAgent('reviewer');
    await session.close();
    return session.id;
  }

  test('the agent comes back: profile section, listed tools only, mode and '
      'model from their own records', () async {
    final id = await createWithReviewer();
    final h = build([reviewer]);

    final loaded = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );
    await loaded.prompt([const TextContent('go')]);

    expect(loaded.agent, 'reviewer');
    expect(loaded.mode, ModeId.plan);
    expect(loaded.model.id, 'other');
    final request = h.requestedContexts.single;
    expect(
      request.systemPrompt,
      endsWith('# Agent profile: reviewer\n\nReview carefully.\n'),
    );
    expect([for (final t in request.tools) t.name], ['read', 'search']);
    expect(h.logger.eventsOf('agent.definition.missing'), isEmpty);
  });

  test('the base survives the reload: default after a load returns the '
      'state before the choice', () async {
    final id = await createWithReviewer();
    final h = build([reviewer]);
    final loaded = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );

    await loaded.setAgent('default');

    expect(loaded.agent, 'default');
    expect(loaded.mode, ModeId.standard);
    expect(loaded.model.id, 'model-1');
  });

  test('a mode the user set after the choice is restored from its own '
      'record, the agent stays', () async {
    final h0 = build([reviewer]);
    final session = await h0.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.setAgent('reviewer');
    await session.setMode(ModeId.ask);
    await session.close();
    final h = build([reviewer]);

    final loaded = await h.core.runtime.loadSession(
      session.id,
      const SessionHostPorts(),
    );

    expect(loaded.agent, 'reviewer');
    expect(loaded.mode, ModeId.ask);
  });

  test('the definition was removed: default, a warning, mode and model from '
      'their records, the session opens', () async {
    final id = await createWithReviewer();
    final h = build(const []);

    final loaded = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );
    await loaded.prompt([const TextContent('go')]);

    expect(loaded.agent, 'default');
    expect(loaded.mode, ModeId.plan);
    expect(loaded.model.id, 'other');
    final log = h.logger.eventsOf('agent.definition.missing').single;
    expect(log.fields, {'session_id': id.value, 'agent': 'reviewer'});
    final request = h.requestedContexts.single;
    expect(request.systemPrompt, isNot(contains('# Agent profile')));
    expect(request.tools, isNotEmpty);
  });

  test('a session that never chose an agent loads as default without '
      'a warning', () async {
    final h0 = build([reviewer]);
    final session = await h0.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.close();
    final h = build([reviewer]);

    final loaded = await h.core.runtime.loadSession(
      session.id,
      const SessionHostPorts(),
    );

    expect(loaded.agent, 'default');
    expect(h.logger.eventsOf('agent.definition.missing'), isEmpty);
  });
}

final class _Port implements ProjectFilesSource {
  _Port(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}
