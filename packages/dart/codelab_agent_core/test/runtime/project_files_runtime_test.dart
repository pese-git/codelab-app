import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../support/models.dart';

/// Файлы проекта сессии (agent-runtime «Файлы проекта сессии»;
/// agent-project-context «Порт файлов проекта»; design.md change
/// `add-agent-project-files`, D1, D4, D6, D14; E-01).
void main() {
  late FakePort port;
  late RecordingLogger logger;
  late List<String> prompts;
  late FakeClock clock;

  /// Ядро над памятью с портом файлов проекта; `links` — «symlink»-и
  /// `realpath`.
  BuiltAgentCore build({
    CoreConfig? config,
    bool withPort = true,
    Map<String, String> links = const {},
  }) {
    clock = FakeClock();
    logger = RecordingLogger();
    prompts = [];
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [textStep('ok'), textStep('ok')],
    }, clock: clock);
    return buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: _LinkEnv(links),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        projectFiles: withPort ? port : null,
      ),
      config: config ?? CoreConfig(defaultModel: testModel),
      streamFunction: (ref, context, {cancel}) {
        prompts.add(context.systemPrompt);
        return scripted.call(ref, context, cancel: cancel);
      },
    );
  }

  setUp(() => port = FakePort());

  Future<String> firstPrompt(AgentSession session) async {
    await session.prompt([const TextContent('go')]);
    return prompts.first;
  }

  group('the query to the port', () {
    test('has the canonical cwd, the trust flag and the budget', () async {
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          trustedProjects: const ['/work/b'],
          projectContextMaxBytes: 1234,
        ),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/b'));

      final query = port.queries.single;
      expect(query.cwd, '/work/b');
      expect(query.projectTrusted, isTrue);
      expect(query.contextMaxBytes, 1234);
      expect(query.cancel.isCancelled, isFalse);
    });

    test('trust follows the cwd of the session, not the launch root', () async {
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          trustedProjects: const ['/work/b'],
          projectRoot: '/work/a',
          withoutProject: CoreConfig(
            defaultModel: testModel,
            trustedProjects: const ['/work/b'],
          ),
        ),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/a'));
      await core.runtime.createSession(SessionSpec(cwd: '/work/b'));

      expect([for (final q in port.queries) q.projectTrusted], [false, true]);
    });

    test('a subdirectory of a trusted root is not trusted', () async {
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          trustedProjects: const ['/work/b'],
        ),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/b/sub'));

      expect(port.queries.single.projectTrusted, isFalse);
    });

    test('a symlink to a trusted root is canonicalized and trusted '
        '(with or without projectRoot)', () async {
      final core = build(
        config: CoreConfig(
          defaultModel: testModel,
          trustedProjects: const ['/work/b'],
        ),
        links: const {'/work/link': '/work/b'},
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/link'));

      expect(port.queries.single.cwd, '/work/b');
      expect(port.queries.single.projectTrusted, isTrue);
    });

    test(
      'a path that cannot be resolved is never trusted (fail closed)',
      () async {
        final core = build(
          config: CoreConfig(
            defaultModel: testModel,
            trustedProjects: const ['/work/missing'],
          ),
        );

        await core.runtime.createSession(SessionSpec(cwd: '/work/missing'));

        // Лексическое совпадение с `trustedProjects` доверия не даёт:
        // `/trusted/../x` без раскрытия symlink — не тот каталог (приоритет 1).
        expect(port.queries.single.cwd, '/work/missing');
        expect(port.queries.single.projectTrusted, isFalse);
      },
    );

    test('loadSession asks the port too, with the cwd it is given', () async {
      final core = build();
      final created = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      port.queries.clear();

      await core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/c',
      );

      expect(port.queries.single.cwd, '/work/c');
    });
  });

  group('the system prompt', () {
    test('has the instruction files, general first (E-01)', () async {
      port.files = ProjectFiles(
        context: [
          ContextFile(path: 'AGENTS.md', content: 'rule A'),
          ContextFile(path: 'pkg/AGENTS.md', content: 'rule B'),
        ],
        contextRoot: ContextRoot.git,
      );
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a/pkg'),
      );
      final prompt = await firstPrompt(session);

      expect(prompt, contains('# Project instructions'));
      expect(prompt.indexOf('rule A'), lessThan(prompt.indexOf('rule B')));
    });

    test('keeps the section after the mode changes', () async {
      port.files = ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
      );
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.setMode(ModeId.plan);
      final prompt = await firstPrompt(session);

      expect(prompt, contains('rule A'));
      expect(prompt, contains('Mode: plan'));
    });

    test('has no section when the budget is 0', () async {
      port.files = ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
      );
      final core = build(
        config: CoreConfig(defaultModel: testModel, projectContextMaxBytes: 0),
      );

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      final prompt = await firstPrompt(session);

      expect(prompt, isNot(contains('Project instructions')));
      expect(port.queries.single.contextMaxBytes, 0);
      expect(logger.eventsOf('project_context.loaded'), isEmpty);
    });

    test('is the old one without a port', () async {
      port.files = ProjectFiles(
        context: [ContextFile(path: 'AGENTS.md', content: 'rule A')],
      );
      final core = build(withPort: false);

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      final prompt = await firstPrompt(session);

      expect(prompt, isNot(contains('Project instructions')));
      expect(port.queries, isEmpty);
      expect(logger.eventsOf('project_context.loaded'), isEmpty);
    });
  });

  group('the port fails', () {
    test('an exception gives a session without files and a log with the '
        'type only', () async {
      port.failWith = StateError('secret-in-message');
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      final prompt = await firstPrompt(session);

      expect(prompt, isNot(contains('Project instructions')));
      final log = logger.eventsOf('project_files.diagnostic').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields['code'], 'unexpected');
      expect(log.fields['session_id'], session.id.value);
      expect(log.fields['message'], contains('StateError'));
      expect(log.toString(), isNot(contains('secret-in-message')));
    });

    test('a port that never completes: the phase times out after 5 s, the '
        'session has no files, the load is cancelled', () async {
      port.gate = Completer<ProjectFiles>().future;
      final core = build();

      final creating = core.runtime.createSession(SessionSpec(cwd: '/work/a'));
      await pumpEventQueue();
      expect(port.queries, hasLength(1));
      await clock.elapse(const Duration(seconds: 4));
      expect(port.queries.single.cancel.isCancelled, isFalse);
      await clock.elapse(const Duration(seconds: 1));

      final session = await creating;
      expect(port.queries.single.cancel.isCancelled, isTrue);
      expect(
        await firstPrompt(session),
        isNot(contains('Project instructions')),
      );
      final log = logger.eventsOf('project_files.diagnostic').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields['code'], 'timeout');
      expect(log.fields['session_id'], session.id.value);
      expect(logger.eventsOf('project_context.loaded'), isEmpty);
      expect(clock.pendingTimers, 0);
    });

    test('dispose while the port never completes: no session', () async {
      port.gate = Completer<ProjectFiles>().future;
      final core = build();

      final creating = core.runtime.createSession(SessionSpec(cwd: '/work/a'));
      await pumpEventQueue();
      final disposing = core.runtime.dispose();

      await expectLater(creating, throwsA(isA<CancelledException>()));
      await disposing;
      expect(clock.pendingTimers, 0);
    });

    test(
      'dispose during load discards the result: no session, no log',
      () async {
        final gate = Completer<ProjectFiles>();
        port.gate = gate.future;
        final core = build();

        final creating = core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );
        // Отмена завершает загрузку сразу, не дожидаясь порта: ожидание
        // ошибки вешается до `dispose()`.
        final cancelled = expectLater(
          creating,
          throwsA(isA<CancelledException>()),
        );
        // Ждём, пока порт получит запрос: тогда загрузка идёт.
        await pumpEventQueue();
        expect(port.queries, hasLength(1));
        final disposing = core.runtime.dispose();
        // Отмена доходит до дочернего токена микрозадачей.
        await pumpEventQueue();
        expect(port.queries.single.cancel.isCancelled, isTrue);
        gate.complete(
          ProjectFiles(
            context: [ContextFile(path: 'AGENTS.md', content: 'late')],
          ),
        );

        await cancelled;
        await disposing;
        expect(logger.eventsOf('project_context.loaded'), isEmpty);
      },
    );
  });

  group('the log (D14)', () {
    test('project_context.loaded names the files and not their text', () async {
      port.files = ProjectFiles(
        context: [
          ContextFile(path: 'AGENTS.md', content: 'sk-test-secret ' * 20),
          ContextFile(path: 'pkg/AGENTS.md', content: 'sk-test-secret'),
        ],
        contextRoot: ContextRoot.git,
      );
      final core = build(
        config: CoreConfig(defaultModel: testModel, projectContextMaxBytes: 14),
      );

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a/pkg'),
      );

      final log = logger.eventsOf('project_context.loaded').single;
      expect(log.level, LogLevel.info);
      expect(log.fields, {
        'session_id': session.id.value,
        'files': ['pkg/AGENTS.md'],
        'bytes': 14,
        'truncated': 0,
        'omitted': 1,
        'root': 'git',
      });
      expect(
        [for (final r in logger.records) r.toString()].join('\n'),
        isNot(contains('sk-test-secret')),
      );
    });

    // agent-project-context «Кавычка в имени каталога»: в атрибуте блока
    // `"` заменяется на `_`, а лог называет настоящий путь без экранирования.
    test('a quote in a directory name: the block attribute is escaped, the '
        'log has the real path', () async {
      port.files = ProjectFiles(
        context: [ContextFile(path: 'a"b/AGENTS.md', content: 'rule Q')],
        contextRoot: ContextRoot.git,
      );
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a/a"b'),
      );
      final prompt = await firstPrompt(session);

      expect(prompt, contains('<project-instructions path="a_b/AGENTS.md">'));
      final log = logger.eventsOf('project_context.loaded').single;
      expect(log.fields['files'], ['a"b/AGENTS.md']);
    });

    test('truncated files are counted', () async {
      port.files = ProjectFiles(
        context: [
          ContextFile(path: 'AGENTS.md', content: 'line one\nline two\nthree'),
        ],
      );
      final core = build(
        config: CoreConfig(defaultModel: testModel, projectContextMaxBytes: 12),
      );

      await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

      final log = logger.eventsOf('project_context.loaded').single;
      expect(log.fields['truncated'], 1);
      expect(log.fields['root'], 'cwd');
    });

    test(
      'every diagnostic is a record; the level follows the diagnostic',
      () async {
        port.files = const ProjectFiles(
          diagnostics: [
            ExtensionDiagnostic(
              path: '/work/a/AGENTS.md',
              level: DiagnosticLevel.error,
              code: 'not_utf8',
              message: 'the file is not valid UTF-8',
            ),
            ExtensionDiagnostic(
              path: '/work/a/x.md',
              level: DiagnosticLevel.warning,
              code: 'syntax',
              message: 'bad',
              line: 4,
              column: 2,
            ),
            ExtensionDiagnostic(
              path: '/work/a/CLAUDE.md',
              level: DiagnosticLevel.info,
              code: 'shadowed',
              message: 'shadowed by AGENTS.md',
            ),
          ],
        );
        final core = build();

        final session = await core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );

        final logs = logger.eventsOf('project_files.diagnostic');
        expect(
          [for (final l in logs) l.level],
          [LogLevel.warning, LogLevel.warning, LogLevel.debug],
        );
        expect(logs[1].fields, {
          'session_id': session.id.value,
          'path': '/work/a/x.md',
          'line': 4,
          'column': 2,
          'code': 'syntax',
          'message': 'bad',
        });
      },
    );
  });

  group('agent definitions in the log', () {
    test(
      'a broken definition logs a diagnostic without its body (D14)',
      () async {
        port.files = ProjectFiles(
          agents: [
            MarkdownFile(
              path: '/work/a/.codelab/agents/bad.md',
              scope: ExtensionScope.project,
              body: 'Never log sk-test-secret anywhere.',
              bodyLine: 6,
              frontmatter: const ConfigTree(
                kind: ConfigLayerKind.project,
                source: '/work/a/.codelab/agents/bad.md',
                values: {
                  'name': 'bad',
                  'description': 'Broken',
                  'mode': 'no-such-mode',
                },
              ),
            ),
          ],
        );
        final core = build(
          config: CoreConfig(
            defaultModel: testModel,
            trustedProjects: const ['/work/a'],
          ),
        );

        await core.runtime.createSession(SessionSpec(cwd: '/work/a'));

        final logs = logger.eventsOf('project_files.diagnostic');
        expect(logs, isNotEmpty);
        expect(logs.first.fields['path'], '/work/a/.codelab/agents/bad.md');
        expect(
          [for (final r in logger.records) r.toString()].join('\n'),
          isNot(contains('sk-test-secret')),
        );
      },
    );
  });
}

/// Порт-фейк: записывает запросы, отдаёт [files], умеет падать и ждать.
final class FakePort implements ProjectFilesSource {
  final queries = <ProjectFilesQuery>[];
  ProjectFiles files = ProjectFiles.empty;
  Object? failWith;
  Future<ProjectFiles>? gate;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    queries.add(query);
    if (failWith case final error?) {
      throw error;
    }
    return gate ?? files;
  }
}

/// Память с «symlink»-ами: `realpath` раскрывает [links], известные каталоги
/// возвращает как есть, остальное — `notFound`; прочее делегируется памяти.
final class _LinkEnv implements ExecutionEnv, DirectoryListing, PathResolver {
  _LinkEnv(this.links);

  final Map<String, String> links;
  final _inner = MemoryExecutionEnv(cwd: '/work/a');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async {
    if (links[path] case final target?) {
      return Ok(target);
    }
    const known = {'/work/a', '/work/b', '/work/c', '/work/a/pkg'};
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
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      _inner.listDir(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}
