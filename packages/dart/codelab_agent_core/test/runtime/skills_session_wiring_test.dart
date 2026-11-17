import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../env/machine_env.dart';
import '../host/core_harness.dart' show callStep, inMemoryJournal, textStep;
import '../permissions/fake_gate.dart';
import '../skills/skills_support.dart';
import '../support/models.dart';
import '../tools/fake_shell.dart';

const userHome = '/home/.codelab/skills';
const notes = '$userHome/notes';
const local = '/work/a/.agents/skills/local';

/// Подключение навыков в рантайме (agent-execution-env «Корни только для
/// чтения», абзац о рантайме и сценарий «Сессия внутри каталога навыка»;
/// agent-skills «Сопутствующие файлы и скрипты навыка», сценарии «Чтение
/// файла пользовательского навыка», «Запись в каталог навыка», «Скрипт
/// пользовательского навыка через клиента ACP»; agent-permissions «Критические
/// пути правок конфигурации агента», «Относительный корень extra_roots защищён
/// в сессии»; design.md change `add-agent-skills`, D5, D9, D17; Q23, Q27,
/// Q46 (а)).
///
/// Фиксируемый API: `AgentCoreServices.hostFiles` (`ExecutionEnv?`),
/// `SessionHostPorts.execOnHost` (`bool`, по умолчанию `false`),
/// `SkillFiles.sessionRoots` (список строк, по умолчанию пуст). Рантайм
/// оборачивает env после фаз загрузки: `execInReadOnlyRoots = hostFiles !=
/// null && (ports.env == null || ports.execOnHost)`.
void main() {
  late FakeSkillPort port;
  late FakeShellEnv base;
  late MemoryExecutionEnv hostFs;
  late FakeGate gate;
  late RecordingLogger logger;
  late List<LlmContext> contexts;
  late FakeClock clock;

  setUp(() async {
    port = FakeSkillPort();
    clock = FakeClock();
    logger = RecordingLogger(clock: clock);
    gate = FakeGate();
    contexts = [];
    base = FakeShellEnv(MemoryExecutionEnv(cwd: '/work/a'), answering('ok\n'));
    hostFs = MemoryExecutionEnv(cwd: '/');
    await hostFs.writeText('$notes/ref.md', 'reference text\n');
    await base.writeText('$local/references/vendor/a.md', 'local ref\n');
    port.files = SkillFiles(
      skills: [
        skillFile(
          'notes',
          frontmatter: {'name': 'notes', 'description': 'About notes.'},
          root: userHome,
        ),
        skillFile(
          'local',
          frontmatter: {'name': 'local', 'description': 'About local.'},
          root: '/work/a/.agents/skills',
          scope: ExtensionScope.project,
        ),
      ],
    );
  });

  BuiltAgentCore build(
    List<Map<String, Object?>> steps, {
    bool withHostFiles = true,
    Map<HostCapability, CapabilityState> narrow = const {},
    SkillsConfig skills = const SkillsConfig(),
    AgentConfigPaths? configPaths,
    ExecutionEnv? baseEnv,
    String platform = 'unknown',
  }) {
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    return buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...narrow}),
      services: AgentCoreServices(
        baseEnv: baseEnv ?? base,
        gate: gate,
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        skillFiles: port,
        platform: platform,
        hostFiles: withHostFiles ? hostFs : null,
        agentConfigPaths: configPaths,
      ),
      config: CoreConfig(
        defaultModel: testModel,
        skills: skills,
        permissions: const PermissionsConfig(mode: ModeId.bypass),
      ),
      streamFunction: (ref, context, {cancel}) {
        contexts.add(context);
        return scripted.call(ref, context, cancel: cancel);
      },
    );
  }

  Future<AgentSession> open(
    BuiltAgentCore core, {
    String cwd = '/work/a',
    SessionHostPorts ports = const SessionHostPorts(),
  }) => core.runtime.createSession(SessionSpec(cwd: cwd, ports: ports));

  /// Текст последнего результата инструмента из последнего запроса модели.
  String lastResult() =>
      (contexts.last.messages
              .whereType<ToolResultMessage>()
              .last
              .content
              .whereType<TextContent>()
              .map((b) => b.text))
          .join('\n');

  bool lastIsError() =>
      contexts.last.messages.whereType<ToolResultMessage>().last.isError;

  Future<void> go(AgentSession s) => s.prompt([const TextContent('go')]);

  group('read and write of a user skill (hostFiles)', () {
    test('scenario "Чтение файла пользовательского навыка": read comes from '
        'hostFiles, not from the session env', () async {
      final core = build([
        callStep('c1', 'read', {'path': '$notes/ref.md'}),
        textStep('ok'),
      ]);

      await go(await open(core));

      expect(lastIsError(), isFalse);
      expect(lastResult(), contains('reference text'));
      expect(base.commands, isEmpty);
    });

    test('scenario "Запись в каталог навыка": outsideWorkspace, the file is '
        'unchanged', () async {
      final core = build([
        callStep('c1', 'write', {'path': '$notes/ref.md', 'content': 'x'}),
        textStep('ok'),
      ]);

      await go(await open(core));

      expect(lastIsError(), isTrue);
      expect(lastResult(), 'Path is outside the workspace: $notes/ref.md');
      expect(
        (await hostFs.readText('$notes/ref.md') as Ok<String, FileError>).value,
        'reference text\n',
      );
    });

    test('without hostFiles there are no roots: read is outsideWorkspace, '
        'but a skill inside the workspace is read and trusted', () async {
      final core = build([
        callStep('c1', 'read', {'path': '$notes/ref.md'}),
        callStep('c2', 'read', {'path': '$local/references/vendor/a.md'}),
        textStep('ok'),
      ], withHostFiles: false);

      await go(await open(core));

      final results = contexts.last.messages
          .whereType<ToolResultMessage>()
          .toList();
      final texts = [
        for (final r in results) (r.content.single as TextContent).text,
      ];
      expect(texts.first, 'Path is outside the workspace: $notes/ref.md');
      expect(texts.last, contains('local ref'));
      expect(texts.last, isNot(contains('untrusted-content')));
    });
  });

  group('exec with cwd in the skill dir (Q17, Q23)', () {
    final hint =
        'The working directory $notes is outside the client workspace; run '
        'the skill script by its absolute path from the skill block, with '
        'the workspace as the working directory.';

    List<Map<String, Object?>> execSteps() => [
      callStep('c1', 'exec', {'command': 'python3 scripts/x.py', 'cwd': notes}),
      textStep('ok'),
    ];

    test('ports.env == null: the session runs on the agent machine, the '
        'command reaches the env', () async {
      final core = build(execSteps());

      await go(await open(core));

      expect(lastIsError(), isFalse);
      expect(base.commands, ['python3 scripts/x.py']);
    });

    test('a client env without execOnHost: the hint, the client env is not '
        'called', () async {
      final client = FakeShellEnv(
        MemoryExecutionEnv(cwd: '/work/a'),
        answering('client\n'),
      );
      final core = build(execSteps());

      await go(await open(core, ports: SessionHostPorts(env: client)));

      expect(lastIsError(), isTrue);
      expect(lastResult(), hint);
      expect(client.commands, isEmpty);
      expect(base.commands, isEmpty);
    });

    test('a client env with execOnHost: true: the command is passed', () async {
      final client = FakeShellEnv(
        MemoryExecutionEnv(cwd: '/work/a'),
        answering('client\n'),
      );
      final core = build(execSteps());

      await go(
        await open(
          core,
          ports: SessionHostPorts(env: client, execOnHost: true),
        ),
      );

      expect(lastIsError(), isFalse);
      expect(client.commands, ['python3 scripts/x.py']);
    });

    test(
      'without hostFiles the flag is false: the former outsideWorkspace',
      () async {
        final core = build(execSteps(), withHostFiles: false);

        await go(await open(core));

        expect(lastResult(), 'Path is outside the workspace: $notes');
        expect(base.commands, isEmpty);
      },
    );

    test(
      'a skill dir inside the workspace: terminal/create goes as usual',
      () async {
        final client = FakeShellEnv(
          MemoryExecutionEnv(cwd: '/work/a'),
          answering('client\n'),
        );
        await client.writeText('$local/.keep', '');
        final core = build([
          callStep('c1', 'exec', {'command': 'ls', 'cwd': local}),
          textStep('ok'),
        ]);

        await go(await open(core, ports: SessionHostPorts(env: client)));

        expect(client.commands, ['ls']);
      },
    );
  });

  group('the registry of the session (D17)', () {
    test('read and exec are replaced in place: the order of schemas is the '
        'order of a session without skills, skill goes after', () async {
      final bare = build([textStep('ok')]);
      port.files = const SkillFiles();
      await go(await open(bare));
      final plain = [for (final t in contexts.first.tools) t.name];
      contexts.clear();
      port.files = SkillFiles(
        skills: [
          skillFile(
            'notes',
            frontmatter: {'name': 'notes', 'description': 'About notes.'},
            root: userHome,
          ),
        ],
      );
      final core = build([textStep('ok')]);

      await go(await open(core));

      final names = [for (final t in contexts.first.tools) t.name];
      expect(names.where((n) => n != 'skill').toList(), plain);
      expect(names, contains('skill'));
    });

    test(
      'a profile without exec does not get exec because of skills',
      () async {
        final core = build(
          [textStep('ok')],
          narrow: const {HostCapability.shellExec: CapabilityOff('test')},
        );

        await go(await open(core));

        expect(
          contexts.first.tools.map((t) => t.name),
          isNot(contains('exec')),
        );
      },
    );
  });

  group('a session inside a skill directory', () {
    test('scenario "Сессия внутри каталога навыка": the dir is the working '
        'folder, write into it works', () async {
      base = FakeShellEnv(MemoryExecutionEnv(cwd: notes), answering('ok\n'));
      final core = build([
        callStep('c1', 'write', {'path': 'out.md', 'content': 'result'}),
        textStep('ok'),
      ]);

      await go(await open(core, cwd: notes));

      expect(lastIsError(), isFalse);
      expect(
        (await base.readText('$notes/out.md') as Ok<String, FileError>).value,
        'result',
      );
    });
  });

  group('PERM-11 paths of the session (Q27, Q46)', () {
    Future<void> run(BuiltAgentCore core, String cwd) async {
      final session = await open(core, cwd: cwd);
      await go(session);
    }

    List<Map<String, Object?>> write(String path) => [
      callStep('c1', 'write', {'path': path, 'content': 'x'}),
      textStep('ok'),
    ];

    test('write into a path of SkillFiles.sessionRoots is critical; the '
        'session with another cwd is not affected', () async {
      port.files = const SkillFiles(sessionRoots: ['/work/a/.claude/skills']);
      await run(
        build(write('/work/a/.claude/skills/lint/SKILL.md')),
        '/work/a',
      );
      expect(gate.requests, hasLength(1));
      expect(gate.requests.single.allowAlwaysOffered, isFalse);

      gate.requests.clear();
      port.files = const SkillFiles();
      contexts.clear();
      await run(
        build(write('/work/b/.claude/skills/lint/SKILL.md')),
        '/work/b',
      );
      expect(gate.requests, isEmpty);
    });

    test('without a host value the case of the file system follows the '
        'platform: macOS protects .CLAUDE too', () async {
      port.files = const SkillFiles(sessionRoots: ['/work/a/.claude/skills']);

      await run(
        build(write('/work/a/.CLAUDE/skills/lint/SKILL.md'), platform: 'macos'),
        '/work/a',
      );
      expect(gate.requests, hasLength(1));

      gate.requests.clear();
      contexts.clear();
      await run(
        build(write('/work/a/.CLAUDE/skills/lint/SKILL.md'), platform: 'linux'),
        '/work/a',
      );
      expect(gate.requests, isEmpty);
    });

    test('skills.enabled: false: the port is silent, no session paths '
        '(Q46 (а))', () async {
      port.files = const SkillFiles(sessionRoots: ['/work/a/.claude/skills']);

      await run(
        build(
          write('/work/a/.claude/skills/lint/SKILL.md'),
          skills: const SkillsConfig(enabled: false),
        ),
        '/work/a',
      );

      expect(port.queries, isEmpty);
      expect(gate.requests, isEmpty);
    });

    test('E1 for a directory of the snapshot: a script by absolute path is '
        'not critical, another file of the skill is', () async {
      // Политика проверяет «обычный файл» через PathResolver хоста.
      final machine = MachineEnv(cwd: '/work/a');
      await machine.writeText('$notes/scripts/x.py', 'print(1)\n');
      await machine.writeText('$notes/data.json', '{}\n');
      port.files = SkillFiles(
        skills: port.files.skills,
        sessionRoots: const [],
      );
      final paths = AgentConfigPaths(paths: [userHome]);

      await run(
        build(
          [
            callStep('c1', 'exec', {'command': 'python3 $notes/scripts/x.py'}),
            textStep('ok'),
          ],
          configPaths: paths,
          baseEnv: machine,
        ),
        '/work/a',
      );
      expect(gate.requests, isEmpty);

      contexts.clear();
      await run(
        build(
          [
            callStep('c1', 'exec', {'command': 'python3 $notes/data.json'}),
            textStep('ok'),
          ],
          configPaths: paths,
          baseEnv: machine,
        ),
        '/work/a',
      );
      expect(gate.requests, hasLength(1));
    });
  });
}
