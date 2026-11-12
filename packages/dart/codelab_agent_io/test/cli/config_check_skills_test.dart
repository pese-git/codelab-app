import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `config check` и навыки (agent-configuration «config check показывает
/// диагностику файлов проекта», сценарий «Битый навык», строки `note:` для
/// корней навыков проекта, предупреждения `shadowed` и `yaml_repaired`,
/// отдельные строки таймаута и сбоя фазы навыков; design.md change
/// `add-agent-skills`, D1, D13).
///
/// Вывод общий у `codelab-agent config check` и `codelab config check`: оба
/// вызывают `ConfigCommands.check`, поэтому проверяется он (`codelab` берёт
/// его через `codelab_setup`).
///
/// Фиксируемый API: тестовые параметры `ConfigCommands(skillFiles:,
/// skillFilesTimeout:)` (по образцу `projectFiles`/`projectFilesTimeout`);
/// без подмены `check` использует `ProjectFilesLoader` (он же
/// `SkillFilesSource`) с `userHome` из `HOME`.
void main() {
  late Directory root;
  late String home;
  late String userHome;
  late String cwd;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  const providers = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

  setUp(() {
    final created = Directory.systemTemp.createTempSync('config_check_skills_');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    userHome = '${root.path}/uh';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(userHome).createSync();
    Directory(cwd).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  void validConfig({bool trusted = false, String extra = ''}) => write(
    '$home/config.yaml',
    '$providers${trusted ? 'trusted_projects:\n  - $cwd\n' : ''}$extra',
  );

  Future<ConfigCommandResult> check({ConfigCommands? commands}) async =>
      (commands ?? ConfigCommands()).check(
        CheckOptions(
          cwd: cwd,
          environment: {'CODELAB_HOME': home, 'HOME': userHome},
        ),
      );

  List<String> warnings(ConfigCommandResult r) => [
    for (final l in r.stdout)
      if (l.startsWith('warning: ')) l,
  ];

  List<String> notes(ConfigCommandResult r) => [
    for (final l in r.stdout)
      if (l.startsWith('note: ')) l,
  ];

  group('diagnostics of skill files', () {
    test('scenario "Битый навык": a warning with the path of SKILL.md and '
        'a fixed text, Config: valid, code 0', () async {
      validConfig();
      write(
        '$home/skills/notes/SKILL.md',
        '---\nname: Notes\ndescription: Takes notes\n---\nsecret body '
            'sk-test-secret\n',
      );

      final result = await check();

      expect(result.exitCode, 0, reason: result.stdout.join('\n'));
      final lines = warnings(result);
      expect(lines, isNotEmpty);
      expect(
        lines,
        everyElement(startsWith('warning: $home/skills/notes/SKILL.md:')),
      );
      // Позиция ключа `name` — строка 2.
      expect(
        lines,
        contains(startsWith('warning: $home/skills/notes/SKILL.md:2:')),
      );
      expect(result.stdout.join('\n'), isNot(contains('sk-test-secret')));
      expect(result.stdout.last, 'Config: valid');
      expect(result.stderr, isEmpty);
    });

    test('the user home of the process (userHomeOf: HOME) is the root of '
        '~/.agents/skills', () async {
      validConfig();
      write(
        '$userHome/.agents/skills/shared/SKILL.md',
        '---\nname: Shared\ndescription: D\n---\nBody\n',
      );

      final result = await check();

      expect(
        warnings(result),
        everyElement(
          startsWith('warning: $userHome/.agents/skills/shared/SKILL.md:'),
        ),
      );
      expect(warnings(result), isNotEmpty);
    });

    test('lines of project files come before the lines of skills', () async {
      validConfig(trusted: true);
      write(
        '$cwd/.codelab/agents/reviewer.md',
        '---\nname: reviewer\ndescription: Reviews\ncolor: red\n---\nB\n',
      );
      write(
        '$home/skills/notes/SKILL.md',
        '---\nname: Notes\ndescription: D\n---\nBody\n',
      );

      final lines = warnings(await check());

      final agent = lines.indexWhere((l) => l.contains('reviewer.md'));
      final skill = lines.indexWhere((l) => l.contains('skills/notes'));
      expect(agent, isNonNegative);
      expect(skill, greaterThan(agent));
    });

    test('yaml_repaired is a warning line', () async {
      validConfig();
      write(
        '$home/skills/pdf/SKILL.md',
        '---\nname: pdf\ndescription: Use when: PDFs\n---\nBody\n',
      );

      final result = await check();

      expect(result.exitCode, 0);
      expect(warnings(result), hasLength(1));
      expect(
        warnings(result).single,
        startsWith('warning: $home/skills/pdf/SKILL.md'),
      );
      expect(result.stdout.last, 'Config: valid');
    });

    test(
      'shadowed is a warning line with the path of the shadowed skill',
      () async {
        validConfig(trusted: true);
        write(
          '$cwd/.codelab/skills/release/SKILL.md',
          '---\nname: release\ndescription: Project\n---\nB\n',
        );
        write(
          '$home/skills/release/SKILL.md',
          '---\nname: release\ndescription: User\n---\nB\n',
        );

        final result = await check();

        expect(result.exitCode, 0);
        expect(
          warnings(result).single,
          startsWith('warning: $home/skills/release'),
        );
      },
    );

    test('an unreadable YAML is a warning line, the check goes on', () async {
      validConfig();
      write(
        '$home/skills/broken/SKILL.md',
        '---\nname: broken\ntags: [a, b\n---\nBody\n',
      );

      final result = await check();

      expect(result.exitCode, 0);
      expect(
        warnings(result).single,
        startsWith('warning: $home/skills/broken/SKILL.md:'),
      );
      expect(result.stdout.last, 'Config: valid');
    });

    test('a skill without problems and other info diagnostics print '
        'nothing', () async {
      validConfig(extra: 'skills:\n  disabled: [off]\n');
      write(
        '$home/skills/fine/SKILL.md',
        '---\nname: fine\ndescription: Fine\n---\nBody\n',
      );
      write(
        '$home/skills/off/SKILL.md',
        '---\nname: off\ndescription: Off\n---\nBody\n',
      );
      write(
        '$home/skills/ops/SKILL.md',
        '---\nname: ops\ndescription: Ops\nmetadata:\n'
            '  codelab-operative: Keep it short.\n---\nBody\n',
      );

      final result = await check();

      expect(warnings(result), isEmpty);
      expect(notes(result), isEmpty);
      expect(result.stdout.last, 'Config: valid');
    });

    test('skills.enabled: false: skill files are not checked', () async {
      validConfig(extra: 'skills:\n  enabled: false\n');
      write('$home/skills/notes/SKILL.md', '---\nname: Notes\n---\nBody\n');

      final result = await check(
        commands: ConfigCommands(skillFiles: _ThrowingSkills()),
      );

      expect(warnings(result), isEmpty);
      expect(result.stdout.last, 'Config: valid');
    });

    test('an invalid config: skills are not checked at all', () async {
      write('$home/config.yaml', '${providers}budget:\n  max_steps: 0\n');
      final source = _CountingSkills();

      final result = await check(commands: ConfigCommands(skillFiles: source));

      expect(result.exitCode, 1);
      expect(source.calls, 0);
    });
  });

  group('note: lines for project skill roots', () {
    test('an untrusted project: one note per existing root, other info '
        'is silent', () async {
      validConfig();
      Directory('$cwd/.codelab/skills/review').createSync(recursive: true);
      Directory('$cwd/.agents/skills/pdf').createSync(recursive: true);

      final result = await check();

      expect(notes(result), [
        'note: $cwd/.codelab/skills: the project is not trusted; add it to '
            'trusted_projects',
        'note: $cwd/.agents/skills: the project is not trusted; add it to '
            'trusted_projects',
      ]);
      expect(warnings(result), isEmpty);
      expect(result.exitCode, 0);
      expect(result.stdout.last, 'Config: valid');
    });

    test(
      'with prompts, agents and skills the notes are one per directory',
      () async {
        validConfig();
        Directory('$cwd/.codelab/prompts').createSync(recursive: true);
        Directory('$cwd/.codelab/agents').createSync(recursive: true);
        Directory('$cwd/.codelab/skills').createSync(recursive: true);

        final result = await check();

        expect(
          [for (final n in notes(result)) n.split(':')[1].trim()],
          unorderedEquals([
            '$cwd/.codelab/prompts',
            '$cwd/.codelab/agents',
            '$cwd/.codelab/skills',
          ]),
        );
      },
    );

    test('a trusted project: no notes', () async {
      validConfig(trusted: true);
      Directory('$cwd/.codelab/skills/review').createSync(recursive: true);

      final result = await check();

      expect(notes(result), isEmpty);
    });

    test('a relative skills.extra_roots in an untrusted project is a '
        'warning, not a note', () async {
      validConfig(extra: 'skills:\n  extra_roots: [".claude/skills"]\n');
      Directory('$cwd/.claude/skills/lint').createSync(recursive: true);

      final result = await check();

      expect(notes(result), isEmpty);
      final line = warnings(result).single;
      expect(line, contains('.claude/skills'));
      expect(result.exitCode, 0);
      expect(result.stdout.last, 'Config: valid');
    });
  });

  group('failures of the skills phase', () {
    const badAgent =
        '---\nname: reviewer\ndescription: Reviews\ncolor: red\n---\nBody\n';

    test('a throwing skills source: its own line, the project files are '
        'printed as usual, code 0', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/agents/reviewer.md', badAgent);

      final result = await check(
        commands: ConfigCommands(skillFiles: _ThrowingSkills()),
      );

      expect(result.exitCode, 0);
      final lines = warnings(result);
      expect(
        lines,
        contains('warning: $cwd: skills could not be read: StateError'),
      );
      expect(
        lines,
        contains(startsWith('warning: $cwd/.codelab/agents/reviewer.md:4:1:')),
      );
      expect(lines.any((l) => l.contains('project files could not')), isFalse);
      expect(result.stdout.join('\n'), isNot(contains('secret detail')));
      expect(result.stdout.last, 'Config: valid');
      expect(result.stderr, isEmpty);
    });

    test('a skills source that never answers: a timeout line, the load is '
        'cancelled, code 0', () async {
      validConfig(trusted: true);
      write('$cwd/.codelab/agents/reviewer.md', badAgent);
      final source = _HangingSkills();

      final result = await check(
        commands: ConfigCommands(
          skillFiles: source,
          skillFilesTimeout: const Duration(milliseconds: 20),
        ),
      );

      expect(result.exitCode, 0);
      final lines = warnings(result);
      expect(lines, contains('warning: $cwd: skills were not read within 0 s'));
      expect(
        lines,
        contains(startsWith('warning: $cwd/.codelab/agents/reviewer.md:4:1:')),
      );
      expect(source.cancel?.isCancelled, isTrue);
      expect(result.stdout.last, 'Config: valid');
    });

    test('and the other way round: project files fail, skill diagnostics '
        'are printed as usual', () async {
      validConfig();
      write(
        '$home/skills/notes/SKILL.md',
        '---\nname: Notes\ndescription: Notes\n---\nBody\n',
      );

      final result = await check(
        commands: ConfigCommands(projectFiles: _ThrowingProject()),
      );

      expect(result.exitCode, 0);
      final lines = warnings(result);
      expect(
        lines,
        contains('warning: $cwd: project files could not be read: StateError'),
      );
      expect(
        lines,
        contains(startsWith('warning: $home/skills/notes/SKILL.md:')),
      );
      expect(lines.any((l) => l.contains('skills could not be read')), isFalse);
      expect(result.stdout.last, 'Config: valid');
    });

    test('the failure of a phase is not a config problem: the output '
        'differs from the clean one only by its line', () async {
      validConfig();

      final clean = await check();
      final failed = await check(
        commands: ConfigCommands(skillFiles: _ThrowingSkills()),
      );

      expect(failed.exitCode, clean.exitCode);
      expect(failed.stdout.last, clean.stdout.last);
      expect(
        failed.stdout.where((l) => !l.startsWith('warning: $cwd: skills')),
        clean.stdout,
      );
    });
  });
}

/// Источник навыков, который бросает непредвиденное исключение.
final class _ThrowingSkills implements SkillFilesSource {
  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) =>
      Future.error(StateError('secret detail'));
}

/// Источник, не отвечающий никогда; запоминает токен отмены запроса.
final class _HangingSkills implements SkillFilesSource {
  CancelToken? cancel;

  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) {
    cancel = query.cancel;
    return Completer<SkillFiles>().future;
  }
}

/// Источник, считающий обращения.
final class _CountingSkills implements SkillFilesSource {
  int calls = 0;

  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) async {
    calls++;
    return const SkillFiles(skills: []);
  }
}

/// Источник файлов проекта, который бросает непредвиденное исключение.
final class _ThrowingProject implements ProjectFilesSource {
  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) =>
      Future.error(StateError('secret detail'));
}
