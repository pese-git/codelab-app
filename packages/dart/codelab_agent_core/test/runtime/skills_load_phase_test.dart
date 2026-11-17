import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer, withValues;
import '../host/core_harness.dart';
import '../skills/skills_support.dart';
import '../support/models.dart';

/// Фаза открытия сессии «навыки» (agent-skills «Порт файлов навыков», оба
/// сценария; «Каталог навыков сессии»; «Конфигурация навыков»; agent-runtime
/// «Профили хостов и сужение», сценарий «Навыки выключены конфигом»;
/// design.md change `add-agent-skills`, D1, D10; HOST-4).
///
/// Фиксируемый API: `AgentCoreServices.skillFiles` (`SkillFilesSource`),
/// `CoreConfig.skills` (`SkillsConfig`), `HostCapability.skills`, лог
/// `skills.loaded {session_id, count, names, ...}`. Образец —
/// `project_files_runtime_test.dart` (та же фаза для файлов проекта).
void main() {
  late FakeSkillPort skillPort;
  late FakeProjectPort projectPort;
  late RecordingLogger logger;
  late List<String> prompts;
  late FakeClock clock;

  BuiltAgentCore build({
    CoreConfig? config,
    bool withSkillPort = true,
    Map<HostCapability, CapabilityState> narrow = const {},
    ConfigSource? source,
  }) {
    clock = FakeClock();
    logger = RecordingLogger(clock: clock);
    prompts = [];
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [textStep('ok'), textStep('ok')],
    }, clock: clock);
    final effective = config ?? CoreConfig(defaultModel: testModel);
    return buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec, ...narrow}),
      services: AgentCoreServices(
        baseEnv: _Env(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        models: source == null
            ? null
            : StaticModelCatalog(effective.providers, logger: logger),
        projectFiles: projectPort,
        skillFiles: withSkillPort ? skillPort : null,
        config: source,
      ),
      config: effective,
      streamFunction: (ref, context, {cancel}) {
        prompts.add(context.systemPrompt);
        return scripted.call(ref, context, cancel: cancel);
      },
      modelsFor: source == null
          ? null
          : (config) => (
              stream: (ref, context, {cancel}) =>
                  scripted.call(ref, context, cancel: cancel),
              catalog: StaticModelCatalog(config.providers, logger: logger),
            ),
    );
  }

  setUp(() {
    skillPort = FakeSkillPort();
    projectPort = FakeProjectPort();
  });

  Future<String> firstPrompt(AgentSession session) async {
    await session.prompt([const TextContent('go')]);
    return prompts.first;
  }

  group('the query to the port', () {
    test('has the canonical cwd, the trust flag, extra roots in config '
        'order and a live token', () async {
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          trustedProjects: const ['/work/b'],
          skills: const SkillsConfig(extraRoots: ['/opt/s', '.claude/skills']),
        ),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/b'));

      final query = skillPort.queries.single;
      expect(query.cwd, '/work/b');
      expect(query.projectTrusted, isTrue);
      expect(query.extraRoots, ['/opt/s', '.claude/skills']);
      expect(query.cancel.isCancelled, isFalse);
    });

    test('an untrusted cwd is passed as untrusted (fail closed)', () async {
      final core = build();

      await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

      expect(skillPort.queries.single.projectTrusted, isFalse);
    });
  });

  group('parallel phases and the timeout', () {
    test('both ports are asked before either completes', () async {
      projectPort.gate = Completer<ProjectFiles>().future;
      skillPort.gate = Completer<SkillFiles>().future;
      final core = build();

      unawaited(
        core.runtime
            .createSession(SessionSpec(cwd: '/work/a'))
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await pumpEventQueue();

      expect(projectPort.queries, hasLength(1));
      expect(skillPort.queries, hasLength(1));
    });

    test(
      'scenario "Медленный корень не отнимает инструкции проекта": the '
      'skills phase times out after 5 s, AGENTS.md is in the prompt',
      () async {
        projectPort.files = ProjectFiles(
          context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
        );
        skillPort.gate = Completer<SkillFiles>().future;
        final core = build();

        final creating = core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );
        await pumpEventQueue();
        await clock.elapse(const Duration(seconds: 4));
        expect(skillPort.queries.single.cancel.isCancelled, isFalse);
        await clock.elapse(const Duration(seconds: 1));

        final session = await creating;
        expect(skillPort.queries.single.cancel.isCancelled, isTrue);
        final prompt = await firstPrompt(session);
        expect(prompt, contains('# Project instructions'));
        expect(prompt, contains('rule A'));
        final log = logger.eventsOf('project_files.diagnostic').single;
        expect(log.level, LogLevel.warning);
        expect(log.fields['code'], 'timeout');
        expect(log.fields['session_id'], session.id.value);
        expect(logger.eventsOf('skills.loaded'), isEmpty);
        expect(clock.pendingTimers, 0);
      },
    );

    test(
      'a late result after the timeout does not reach the session',
      () async {
        final gate = Completer<SkillFiles>();
        skillPort.gate = gate.future;
        final core = build();
        final creating = core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );
        await pumpEventQueue();
        await clock.elapse(const Duration(seconds: 5));
        final session = await creating;

        gate.complete(SkillFiles(skills: [validSkill('late')]));
        await pumpEventQueue();

        expect(logger.eventsOf('skills.loaded'), isEmpty);
        expect(await firstPrompt(session), isNot(contains('late')));
      },
    );

    test(
      'a slow project phase does not take the skills of the session',
      () async {
        projectPort.gate = Completer<ProjectFiles>().future;
        skillPort.files = SkillFiles(skills: [validSkill('notes')]);
        final core = build();

        final creating = core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );
        await pumpEventQueue();
        await clock.elapse(const Duration(seconds: 5));
        final session = await creating;

        final log = logger.eventsOf('skills.loaded').single;
        expect(log.fields['session_id'], session.id.value);
        expect(log.fields['names'], ['notes']);
      },
    );
  });

  group('the port fails', () {
    test('an exception: a session without skills, the log has the type '
        'only, the project phase is intact', () async {
      projectPort.files = ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
      );
      skillPort.failWith = StateError('secret-in-message');
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(await firstPrompt(session), contains('rule A'));
      final log = logger.eventsOf('project_files.diagnostic').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields['code'], 'unexpected');
      expect(log.fields['session_id'], session.id.value);
      expect(log.fields['message'], 'skills could not be read: StateError');
      expect(log.toString(), isNot(contains('secret-in-message')));
      expect(session.skills, same(SkillCatalog.empty));
      expect(logger.eventsOf('skills.loaded'), isEmpty);
    });

    test('scenario "Отмена во время загрузки навыков": dispose() -> '
        'createSession is cancelled, no session, the late result is '
        'discarded', () async {
      final gate = Completer<SkillFiles>();
      skillPort.gate = gate.future;
      final core = build();

      final creating = core.runtime.createSession(SessionSpec(cwd: '/work/a'));
      final cancelled = expectLater(
        creating,
        throwsA(isA<CancelledException>()),
      );
      await pumpEventQueue();
      expect(skillPort.queries, hasLength(1));
      final disposing = core.runtime.dispose();
      await pumpEventQueue();
      expect(skillPort.queries.single.cancel.isCancelled, isTrue);
      gate.complete(SkillFiles(skills: [validSkill('late')]));

      await cancelled;
      await disposing;
      expect(logger.eventsOf('skills.loaded'), isEmpty);
      expect(clock.pendingTimers, 0);
    });

    test('dispose while the port never completes: no session', () async {
      skillPort.gate = Completer<SkillFiles>().future;
      final core = build();

      final creating = core.runtime.createSession(SessionSpec(cwd: '/work/a'));
      final cancelled = expectLater(
        creating,
        throwsA(isA<CancelledException>()),
      );
      await pumpEventQueue();
      final disposing = core.runtime.dispose();

      await cancelled;
      await disposing;
      expect(clock.pendingTimers, 0);
    });
  });

  group('the port is not called', () {
    test('without a port (null): a session without skills', () async {
      skillPort.files = SkillFiles(skills: [validSkill('notes')]);
      final core = build(withSkillPort: false);

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      // Инвариант D16: без порта capability остаётся `on`, каталог пуст.
      expect(core.plan.profile.isOn(HostCapability.skills), isTrue);
      expect(core.plan.offReasons, isNot(contains(HostCapability.skills)));
      expect(session.skills, same(SkillCatalog.empty));
      expect(core.plan.toolNames, isNot(contains('skill')));
      expect(core.plan.promptSections, isNot(contains('skills.catalog')));
      expect(session.skills.commands, isEmpty);
      expect(session.skills.modelVisible, isEmpty);
      expect(skillPort.queries, isEmpty);
      expect(logger.eventsOf('skills.loaded'), isEmpty);
    });

    test('scenario "Навыки выключены конфигом" (Q45): skills.enabled: false '
        '-> the port is silent, the snapshot is empty, the capability stays '
        'on', () async {
      skillPort.files = SkillFiles(skills: [validSkill('notes')]);
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          skills: const SkillsConfig(enabled: false),
        ),
      );

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      // Q45: capability сужает только профиль; `skills.enabled` действует на
      // сессии своей папки, поэтому `offReasons` не содержит `skills`.
      expect(core.plan.offReasons, isNot(contains(HostCapability.skills)));
      expect(core.plan.profile.isOn(HostCapability.skills), isTrue);
      expect(session.skills, same(SkillCatalog.empty));
      expect(skillPort.queries, isEmpty);
      expect(logger.eventsOf('skills.loaded'), isEmpty);
      expect([
        for (final c in session.commands) c.name,
      ], isNot(contains(startsWith('skill:'))));
    });

    test('scenario "Навыки выключены профилем" (HOST-4): offReasons has a '
        'reason for skills, no port call, no catalog section, no skill tool, '
        'no skill:* commands', () async {
      skillPort.files = SkillFiles(skills: [validSkill('notes')]);
      final core = build(
        narrow: const {HostCapability.skills: CapabilityOff('test')},
      );

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(core.plan.offReasons[HostCapability.skills], isNotEmpty);
      expect(skillPort.queries, isEmpty);
      expect(session.skills, same(SkillCatalog.empty));
      expect(core.plan.toolNames, isNot(contains('skill')));
      expect(core.plan.promptSections, isNot(contains('skills.catalog')));
      expect([
        for (final c in session.commands) c.name,
      ], isNot(contains(startsWith('skill:'))));
      final prompt = await firstPrompt(session);
      expect(prompt, isNot(contains('notes')));
    });

    test('a profile with skills on keeps the capability in the plan', () {
      final core = build();

      expect(core.plan.offReasons, isNot(contains(HostCapability.skills)));
      expect(core.plan.profile.isOn(HostCapability.skills), isTrue);
    });
  });

  group('loaded skills and the log', () {
    test(
      'skills.loaded names the skills sorted by name, without bodies',
      () async {
        skillPort.files = SkillFiles(
          skills: [
            validSkill('zeta', body: 'secret-token-123'),
            validSkill('alpha'),
          ],
        );
        final core = build();

        final session = await core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );

        final log = logger.eventsOf('skills.loaded').single;
        expect(log.level, LogLevel.info);
        expect(log.fields['session_id'], session.id.value);
        expect(log.fields['count'], 2);
        expect(log.fields['names'], ['alpha', 'zeta']);
        expect(
          [for (final r in logger.records) r.toString()].join('\n'),
          isNot(contains('secret-token-123')),
        );
      },
    );

    test('catalog diagnostics go to project_files.diagnostic with the '
        'level of the diagnostic', () async {
      skillPort.files = SkillFiles(
        skills: [
          skillFile('bad', frontmatter: {'name': 'bad'}),
          validSkill('ok'),
        ],
        diagnostics: const [
          ExtensionDiagnostic(
            path: '/home/.codelab/skills/x',
            level: DiagnosticLevel.warning,
            code: 'shadowed',
            message: 'shadowed',
          ),
        ],
      );
      final core = build();

      await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

      final codes = [
        for (final l in logger.eventsOf('project_files.diagnostic'))
          l.fields['code'],
      ];
      expect(codes, containsAll(['shadowed', 'missing_description']));
    });

    test('skills.disabled and max_skills of the config apply to the '
        'catalog of the session', () async {
      skillPort.files = SkillFiles(
        skills: [validSkill('a'), validSkill('b'), validSkill('c')],
      );
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          skills: const SkillsConfig(disabled: ['a'], maxSkills: 1),
        ),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

      expect(logger.eventsOf('skills.loaded').single.fields['names'], ['b']);
    });
  });

  group('session/load', () {
    test('loadSession runs the skills phase again with the cwd it is given; '
        'the snapshot is built anew', () async {
      skillPort.files = SkillFiles(skills: [validSkill('notes')]);
      final core = build();
      final created = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      skillPort.queries.clear();
      skillPort.files = SkillFiles(
        skills: [validSkill('notes'), validSkill('pdf')],
      );

      await core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/c',
      );

      expect(skillPort.queries.single.cwd, '/work/c');
      final logs = logger.eventsOf('skills.loaded');
      expect(logs, hasLength(2));
      expect(logs.last.fields['names'], ['notes', 'pdf']);
      expect([for (final k in created.skills.skills) k.name], ['notes']);
    });

    test('loadSession with skills off does not call the port', () async {
      final core = build(
        narrow: const {HostCapability.skills: CapabilityOff('test')},
      );
      final created = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/c',
      );

      expect(skillPort.queries, isEmpty);
    });
  });

  group('config reload (agent-skills «Каталог навыков сессии», '
      '«Конфигурация навыков»)', () {
    test('a reload does not call the port; the new skills.* values apply '
        'to the next session', () async {
      skillPort.files = SkillFiles(
        skills: [validSkill('pdf'), validSkill('notes')],
      );
      final user = withValues(baseValues(), {
        'skills': {'disabled': <String>[]},
      });
      final source = _MutableSource(user);
      final core = build(config: source.initial.config, source: source);
      final first = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      expect(logger.eventsOf('skills.loaded').single.fields['names'], [
        'notes',
        'pdf',
      ]);
      skillPort.queries.clear();

      source.values = withValues(baseValues(), {
        'skills': {
          'disabled': ['pdf'],
          'extra_roots': ['/opt/more'],
        },
      });
      final report = await core.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.applied);
      // Перезагрузка не перечитывает каталоги живых сессий.
      expect(skillPort.queries, isEmpty);
      expect(logger.eventsOf('skills.loaded'), hasLength(1));
      // Каталог живой сессии не меняется (SKL-4, D10).
      expect([for (final k in first.skills.skills) k.name], ['notes', 'pdf']);

      final second = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(skillPort.queries.single.extraRoots, ['/opt/more']);
      final logs = logger.eventsOf('skills.loaded');
      expect(logs, hasLength(2));
      expect(logs.last.fields['session_id'], second.id.value);
      expect(logs.last.fields['names'], ['notes']);
      expect([for (final k in second.skills.skills) k.name], ['notes']);
      expect([for (final k in first.skills.skills) k.name], ['notes', 'pdf']);
      expect(first.id, isNot(second.id));
    });
  });
}

