import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Сбой подготовки в `loadProjectExtensions` и `config check` (ревью
/// итерации 1: «config check при сбое подготовки — одна строка», «защита
/// разбора»; design.md change `add-app-skills-page`, D3).
///
/// Почему отдельно: до выделения расчёта непредвиденное исключение подготовки
/// (`CODELAB_HOME` вида `~user`) и исключение разбора давали одну строку
/// `warning:` с типом, а не падение `check`. Тот же `check` не может довести
/// до подготовки неверное окружение (конфиг уже загружен), поэтому путь
/// проверяется швом `ConfigCommands(extensionsLoader:)`.
void main() {
  late Directory root;
  late String home;
  late String cwd;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    final created = Directory.systemTemp.createTempSync('ext_failure_');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    write('$home/config.yaml', '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
trusted_projects:
  - $cwd
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  CoreConfig config() => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
  );

  Future<ConfigCommandResult> check(ConfigCommands commands) => commands.check(
    CheckOptions(
      cwd: cwd,
      environment: {'CODELAB_HOME': home, 'HOME': '${root.path}/uh'},
    ),
  );

  List<String> warnings(ConfigCommandResult r) => [
    for (final l in r.stdout)
      if (l.startsWith('warning: ')) l,
  ];

  group('a failed preparation is explicit', () {
    test('loadProjectExtensions: preparationError names the type, both '
        'phases are PhaseFailed with it', () async {
      final result = await loadProjectExtensions(
        cwd: cwd,
        config: config(),
        environment: {'CODELAB_HOME': '~bob/x', 'HOME': root.path},
      );

      expect(result.preparationError, 'ConfigUsageException');
      expect(
        (result.projectFiles as PhaseFailed).errorType,
        'ConfigUsageException',
      );
      expect((result.skills as PhaseFailed).errorType, 'ConfigUsageException');
      expect(result.trusted, isFalse);
    });

    test('a failed preparation with skills.enabled: false keeps skills '
        'null: the phase was never meant to run', () async {
      final base = config();
      final disabled = CoreConfig(
        defaultModel: base.defaultModel,
        skills: const SkillsConfig(enabled: false),
      );

      final result = await loadProjectExtensions(
        cwd: cwd,
        config: disabled,
        environment: {'CODELAB_HOME': '~bob/x', 'HOME': root.path},
      );

      expect(result.skills, isNull);
      expect(result.projectFiles, isA<PhaseFailed>());
      expect(result.preparationError, isNotEmpty);
    });

    test('a normal load has no preparationError', () async {
      final result = await loadProjectExtensions(
        cwd: cwd,
        config: config(),
        environment: {'CODELAB_HOME': home, 'HOME': root.path},
        projectFiles: _EmptyProject(),
        skillFiles: _EmptySkills(),
      );

      expect(result.preparationError, isNull);
    });

    test('config check prints ONE line for a failed preparation, as before '
        'the extraction', () async {
      final commands = ConfigCommands(
        extensionsLoader:
            ({
              required cwd,
              required config,
              required environment,
              projectFiles,
              skillFiles,
              timeout = const Duration(seconds: 5),
              skillsTimeout,
            }) async => ProjectExtensions(
              cwd: cwd,
              trusted: false,
              contextRoot: cwd,
              codelabHome: null,
              projectFiles: const PhaseFailed('StateError'),
              skills: const PhaseFailed('StateError'),
              skillRoots: const [],
              preparationError: 'StateError',
            ),
      );

      final result = await check(commands);

      expect(result.exitCode, 0);
      expect(warnings(result), [
        'warning: $cwd: project files could not be read: StateError',
      ]);
      expect(result.stdout.last, 'Config: valid');
    });
  });

  group('a parser that throws does not crash config check', () {
    test('parseSkills: a warning with the type, code 0', () async {
      final commands = ConfigCommands(skillFiles: _PoisonedSkills());

      final result = await check(commands);

      expect(result.exitCode, 0);
      expect(
        warnings(result),
        contains('warning: $cwd: skills could not be read: StateError'),
      );
      expect(result.stdout.join('\n'), isNot(contains('poison')));
      expect(result.stdout.last, 'Config: valid');
    });

    test('parseCommandTemplates: a project-files warning with the type, '
        'skills lines unaffected', () async {
      final commands = ConfigCommands(projectFiles: _PoisonedTemplates());

      final result = await check(commands);

      expect(result.exitCode, 0);
      expect(
        warnings(result),
        contains('warning: $cwd: project files could not be read: StateError'),
      );
      expect(result.stdout.join('\n'), isNot(contains('poison')));
      expect(result.stdout.last, 'Config: valid');
    });
  });
}

/// Словарь, который бросает при чтении: так разбор падает, как у ошибки в
/// самом парсере.
final class _PoisonMap implements Map<String, Object?> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('poison');
}

final class _PoisonedSkills implements SkillFilesSource {
  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) async => SkillFiles(
    skills: [
      SkillFile(
        dir: '/x/skills/a',
        scope: ExtensionScope.user,
        rootIndex: 0,
        frontmatter: ConfigTree(
          kind: ConfigLayerKind.user,
          source: '/x/skills/a/SKILL.md',
          values: _PoisonMap(),
        ),
        body: 'b',
        bodyLine: 3,
      ),
    ],
  );
}

final class _PoisonedTemplates implements ProjectFilesSource {
  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async => ProjectFiles(
    templates: [
      MarkdownFile(
        path: '/x/prompts/review.md',
        scope: ExtensionScope.user,
        frontmatter: ConfigTree(
          kind: ConfigLayerKind.user,
          source: '/x/prompts/review.md',
          values: _PoisonMap(),
        ),
        body: 'b',
        bodyLine: 3,
      ),
    ],
  );
}

final class _EmptyProject implements ProjectFilesSource {
  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles.empty;
}

final class _EmptySkills implements SkillFilesSource {
  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) async =>
      SkillFiles.empty;
}
