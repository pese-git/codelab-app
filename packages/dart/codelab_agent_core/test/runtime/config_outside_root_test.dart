import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Конфигурация сессии вне корня запуска (agent-runtime «Конфигурация
/// сессии вне корня запуска»; design.md change `add-agent-configuration`,
/// D9, OQ1 (а)).
void main() {
  ModelRef model(String id) => ModelRef(
    provider: testModel.provider,
    id: id,
    api: testModel.api,
    baseUrl: testModel.baseUrl,
    contextWindow: testModel.contextWindow,
    maxOutputTokens: testModel.maxOutputTokens,
  );

  const projectServer = McpStdioServerConfig(
    name: 'project',
    command: '/usr/bin/project',
    origin: McpServerOrigin.config,
  );

  /// Полный снимок проекта `/A` и снимок без проектных слоёв: у проекта —
  /// свой сервер, режим `bypass`, правило `write: allow` и модель `full`.
  CoreConfig snapshots({String? root = '/A', bool withBare = true}) =>
      CoreConfig(
        defaultModel: model('full'),
        permissions: const PermissionsConfig(
          mode: ModeId.bypass,
          rules: PolicyRules(toolPolicies: {'write': ToolPolicy.allow}),
        ),
        mcpServers: const [projectServer],
        projectRoot: root,
        withoutProject: withBare
            ? CoreConfig(
                defaultModel: model('bare'),
                permissions: const PermissionsConfig(mode: ModeId.ask),
              )
            : null,
      );

  ({
    BuiltAgentCore core,
    RecordingLogger logger,
    FakeMcpConnector mcp,
    FakeGate gate,
    ScriptedStreamFunction model,
  })
  build(CoreConfig config, {List<Map<String, Object?>> steps = const []}) {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final mcp = FakeMcpConnector();
    final gate = FakeGate();
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    final core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/A'),
        gate: gate,
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        mcp: mcp,
      ),
      config: config,
      streamFunction: scripted.call,
    );
    return (core: core, logger: logger, mcp: mcp, gate: gate, model: scripted);
  }

  group('createSession', () {
    test(
      'a session in the launch root gets the full snapshot and no log',
      () async {
        final h = build(snapshots());

        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/A'),
        );

        expect(session.mode, ModeId.bypass);
        expect(session.model.id, 'full');
        expect(
          [for (final s in h.mcp.requests.single.servers) s.name],
          ['project'],
        );
        expect(h.logger.eventsOf('config.session.outside_root'), isEmpty);
      },
    );

    test('a session in another root does not get the servers of the '
        'project, its mode or model; one log per cwd', () async {
      final h = build(snapshots());

      final first = await h.core.runtime.createSession(SessionSpec(cwd: '/B'));
      await h.core.runtime.createSession(SessionSpec(cwd: '/B'));

      expect(first.mode, ModeId.ask);
      expect(first.model.id, 'bare');
      expect(h.mcp.requests, isEmpty, reason: 'no servers: no connector call');
      final logs = h.logger.eventsOf('config.session.outside_root');
      expect(logs, hasLength(1));
      expect(logs.single.fields['cwd'], '/B');
      expect(logs.single.fields['config_root'], '/A');
      expect(logs.single.fields['session_id'], first.id.value);
    });

    test('a subdirectory is another root: the allow rule of the project '
        'does not apply (scenario "Подкаталог — другой корень")', () async {
      Map<String, Object?> writeStep() =>
          callStep('c1', 'write', {'path': 'f.txt', 'content': 'x'});
      // Режим обоих снимков стандартный, чтобы проверялось только правило.
      final rules = CoreConfig(
        defaultModel: model('full'),
        permissions: const PermissionsConfig(
          rules: PolicyRules(toolPolicies: {'write': ToolPolicy.allow}),
        ),
        projectRoot: '/A',
        withoutProject: CoreConfig(defaultModel: model('bare')),
      );
      final root = build(rules, steps: [writeStep(), textStep('ok')]);
      final sub = build(rules, steps: [writeStep(), textStep('ok')]);

      final a = await root.core.runtime.createSession(SessionSpec(cwd: '/A'));
      await a.prompt([const TextContent('go')]);
      final b = await sub.core.runtime.createSession(
        SessionSpec(cwd: '/A/sub'),
      );
      await b.prompt([const TextContent('go')]);

      expect(root.gate.requests, isEmpty, reason: 'allow applies in the root');
      expect(
        sub.gate.requests,
        hasLength(1),
        reason: 'no allow rule in /A/sub: the gate is asked',
      );
      expect(
        sub.logger.eventsOf('config.session.outside_root').single.fields['cwd'],
        '/A/sub',
      );
    });

    test('paths are compared by components, not as text', () async {
      final h = build(snapshots());

      await h.core.runtime.createSession(SessionSpec(cwd: '/A/'));
      await h.core.runtime.createSession(SessionSpec(cwd: '/x/../A'));

      expect(h.logger.eventsOf('config.session.outside_root'), isEmpty);
    });
  });

  group('without projectRoot or withoutProject the behaviour is unchanged', () {
    test('no projectRoot: every session gets the config', () async {
      final h = build(snapshots(root: null));

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/B'),
      );

      expect(session.mode, ModeId.bypass);
      expect(h.logger.eventsOf('config.session.outside_root'), isEmpty);
    });

    test(
      'no snapshot without the project: every session gets the config',
      () async {
        final h = build(snapshots(withBare: false));

        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/B'),
        );

        expect(session.mode, ModeId.bypass);
        expect(h.logger.eventsOf('config.session.outside_root'), isEmpty);
      },
    );
  });

  group('loadSession follows the same rule', () {
    test('a session loaded for another cwd takes the snapshot without the '
        'project', () async {
      final h = build(snapshots());
      final created = await h.core.runtime.createSession(
        SessionSpec(cwd: '/A'),
      );
      expect(created.mode, ModeId.bypass);
      h.mcp.requests.clear();

      final loaded = await h.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/B',
      );

      expect(loaded.mode, ModeId.ask);
      expect(h.mcp.requests, isEmpty);
      final logs = h.logger.eventsOf('config.session.outside_root');
      expect(logs, hasLength(1));
      expect(logs.single.fields['cwd'], '/B');
      expect(logs.single.fields['session_id'], created.id.value);
    });

    test('a session loaded in the root keeps the full snapshot', () async {
      final h = build(snapshots());
      final created = await h.core.runtime.createSession(
        SessionSpec(cwd: '/A'),
      );

      final loaded = await h.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
      );

      expect(loaded.mode, ModeId.bypass);
      expect(h.logger.eventsOf('config.session.outside_root'), isEmpty);
    });
  });
}