/// Порт файлов проекта: тот же приём, что в `project_files_runtime_test`.
final class FakeProjectPort implements ProjectFilesSource {
  final queries = <ProjectFilesQuery>[];
  ProjectFiles files = ProjectFiles.empty;
  Future<ProjectFiles>? gate;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    queries.add(query);
    return gate ?? files;
  }
}

/// Источник конфигурации с изменяемыми значениями пользовательского слоя.
final class _MutableSource implements ConfigSource {
  _MutableSource(this.values) {
    _initial = _build(null);
  }

  Map<String, Object?> values;
  late final ConfigLoadResult _initial;
  final _changes = StreamController<void>.broadcast();

  ConfigLoadResult _build(List<String>? pinned) => CoreConfig.fromLayers(
    [layer(values)],
    environment: const {},
    pinnedTrustedProjects: pinned,
  );

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async =>
      _build(_initial.config!.trustedProjects);

  @override
  Stream<void> get changes => _changes.stream;
}

/// Окружение с `realpath`: известные каталоги возвращаются как есть.
final class _Env implements ExecutionEnv, PathResolver {
  final _inner = MemoryExecutionEnv(cwd: '/work/a');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    const known = {'/work/a', '/work/b', '/work/c'};
    return known.contains(path)
        ? Ok(path)
        : Err(FileError(FileErrorCode.notFound, path));
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}
