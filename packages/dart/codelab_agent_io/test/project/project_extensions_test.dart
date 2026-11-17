import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `loadProjectExtensions`: файлы проекта и навыки папки так, как их прочитает
/// сессия агента (client-agent-setup «Обзор расширений агента»; design.md
/// change `add-app-skills-page`, D3, D15; задача 1.1).
///
/// Почему отдельный файл: расчёт каноничной папки, доверия и двух
/// параллельных фаз раньше жил приватным кодом `ConfigCommands._fileLines`;
/// теперь его делят `config check` и мост страницы навыков, и правило не
/// должно разойтись. Здесь проверяется сама функция на временных каталогах и
/// фейковых портах; неизменность вывода `config check` стерегут его
/// существующие тесты (`config_check_skills_test.dart`, тесты файлов проекта).
///
/// Фиксируемый API (design.md D3): `loadProjectExtensions({cwd, config,
/// environment, projectFiles, skillFiles, timeout})`; `ProjectExtensions`
/// (`cwd`, `trusted`, `contextRoot`, `codelabHome`, `projectFiles`, `skills`,
/// `skillRoots`); `PhaseOutcome` = `PhaseLoaded(value)` | `PhaseTimedOut` |
/// `PhaseFailed(errorType)`; `SkillRootInfo(scope, path, extraRoot)`.
void main() {
  late Directory root;
  late String base;
  late String home;
  late String userHome;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('project_ext_');
    root = Directory(created.resolveSymbolicLinksSync());
    base = root.path;
    home = '$base/home';
    userHome = '$base/uh';
    Directory(home).createSync();
    Directory(userHome).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  CoreConfig config({
    List<String> trusted = const [],
    SkillsConfig skills = const SkillsConfig(),
  }) => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
    trustedProjects: trusted,
    skills: skills,
  );

  Map<String, String> env() => {'CODELAB_HOME': home, 'HOME': userHome};

  Future<ProjectExtensions> load(
    String cwd,
    CoreConfig cfg, {
    ProjectFilesSource? projectFiles,
    SkillFilesSource? skillFiles,
    Duration timeout = const Duration(seconds: 5),
  }) => loadProjectExtensions(
    cwd: cwd,
    config: cfg,
    environment: env(),
    projectFiles: projectFiles,
    skillFiles: skillFiles,
    timeout: timeout,
  );

  group('canonical cwd and trust (D3, fail-closed)', () {
    test('a symlinked cwd is resolved and compared with trusted_projects by '
        'the canonical path', () async {
      final real = '$base/real';
      Directory(real).createSync();
      Link('$base/link').createSync(real);
      final project = _FakeProject();
      final skills = _FakeSkills();

      final result = await load(
        '$base/link',
        config(trusted: [real]),
        projectFiles: project,
        skillFiles: skills,
      );

      expect(result.cwd, real);
      expect(result.trusted, isTrue);
      // Оба порта получают канонический cwd и то же решение о доверии.
      expect(project.query?.cwd, real);
      expect(project.query?.projectTrusted, isTrue);
      expect(skills.query?.cwd, real);
      expect(skills.query?.projectTrusted, isTrue);
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test('a folder that is not in trusted_projects is untrusted', () async {
      Directory('$base/proj').createSync();
      final project = _FakeProject();
      final skills = _FakeSkills();

      final result = await load(
        '$base/proj',
        config(trusted: ['$base/other']),
        projectFiles: project,
        skillFiles: skills,
      );

      expect(result.trusted, isFalse);
      expect(project.query?.projectTrusted, isFalse);
      expect(skills.query?.projectTrusted, isFalse);
    });

    test('without realpath (the folder does not exist) the project is '
        'untrusted even if trusted_projects names this very path', () async {
      final missing = '$base/missing';
      final project = _FakeProject();

      final result = await load(
        missing,
        config(trusted: [missing]),
        projectFiles: project,
        skillFiles: _FakeSkills(),
      );

      expect(result.trusted, isFalse);
      expect(project.query?.projectTrusted, isFalse);
      // При Err realpath остаётся путь, как его задал пользователь.
      expect(result.cwd, missing);
    });

    test('codelabHome comes from the environment of the agent', () async {
      Directory('$base/proj').createSync();

      final result = await load(
        '$base/proj',
        config(),
        projectFiles: _FakeProject(),
        skillFiles: _FakeSkills(),
      );

      expect(result.codelabHome, home);
    });
  });

  group('two phases in parallel, each with its own timeout (D3)', () {
    test('both phases start before either of them finishes', () async {
      Directory('$base/proj').createSync();
      final projectStarted = Completer<void>();
      final skillsStarted = Completer<void>();
      // Каждая фаза ждёт старта другой: при последовательном запуске первая
      // не дождалась бы и ушла в таймаут, а не в `PhaseLoaded`.
      final project = _FakeProject(
        onLoad: () async {
          projectStarted.complete();
          await skillsStarted.future;
          return ProjectFiles.empty;
        },
      );
      final skills = _FakeSkills(
        onLoad: () async {
          skillsStarted.complete();
          await projectStarted.future;
          return SkillFiles.empty;
        },
      );

      final result = await load(
        '$base/proj',
        config(),
        projectFiles: project,
        skillFiles: skills,
        timeout: const Duration(seconds: 2),
      );

      expect(result.projectFiles, isA<PhaseLoaded<ProjectFiles>>());
      expect(result.skills, isA<PhaseLoaded<SkillFiles>>());
    });

    test('a skills phase that never answers: PhaseTimedOut, its load is '
        'cancelled, the project phase is untouched', () async {
      Directory('$base/proj').createSync();
      final project = _FakeProject(
        onLoad: () async => ProjectFiles(
          context: [ContextFile(path: 'AGENTS.md', content: 'rule')],
        ),
      );
      final skills = _FakeSkills(onLoad: () => Completer<SkillFiles>().future);

      final result = await load(
        '$base/proj',
        config(),
        projectFiles: project,
        skillFiles: skills,
        timeout: const Duration(milliseconds: 20),
      );

      expect(result.skills, isA<PhaseTimedOut>());
      expect(skills.query?.cancel.isCancelled, isTrue);
      final loaded = result.projectFiles as PhaseLoaded<ProjectFiles>;
      expect(loaded.value.context.single.path, 'AGENTS.md');
    });

    test('skillsTimeout bounds only the skills phase: a short skills limit '
        'wins over a long common one', () async {
      Directory('$base/proj').createSync();
      final skills = _FakeSkills(onLoad: () => Completer<SkillFiles>().future);

      // Общий предел 30 с, у навыков 20 мс: без отдельного предела тест
      // упёрся бы во внешние 2 с.
      final result = await loadProjectExtensions(
        cwd: '$base/proj',
        config: config(),
        environment: env(),
        projectFiles: _FakeProject(),
        skillFiles: skills,
        timeout: const Duration(seconds: 30),
        skillsTimeout: const Duration(milliseconds: 20),
      ).timeout(const Duration(seconds: 2));

      expect(result.skills, isA<PhaseTimedOut>());
      expect(skills.query?.cancel.isCancelled, isTrue);
      expect(result.projectFiles, isA<PhaseLoaded<ProjectFiles>>());
    });

    test('a project-files phase that never answers: PhaseTimedOut, the '
        'skills phase is untouched', () async {
      Directory('$base/proj').createSync();
      final project = _FakeProject(
        onLoad: () => Completer<ProjectFiles>().future,
      );

      final result = await load(
        '$base/proj',
        config(),
        projectFiles: project,
        skillFiles: _FakeSkills(),
        timeout: const Duration(milliseconds: 20),
      );

      expect(result.projectFiles, isA<PhaseTimedOut>());
      expect(project.query?.cancel.isCancelled, isTrue);
      expect(result.skills, isA<PhaseLoaded<SkillFiles>>());
    });
  });

  group('an exception of a port is a value, not an exception (D3)', () {
    test('PhaseFailed carries the type name only, never the text', () async {
      Directory('$base/proj').createSync();
      final skills = _FakeSkills(
        onLoad: () => Future.error(StateError('secret detail sk-test-leak')),
      );

      final result = await load(
        '$base/proj',
        config(),
        projectFiles: _FakeProject(),
        skillFiles: skills,
      );

      final failed = result.skills as PhaseFailed;
      expect(failed.errorType, 'StateError');
      expect(failed.toString(), isNot(contains('secret detail')));
      expect(failed.toString(), isNot(contains('sk-test-leak')));
      expect(result.projectFiles, isA<PhaseLoaded<ProjectFiles>>());
    });

    test(
      'a failed project-files phase does not touch the skills phase',
      () async {
        Directory('$base/proj').createSync();

        final result = await load(
          '$base/proj',
          config(),
          projectFiles: _FakeProject(
            onLoad: () => Future.error(ArgumentError()),
          ),
          skillFiles: _FakeSkills(),
        );

        expect((result.projectFiles as PhaseFailed).errorType, 'ArgumentError');
        expect(result.skills, isA<PhaseLoaded<SkillFiles>>());
      },
    );
  });

  group('skills.enabled: false (D3)', () {
    test('the skills phase is not started and skills is null', () async {
      Directory('$base/proj').createSync();
      final skills = _FakeSkills();

      final result = await load(
        '$base/proj',
        config(skills: const SkillsConfig(enabled: false)),
        projectFiles: _FakeProject(),
        skillFiles: skills,
      );

      expect(result.skills, isNull);
      expect(skills.query, isNull);
      expect(result.projectFiles, isA<PhaseLoaded<ProjectFiles>>());
    });
  });

  group('contextRoot and skillRoots equal what the loader reads '
      '(D3, D10 add-agent-skills)', () {
    late String repo;
    late String pkg;

    setUp(() {
      repo = '$base/repo';
      pkg = '$repo/pkg';
      Directory('$repo/.git').createSync(recursive: true);
      Directory(pkg).createSync();
    });

    test('a trusted project: levels from cwd up, then the user roots, then '
        'extra_roots as written', () async {
      final result = await load(
        pkg,
        config(
          trusted: [pkg],
          skills: const SkillsConfig(
            extraRoots: ['.claude/skills', '~/shared', '/abs/skills'],
          ),
        ),
      );

      expect(result.cwd, pkg);
      expect(result.contextRoot, repo);
      expect(
        [for (final r in result.skillRoots) (r.scope, r.path, r.extraRoot)],
        [
          (ExtensionScope.project, '$pkg/.codelab/skills', null),
          (ExtensionScope.project, '$pkg/.agents/skills', null),
          (ExtensionScope.project, '$repo/.codelab/skills', null),
          (ExtensionScope.project, '$repo/.agents/skills', null),
          (ExtensionScope.user, '$home/skills', null),
          (ExtensionScope.user, '$userHome/.agents/skills', null),
          // Элемент как записан в конфиге; `~` раскрыт `userHomeOf`.
          (ExtensionScope.extra, '$pkg/.claude/skills', '.claude/skills'),
          (ExtensionScope.extra, '$userHome/shared', '~/shared'),
          (ExtensionScope.extra, '/abs/skills', '/abs/skills'),
        ],
      );
    });

    test('an untrusted project: project roots and a relative extra root get '
        'no number, as in the loader', () async {
      final result = await load(
        pkg,
        config(
          skills: const SkillsConfig(
            extraRoots: ['.claude/skills', '~/shared'],
          ),
        ),
      );

      expect(result.trusted, isFalse);
      expect(
        [for (final r in result.skillRoots) (r.scope, r.path, r.extraRoot)],
        [
          (ExtensionScope.user, '$home/skills', null),
          (ExtensionScope.user, '$userHome/.agents/skills', null),
          (ExtensionScope.extra, '$userHome/shared', '~/shared'),
        ],
      );
    });

    test('rootIndex of every loaded skill points at the root that holds '
        'its directory', () async {
      write(
        '$pkg/.codelab/skills/a/SKILL.md',
        '---\nname: a\ndescription: A\n---\nBody\n',
      );
      write(
        '$repo/.agents/skills/b/SKILL.md',
        '---\nname: b\ndescription: B\n---\nBody\n',
      );
      write(
        '$userHome/.agents/skills/c/SKILL.md',
        '---\nname: c\ndescription: C\n---\nBody\n',
      );
      write(
        '$userHome/shared/d/SKILL.md',
        '---\nname: d\ndescription: D\n---\nBody\n',
      );

      final result = await load(
        pkg,
        config(
          trusted: [pkg],
          skills: const SkillsConfig(extraRoots: ['~/shared']),
        ),
      );

      final files = (result.skills as PhaseLoaded<SkillFiles>).value;
      expect(files.skills.map((s) => s.dir.split('/').last), [
        'a',
        'b',
        'c',
        'd',
      ]);
      for (final skill in files.skills) {
        final holder = result.skillRoots[skill.rootIndex];
        expect(
          skill.dir.substring(0, skill.dir.lastIndexOf('/')),
          holder.path,
          reason: skill.dir,
        );
        expect(skill.scope, holder.scope, reason: skill.dir);
      }
    });

    test('a folder without a repository: contextRoot is cwd', () async {
      Directory('$base/plain').createSync();

      final result = await load(
        '$base/plain',
        config(trusted: ['$base/plain']),
      );

      expect(result.contextRoot, '$base/plain');
    });
  });
}

/// Порт файлов проекта: запоминает запрос, ответ задаёт тест.
final class _FakeProject implements ProjectFilesSource {
  _FakeProject({this.onLoad});

  final Future<ProjectFiles> Function()? onLoad;
  ProjectFilesQuery? query;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) {
    this.query = query;
    return onLoad?.call() ?? Future.value(ProjectFiles.empty);
  }
}

/// Порт навыков: запоминает запрос, ответ задаёт тест.
final class _FakeSkills implements SkillFilesSource {
  _FakeSkills({this.onLoad});

  final Future<SkillFiles> Function()? onLoad;
  SkillFilesQuery? query;

  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) {
    this.query = query;
    return onLoad?.call() ?? Future.value(SkillFiles.empty);
  }
}
