import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../support/models.dart';
import '../tools/capability_envs.dart';
import '../mcp/fake_mcp_connector.dart';
import '../tools/fake_shell.dart';
import 'core_harness.dart';

void main() {
  // agent-runtime «Матрица профиля»: схемы запроса — read, write, edit,
  // task_create, task_update, task_list, task_get, ls, search в этом порядке;
  // в промпте нет tools/exec, зато есть tools/tasks (якорь task_create, D13,
  // D32). `agent` — последний встроенный инструмент сессии (субагенты включены
  // по умолчанию); сужение `subagents.enabled: false` — `subagents_runtime_test`.
  test('agent-serve over the memory env without shell', () async {
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      steps: [
        {
          ...textStep('ok'),
          'expect': {
            'tools': [
              'read',
              'write',
              'edit',
              'task_create',
              'task_update',
              'task_list',
              'task_get',
              'ls',
              'search',
              'agent',
            ],
          },
        },
      ],
    );

    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await session.prompt([const TextContent('hi')]);

    h.model.verify();
    // Порядок регистрации §10.7, шаг 5: базовые, затем по capability.
    expect(h.core.plan.toolNames, [
      'read',
      'write',
      'edit',
      'task_create',
      'task_update',
      'task_list',
      'task_get',
      'ls',
      'search',
    ]);
    expect(h.core.plan.toolNames, isNot(contains('update_plan')));
    expect(h.core.plan.offReasons.keys, [
      HostCapability.shellExec,
      HostCapability.sessionPersistence,
      HostCapability.mcp,
    ]);
    expect(h.core.plan.promptSections, isNot(contains('tools.exec')));
    expect(h.core.plan.promptSections, contains('tools.tasks'));
    expect(h.core.plan.promptSections, isNot(contains('tools.plan')));
    expect(h.logger.eventsOf('host.plan'), hasLength(1));
  });

  test('exec is registered when shellExec is on', () {
    final h = CoreHarness.build(
      baseEnv: FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering('')),
      gate: FakeGate(),
      steps: const [],
    );

    expect(h.core.plan.toolNames, [
      'read',
      'write',
      'edit',
      'task_create',
      'task_update',
      'task_list',
      'task_get',
      'exec',
      'ls',
      'search',
    ]);
  });

  test('shellExec over the memory env is a wiring error (HOST-3)', () {
    expect(
      () => CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: FakeGate(),
        steps: const [],
      ),
      throwsA(
        isA<HostWiringException>().having(
          (e) => e.message,
          'message',
          contains('shellExec'),
        ),
      ),
    );
  });

  test(
    'without a gate interactiveApproval is off and a write is denied (PERM-5)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/proj/a.txt', 'a\n');
      final h = CoreHarness.build(
        baseEnv: memory,
        narrow: noExec,
        steps: [
          callStep('c1', 'edit', {
            'path': 'a.txt',
            'oldText': 'a',
            'newText': 'b',
          }),
          textStep('could not'),
        ],
      );

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final result = await session.prompt([const TextContent('edit')]);

      expect(
        h.core.plan.offReasons[HostCapability.interactiveApproval],
        'PermissionGate не передан',
      );
      expect(result.reason, TurnEndReason.completed);
      expect(
        await memory.readText('/proj/a.txt'),
        const Ok<String, FileError>('a\n'),
      );
      final request = h.model.requests[1].messages.last as ToolResultMessage;
      expect(
        (request.content.single as TextContent).text,
        contains('no approval interface is available'),
      );
    },
  );

  test('the policy is the first hook; host hooks come after it', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/a.txt', 'a\n');
    final seen = <String>[];
    final h = CoreHarness.build(
      baseEnv: memory,
      narrow: noExec,
      gate: gateAnswering(PermissionDecision.rejectOnce),
      steps: [
        callStep('c1', 'read', {'path': 'a.txt'}),
        callStep('c2', 'edit', {
          'path': 'a.txt',
          'oldText': 'a',
          'newText': 'b',
        }),
        textStep('done'),
      ],
    );

    final session = await h.core.runtime.createSession(
      SessionSpec(
        cwd: '/proj',
        extraBeforeToolCall: [
          (call, args, ctx) async {
            seen.add('before ${call.name}');
            return null;
          },
        ],
        extraAfterToolCall: [
          (call, result, isError) async {
            seen.add('after ${call.name}');
            return null;
          },
        ],
      ),
    );
    await session.prompt([const TextContent('go')]);

    expect(seen, ['before read', 'after read']);
  });

  test(
    'every session tool works on one bounded env of the session (ENV-2)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/other/x.txt', 'x\n');
      final h = CoreHarness.build(
        baseEnv: memory,
        narrow: noExec,
        gate: FakeGate(),
        steps: [
          callStep('c1', 'read', {'path': '/other/x.txt'}),
          textStep('no'),
        ],
      );

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.prompt([const TextContent('read')]);

      final result = h.model.requests[1].messages.last as ToolResultMessage;
      expect(
        (result.content.single as TextContent).text,
        'Path is outside the workspace: /other/x.txt',
      );
    },
  );

  test('without DirectoryListing ls and search are not registered', () {
    final h = CoreHarness.build(
      baseEnv: FilesOnlyEnv(MemoryExecutionEnv(cwd: '/proj')),
      narrow: noExec,
      gate: FakeGate(),
      steps: const [],
    );

    expect(h.core.plan.toolNames, [
      'read',
      'write',
      'edit',
      'task_create',
      'task_update',
      'task_list',
      'task_get',
    ]);
    expect(h.core.plan.offReasons.keys, contains(HostCapability.fileListing));
  });

  // TSK-1: событие списка приходит между ToolCallStarted и ToolCallFinished
  // своего вызова (agent-tools «Инструменты списка задач»).
  test('task_create of a session reaches its event stream', () async {
    final h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      steps: [
        callStep('c1', 'task_create', {'subject': 'step'}),
        textStep('ok'),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.bypass),
    );
    final seen = <Type>[];
    session.events.listen((e) => seen.add(e.runtimeType));

    await session.prompt([const TextContent('plan')]);
    await pumpEventQueue();

    final changed = seen.indexOf(TaskListChanged);
    expect(changed, greaterThan(seen.indexOf(ToolCallStarted)));
    expect(changed, lessThan(seen.indexOf(ToolCallFinished)));
  });

  group('sessionPersistence (§10.8, design.md D12)', () {
    BuiltAgentCore build({required bool persistent}) => buildAgentCore(
      profile: HostProfile.of(
        'embedded-cli',
      ).narrowed({...noExec, if (!persistent) ...inMemoryJournal}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: FakeGate(),
        logger: RecordingLogger(),
        clock: FakeClock(),
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
      ),
      config: CoreConfig(defaultModel: testModel),
      streamFunction: ScriptedStreamFunction.fromJson(const {'steps': []}).call,
    );

    test('a persistent journal over the memory store is a wiring error', () {
      expect(
        () => build(persistent: true),
        throwsA(
          isA<HostWiringException>().having(
            (e) => e.message,
            'message',
            contains('sessionPersistence'),
          ),
        ),
      );
    });

    test('off — the memory store is fine and the reason is in the plan', () {
      final core = build(persistent: false);

      expect(
        core.plan.offReasons[HostCapability.sessionPersistence],
        isNotEmpty,
      );
    });
  });

  group('capability mcp (design.md change add-agent-mcp-client, D3)', () {
    test('without services.mcp the capability is off with a reason', () {
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        steps: const [],
      );

      expect(
        h.core.plan.offReasons[HostCapability.mcp],
        'сервис MCP не передан',
      );
      expect(h.core.plan.profile.isOn(HostCapability.mcp), isFalse);
    });

    test('a connector with both transports keeps the capability on', () {
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        steps: const [],
        mcp: FakeMcpConnector(),
      );

      expect(h.core.plan.offReasons, isNot(contains(HostCapability.mcp)));
      expect(h.core.plan.profile.isOn(HostCapability.mcp), isTrue);
    });

    test('a connector without a transport of the capability is a wiring '
        'error that names mcp and the transport (HOST-3)', () {
      expect(
        () => CoreHarness.build(
          baseEnv: MemoryExecutionEnv(cwd: '/proj'),
          narrow: noExec,
          gate: FakeGate(),
          steps: const [],
          mcp: FakeMcpConnector(transports: {'stdio'}),
        ),
        throwsA(
          isA<HostWiringException>().having(
            (e) => e.message,
            'message',
            allOf(contains('mcp'), contains('http')),
          ),
        ),
      );
    });

    test('a narrowed capability needs only its own transports', () {
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: {
          ...noExec,
          HostCapability.mcp: const CapabilityTransport({
            'http',
          }, 'профиль без процессов'),
        },
        gate: FakeGate(),
        steps: const [],
        mcp: FakeMcpConnector(transports: {'http'}),
      );

      expect(h.core.plan.profile.isOn(HostCapability.mcp), isTrue);
    });
  });
}
