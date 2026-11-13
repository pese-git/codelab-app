import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Загрузчик навыков `ProjectFilesLoader.loadSkills` на реальных файлах
/// (agent-skills «Корни навыков, приоритет и согласие», все сценарии;
/// «Сопутствующие файлы и скрипты навыка» — перечисление; agent-project-context
/// «Граница чтения файлов проекта», сценарий «Сопутствующий файл-ссылка
/// наружу»; design.md change `add-agent-skills`, D1, D3, D5).
///
/// Фиксируемый API: `ProjectFilesLoader(home:, userHome:, local:)` реализует
/// `SkillFilesSource.loadSkills(SkillFilesQuery(cwd:, projectTrusted:,
/// extraRoots:, cancel:))` -> `SkillFiles {skills, diagnostics}`; `SkillFile
/// {dir, scope, rootIndex, frontmatter, parseErrors, repaired, body,
/// companions, companionsTruncated}`. Настоящие `~/.codelab` и `~` не
/// читаются: `home` и `userHome` задаются явно.
void main() {
  late String base;
  late String repo;
  late String home;
  late String userHome;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('skill_files_load_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    home = '$base/home';
    userHome = '$base/uh';
    Directory('$repo/.git').createSync(recursive: true);
    Directory(home).createSync();
    Directory(userHome).createSync();
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  void writeBytes(String path, List<int> bytes) => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(Uint8List.fromList(bytes));

  /// `<root>/<name>/SKILL.md` с минимальным frontmatter.
  void skill(
    String root,
    String name, {
    String? description,
    String body = 'Do it.\n',
    String? text,
  }) => write(
    '$root/$name/SKILL.md',
    text ??
        '---\nname: $name\ndescription: ${description ?? 'About $name'}\n---\n'
            '$body',
  );

  Future<SkillFiles> load({
    String? cwd,
    bool trusted = true,
    List<String> extra = const [],
    CancelToken? cancel,
    String? withHome,
    String? withUserHome,
    bool noHome = false,
  }) =>
      ProjectFilesLoader(
        home: noHome ? null : (withHome ?? home),
        userHome: noHome ? null : (withUserHome ?? userHome),
        local: LocalExecutionEnv(cwd: base),
      ).loadSkills(
        SkillFilesQuery(
          cwd: cwd ?? repo,
          projectTrusted: trusted,
          extraRoots: extra,
          cancel: cancel ?? CancelToken.none,
        ),
      );

  /// Сценарий перекрытия (Q39): загрузчик отдаёт оба навыка без диагностик,
  /// у победителя `rootIndex` меньше; `shadowed` выдаёт ядро (`parseSkills`)
  /// с путём `SKILL.md` проигравшего и путём победителя в тексте.
  void expectShadowing(
    SkillFiles files, {
    required String winner,
    required String loser,
  }) {
    expect(files.diagnostics, isEmpty);
    expect(files.skills, hasLength(2));
    expect(files.skills.first.dir, winner);
    expect(files.skills.last.dir, loser);
    expect(files.skills.first.rootIndex, lessThan(files.skills.last.rootIndex));
    final catalog = parseSkills(files, const SkillsConfig());
    expect(catalog.skills.single.dir, winner);
    final d = catalog.diagnostics.single;
    expect(d.code, 'shadowed');
    expect(d.level, DiagnosticLevel.warning);
    expect(d.path, '$loser/SKILL.md');
    expect(d.message, contains('$winner/SKILL.md'));
  }

  String nameOf(SkillFile f) => f.dir.split('/').last;
  List<String> names(SkillFiles f) => [for (final s in f.skills) nameOf(s)];
  List<String> codes(SkillFiles f) => [for (final d in f.diagnostics) d.code];
  List<ExtensionDiagnostic> withCode(SkillFiles f, String code) => [
    for (final d in f.diagnostics)
      if (d.code == code) d,
  ];

  group('trust of the project', () {
    test('scenario "Недоверенный проект": nothing is read, one '
        'untrusted_project info per existing root', () async {
      // Невалидный UTF-8: прочитай загрузчик файл, была бы `not_utf8`.
      writeBytes('$repo/.codelab/skills/review/SKILL.md', [0xff, 0xfe]);
      skill('$repo/.agents/skills', 'pdf');

      final files = await load(trusted: false);

      expect(files.skills, isEmpty);
      final d = files.diagnostics;
      expect(codes(files), ['untrusted_project', 'untrusted_project']);
      expect(d.map((x) => x.level), everyElement(DiagnosticLevel.info));
      expect(d.map((x) => x.path), [
        '$repo/.codelab/skills',
        '$repo/.agents/skills',
      ]);
    });

    test(
      'an untrusted project without skill directories: no diagnostic',
      () async {
        final files = await load(trusted: false);

        expect(files.skills, isEmpty);
        expect(files.diagnostics, isEmpty);
      },
    );

    test('an untrusted project does not hide the user roots', () async {
      skill('$home/skills', 'notes');
      skill('$repo/.codelab/skills', 'review');

      final files = await load(trusted: false);

      expect(names(files), ['notes']);
      expect(files.skills.single.scope, ExtensionScope.user);
    });

    test('a relative extra root of an untrusted project: warning '
        'untrusted_project, not read; an absolute one is read', () async {
      skill('$repo/.claude/skills', 'lint');
      skill('$base/shared', 'global');

      final files = await load(
        trusted: false,
        extra: ['.claude/skills', '$base/shared'],
      );

      expect(names(files), ['global']);
      final d = withCode(files, 'untrusted_project').single;
      expect(d.level, DiagnosticLevel.warning);
    });
  });

  group('roots and scopes', () {
    test('scenario ".agents/skills без отдельного согласия": project and '
        'user roots', () async {
      skill('$repo/.agents/skills', 'pdf');
      skill('$userHome/.agents/skills', 'notes');

      final files = await load();

      expect(files.diagnostics, isEmpty);
      final byName = {for (final s in files.skills) nameOf(s): s};
      expect(byName['pdf']!.scope, ExtensionScope.project);
      expect(byName['pdf']!.dir, '$repo/.agents/skills/pdf');
      expect(byName['notes']!.scope, ExtensionScope.user);
      expect(byName['notes']!.dir, '$userHome/.agents/skills/notes');
    });

    test(
      'the user roots are \$CODELAB_HOME/skills and ~/.agents/skills',
      () async {
        skill('$home/skills', 'a');
        skill('$userHome/.agents/skills', 'b');
        skill('$userHome/.codex/skills', 'codex');

        final files = await load();

        expect(names(files), ['a', 'b']);
        expect(
          files.skills.map((s) => s.scope),
          everyElement(ExtensionScope.user),
        );
      },
    );

    test('home: null and userHome: null switch the user area off '
        '(--llm-script)', () async {
      skill('$home/skills', 'a');
      skill('$userHome/.agents/skills', 'b');

      final files = await load(noHome: true);

      expect(files.skills, isEmpty);
    });

    test('scenario ".claude/skills только с согласия": absent without '
        'extra_roots, loaded with it (scope extra)', () async {
      skill('$repo/.claude/skills', 'lint');

      final without = await load();
      final withRoot = await load(extra: ['.claude/skills']);

      expect(without.skills, isEmpty);
      expect(without.diagnostics, isEmpty);
      final s = withRoot.skills.single;
      expect(nameOf(s), 'lint');
      expect(s.scope, ExtensionScope.extra);
      expect(s.dir, '$repo/.claude/skills/lint');
    });

    test('an absolute extra root is read as it is', () async {
      skill('$base/elsewhere', 'abs');

      final files = await load(extra: ['$base/elsewhere']);

      expect(names(files), ['abs']);
      expect(files.skills.single.scope, ExtensionScope.extra);
    });

    test('Q31: extra roots come below the project and user roots, in '
        'config order', () async {
      skill('$base/x1', 'one');
      skill('$base/x2', 'two');
      skill('$repo/.codelab/skills', 'proj');
      skill('$home/skills', 'usr');

      final files = await load(extra: ['$base/x1', '.claude/none', '$base/x2']);

      final order = [for (final s in files.skills) s.rootIndex];
      expect(order, orderedEquals([...order]..sort()));
      expect(names(files), ['proj', 'usr', 'one', 'two']);
    });

    test('Q31/Q39: a shadowed name goes to the higher root: a project skill '
        'wins over an extra root', () async {
      skill('$base/x1', 'same');
      skill('$repo/.codelab/skills', 'same');

      final files = await load(extra: ['$base/x1']);

      expectShadowing(
        files,
        winner: '$repo/.codelab/skills/same',
        loser: '$base/x1/same',
      );
    });

    test('a skills root that does not exist is silent', () async {
      final files = await load(extra: ['$base/missing']);

      expect(files.skills, isEmpty);
      expect(files.diagnostics, isEmpty);
    });
  });

  group('rootIndex and ~ in extra_roots (D16, Q41)', () {
    test('every root of the list has a number, whether the directory '
        'exists or not', () async {
      skill('$home/skills', 'h');
      skill('$userHome/.agents/skills', 'u');
      skill('$base/x2', 'e2');

      // cwd = корень git: уровень проекта один, корней проекта два.
      final files = await load(extra: ['$base/missing', '$base/x2']);

      final byName = {for (final f in files.skills) nameOf(f): f.rootIndex};
      expect(byName, {'h': 2, 'u': 3, 'e2': 5});
    });

    test('~/dir and ~ are expanded to userHome and count as absolute, '
        'also for an untrusted project', () async {
      skill('$userHome/shared', 'one');
      skill(userHome, 'two');

      final files = await load(trusted: false, extra: ['~/shared', '~']);

      expect(names(files)..sort(), ['one', 'two']);
      expect(
        files.skills.every((f) => f.scope == ExtensionScope.extra),
        isTrue,
      );
      expect(files.diagnostics, isEmpty);
    });

    test('without userHome (--llm-script) an element with ~ is not read: '
        'warning unresolved_root with the element', () async {
      skill('$userHome/shared', 'one');
      skill('$base/abs', 'two');

      final files = await load(noHome: true, extra: ['~/shared', '$base/abs']);

      expect(names(files), ['two']);
      final d = withCode(files, 'unresolved_root').single;
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, '~/shared');
      expect(
        d.message,
        'the skills root starts with ~ but the home directory is unknown; it '
        'is not read',
      );
    });
  });

  group('the root is bounded by its level (Q42)', () {
    test('.agents/skills as a symlink out of the project: outside_root, '
        'nothing is loaded', () async {
      skill('$base/outside', 'evil');
      Link('$repo/.agents/skills').createSync('$base/outside', recursive: true);

      final files = await load();

      expect(files.skills, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, '$repo/.agents/skills');
      expect(
        d.message,
        'the skills root resolves outside its area; its skills are not read',
      );
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test(
      '.codelab/skills as a symlink out of the project: outside_root',
      () async {
        skill('$base/outside', 'evil');
        Link(
          '$repo/.codelab/skills',
        ).createSync('$base/outside', recursive: true);

        final files = await load();

        expect(files.skills, isEmpty);
        expect(codes(files), ['outside_root']);
      },
      skip: Platform.isWindows ? 'symlink needs privileges' : false,
    );

    test(
      '\$CODELAB_HOME/skills as a symlink out of home: outside_root',
      () async {
        skill('$base/outside', 'evil');
        Link('$home/skills').createSync('$base/outside');

        final files = await load();

        expect(files.skills, isEmpty);
        expect(codes(files), ['outside_root']);
      },
      skip: Platform.isWindows ? 'symlink needs privileges' : false,
    );

    test('the same directory through extra_roots is loaded (consent); '
        '~/.agents/skills is not bounded either', () async {
      skill('$base/outside', 'evil');
      Link('$repo/.agents/skills').createSync('$base/outside', recursive: true);
      Link('$userHome/.agents').createSync('$base/outside-agents');
      skill('$base/outside-agents/skills', 'viaUser');

      final files = await load(extra: ['$base/outside']);

      expect(names(files)..sort(), ['evil', 'viaUser']);
      expect(codes(files), ['outside_root']);
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test('a symlinked root that stays inside its level is read', () async {
      skill('$repo/shared', 'ok');
      Link('$repo/.agents/skills').createSync('$repo/shared', recursive: true);

      final files = await load();

      expect(names(files), ['ok']);
      expect(files.diagnostics, isEmpty);
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test(
      'an extra root is the user\'s consent: a symlink out is followed',
      () async {
        skill('$base/outside', 'ext');
        Link('$base/link').createSync('$base/outside');

        final files = await load(extra: ['$base/link']);

        expect(names(files), ['ext']);
      },
      skip: Platform.isWindows ? 'symlink needs privileges' : false,
    );
  });

  group('one directory reached through two roots', () {
    test('cwd = ~: ~/.codelab/skills equals \$CODELAB_HOME/skills, the '
        'directory is loaded once, without shadowed', () async {
      final h = '$userHome/.codelab';
      skill('$h/skills', 'same');

      final files = await load(
        cwd: userHome,
        withHome: h,
        withUserHome: userHome,
      );

      expect(files.skills, hasLength(1));
      expect(files.diagnostics, isEmpty);
      final catalog = parseSkills(files, const SkillsConfig());
      expect(catalog.diagnostics, isEmpty);
    });
  });

  group('levels from cwd to the git root', () {
    late String pkg;
    setUp(() {
      pkg = '$repo/pkg';
      Directory(pkg).createSync();
    });

    test('scenario "Ближний уровень проекта перекрывает дальний"', () async {
      skill('$repo/.codelab/skills', 'release');
      skill('$pkg/.agents/skills', 'release');

      final files = await load(cwd: pkg);

      expectShadowing(
        files,
        winner: '$pkg/.agents/skills/release',
        loser: '$repo/.codelab/skills/release',
      );
    });

    test('skills of every level up to the git root are found', () async {
      skill('$repo/.codelab/skills', 'top');
      skill('$pkg/.codelab/skills', 'near');

      final files = await load(cwd: pkg);

      expect(names(files)..sort(), ['near', 'top']);
    });

    test('inside a level .codelab/skills goes before .agents/skills; the '
        'second same name is shadowed', () async {
      skill('$repo/.agents/skills', 'dup');
      skill('$repo/.codelab/skills', 'dup');

      final files = await load();

      expectShadowing(
        files,
        winner: '$repo/.codelab/skills/dup',
        loser: '$repo/.agents/skills/dup',
      );
    });

    test('without a git repository only cwd is a level', () async {
      final plain = '$base/plain';
      skill('$plain/.codelab/skills', 'here');
      skill('$base/.codelab/skills', 'above');
      Directory('$plain/sub').createSync();
      skill('$plain/sub/.codelab/skills', 'sub');

      final files = await load(cwd: '$plain/sub');

      expect(names(files), ['sub']);
    });

    test('64 levels above cwd: the search stops with limit_exceeded; 63 '
        'levels still reach the root', () async {
      skill('$repo/.codelab/skills', 'far');
      var far = repo;
      for (var i = 0; i < 64; i++) {
        far = '$far/d';
      }
      Directory(far).createSync(recursive: true);
      skill('$far/.codelab/skills', 'own');
      var near = repo;
      for (var i = 0; i < 63; i++) {
        near = '$near/d';
      }

      final deep = await load(cwd: far);
      final reachable = await load(cwd: near);

      expect(names(deep), ['own']);
      expect(codes(deep), contains('limit_exceeded'));
      expect(
        withCode(deep, 'limit_exceeded').single.level,
        DiagnosticLevel.info,
      );
      expect(names(reachable), ['far']);
      expect(withCode(reachable, 'limit_exceeded'), isEmpty);
    });
  });

  group('shadowing between scopes', () {
    test(
      'scenario "Проект перекрывает пользователя с предупреждением"',
      () async {
        skill('$repo/.codelab/skills', 'release-notes');
        skill('$home/skills', 'release-notes');

        final files = await load();

        expectShadowing(
          files,
          winner: '$repo/.codelab/skills/release-notes',
          loser: '$home/skills/release-notes',
        );
      },
    );

    test('\$CODELAB_HOME/skills goes before ~/.agents/skills', () async {
      skill('$userHome/.agents/skills', 'same');
      skill('$home/skills', 'same');

      final files = await load();

      expectShadowing(
        files,
        winner: '$home/skills/same',
        loser: '$userHome/.agents/skills/same',
      );
    });
  });

  group('what is skipped', () {
    test('scenario "Symlink каталога навыка наружу": outside_root with the '
        'path, the skill is absent', () async {
      skill('$base/outside', 'evil');
      Directory('$home/skills').createSync(recursive: true);
      Link('$home/skills/evil').createSync('$base/outside/evil');

      final files = await load();

      expect(files.skills, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.path, '$home/skills/evil');
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test(
      'a symlink to a directory inside the same root is not an escape',
      () async {
        skill('$home/skills', 'real');
        Link('$home/skills/alias').createSync('$home/skills/real');

        final files = await load();

        expect(withCode(files, 'outside_root'), isEmpty);
      },
      skip: Platform.isWindows ? 'symlink needs privileges' : false,
    );

    test('a file in the root, dot-directories, a SKILL.md straight in the '
        'root and directories without SKILL.md are silent', () async {
      final root = '$home/skills';
      write('$root/README.md', 'text');
      write('$root/SKILL.md', '---\nname: root\ndescription: D\n---\nB');
      skill(root, '.hidden');
      Directory('$root/empty').createSync(recursive: true);
      skill(root, 'ok');

      final files = await load();

      expect(names(files), ['ok']);
      expect(files.diagnostics, isEmpty);
    });

    test('only the first level: skills/<group>/<skill>/SKILL.md is not '
        'found (D3)', () async {
      skill('$home/skills/group', 'inner');

      final files = await load();

      expect(files.skills, isEmpty);
      expect(files.diagnostics, isEmpty);
    });

    test(
      '1000 subdirectories are read, the rest: one limit_exceeded warning',
      () async {
        final root = '$home/skills';
        for (var i = 0; i < 1001; i++) {
          final n = 's${i.toString().padLeft(4, '0')}';
          write('$root/$n/SKILL.md', '---\nname: $n\ndescription: D\n---\nB');
        }

        final files = await load();

        expect(files.skills, hasLength(1000));
        expect(names(files), isNot(contains('s1000')));
        final d = withCode(files, 'limit_exceeded').single;
        expect(d.level, DiagnosticLevel.warning);
      },
    );

    test('a cancelled token stops reading without failing', () async {
      skill('$home/skills', 'a');
      skill('$repo/.codelab/skills', 'b');
      final source = CancelTokenSource()..cancel();

      final files = await load(cancel: source.token);

      expect(files.skills, isEmpty);
    });
  });

  group('SKILL.md', () {
    test('is returned raw: parsed frontmatter, body, directory', () async {
      skill(
        '$home/skills',
        'notes',
        text:
            '---\nname: notes\ndescription: Takes notes\ncolor: red\n---\n'
            'Body line\n',
      );

      final files = await load();

      final s = files.skills.single;
      expect(s.dir, '$home/skills/notes');
      expect(s.frontmatter!.values, {
        'name': 'notes',
        'description': 'Takes notes',
        'color': 'red',
      });
      expect(s.frontmatter!.positions['color'], const ConfigPosition(4, 1));
      expect(s.body, 'Body line\n');
      expect(s.repaired, isFalse);
      expect(s.parseErrors, isEmpty);
      expect(s.companions, isEmpty);
      expect(s.companionsTruncated, isFalse);
    });

    test(
      'YAML repair: the host marks repaired, the frontmatter is parsed',
      () async {
        skill(
          '$home/skills',
          'pdf',
          text: '---\nname: pdf\ndescription: Use when: PDFs\n---\nB',
        );

        final files = await load();

        final s = files.skills.single;
        expect(s.repaired, isTrue);
        expect(s.frontmatter!.values['description'], 'Use when: PDFs');
      },
    );

    test('unreadable YAML: the skill is returned with the error, not '
        'dropped silently', () async {
      skill(
        '$home/skills',
        'broken',
        text: '---\nname: broken\ntags: [a, b\n---\nB',
      );

      final files = await load();

      final s = files.skills.single;
      expect(s.frontmatter, isNull);
      expect(s.parseErrors.single.level, DiagnosticLevel.error);
    });

    test('up to 128 KiB is read (the 64 KiB body limit is checked by the '
        'core)', () async {
      skill('$home/skills', 'big', body: 'a' * (100 * 1024));

      final files = await load();

      expect(files.skills.single.body.length, greaterThan(100 * 1024 - 1));
      expect(files.diagnostics, isEmpty);
    });

    test('over 128 KiB is not read: too_large', () async {
      skill('$home/skills', 'huge', body: 'a' * (129 * 1024));

      final files = await load();

      expect(files.skills, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'too_large');
      expect(d.level, DiagnosticLevel.error);
      expect(d.path, '$home/skills/huge/SKILL.md');
    });

    test('not UTF-8: not_utf8, the skill is skipped', () async {
      writeBytes('$home/skills/bad/SKILL.md', [0x2d, 0x2d, 0x2d, 0xff, 0xfe]);

      final files = await load();

      expect(files.skills, isEmpty);
      expect(codes(files), ['not_utf8']);
      expect(files.diagnostics.single.level, DiagnosticLevel.warning);
    });

    test('diagnostics have no fragments of the file', () async {
      write(
        '$home/skills/leak/SKILL.md',
        '---\nname: leak\nsk-test-secret: [\n---\nB',
      );

      final files = await load();

      final texts = [
        for (final s in files.skills) ...s.parseErrors.map((d) => d.message),
        for (final d in files.diagnostics) d.message,
      ].join('\n');
      expect(texts, isNot(contains('sk-test-secret')));
    });
  });

  group('companion files', () {
    late String dir;
    setUp(() {
      dir = '$home/skills/notes';
      skill('$home/skills', 'notes');
    });

    test('regular files to depth 3, sorted bytewise, without SKILL.md and '
        'evals/ (D5)', () async {
      write('$dir/template.md', 't');
      write('$dir/scripts/x.py', 'x');
      write('$dir/references/FORMS.md', 'f');
      write('$dir/a/b/c.txt', 'depth three');
      write('$dir/a/b/c/d.txt', 'depth four');
      write('$dir/evals/evals.json', '{}');

      final files = await load();

      final s = files.skills.single;
      expect(s.companions, [
        'a/b/c.txt',
        'references/FORMS.md',
        'scripts/x.py',
        'template.md',
      ]);
      expect(s.companionsTruncated, isFalse);
    });

    test('no dot-directories', () async {
      write('$dir/.git/config', 'x');
      write('$dir/.cache/a.txt', 'x');
      write('$dir/ok.txt', 'x');

      final files = await load();

      expect(files.skills.single.companions, ['ok.txt']);
    });

    test(
      'contents are not read: an invalid UTF-8 file is just a path',
      () async {
        writeBytes('$dir/data.bin', [0xff, 0xfe, 0x00]);

        final files = await load();

        expect(files.skills.single.companions, ['data.bin']);
        expect(files.diagnostics, isEmpty);
      },
    );

    test('the walk stops at the 5000th entry: companionsTruncated, 50 '
        'paths in byte order of what was found (D5)', () async {
      for (var i = 0; i < 5001; i++) {
        File('$dir/f${i.toString().padLeft(4, '0')}.txt').writeAsStringSync('');
      }

      final files = await load();

      final s = files.skills.single;
      expect(s.companions, hasLength(50));
      expect(s.companions.first, 'f0000.txt');
      expect(s.companionsTruncated, isTrue);
    });

    test('the limit counts every entry looked at, directories included '
        '(D5): 5100 empty directories and 3 files', () async {
      for (var i = 0; i < 5100; i++) {
        Directory(
          '$dir/e${i.toString().padLeft(4, '0')}',
        ).createSync(recursive: true);
      }
      for (final name in ['a.txt', 'b.txt', 'c.txt']) {
        File('$dir/$name').writeAsStringSync('');
      }

      final files = await load();

      final s = files.skills.single;
      expect(s.companions, ['a.txt', 'b.txt', 'c.txt']);
      expect(s.companionsTruncated, isTrue);
    });

    test('fewer entries than the limit: complete, not truncated', () async {
      for (var i = 0; i < 100; i++) {
        Directory(
          '$dir/e${i.toString().padLeft(3, '0')}',
        ).createSync(recursive: true);
      }
      File('$dir/a.txt').writeAsStringSync('');

      final files = await load();

      expect(files.skills.single.companions, ['a.txt']);
      expect(files.skills.single.companionsTruncated, isFalse);
    });

    test('exactly 50 files: the list is complete', () async {
      for (var i = 0; i < 50; i++) {
        write('$dir/f${i.toString().padLeft(2, '0')}.txt', 'x');
      }

      final files = await load();

      expect(files.skills.single.companions, hasLength(50));
      expect(files.skills.single.companionsTruncated, isFalse);
    });

    test('60 files: 50 paths in byte order and the incomplete flag', () async {
      for (var i = 0; i < 60; i++) {
        write('$dir/f${i.toString().padLeft(2, '0')}.txt', 'x');
      }

      final files = await load();

      final s = files.skills.single;
      expect(s.companions, hasLength(50));
      expect(s.companions.first, 'f00.txt');
      expect(s.companions.last, 'f49.txt');
      expect(s.companionsTruncated, isTrue);
    });

    test('scenario "Сопутствующий файл-ссылка наружу": loaded, the link is '
        'not in the list, the target is not read', () async {
      write('$home/config.yaml', 'secret: sk-test-secret');
      Link('$dir/ref.md').createSync('$home/config.yaml');
      write('$dir/own.md', 'x');

      final files = await load();

      final s = files.skills.single;
      expect(nameOf(s), 'notes');
      expect(s.companions, ['own.md']);
      expect(s.body, isNot(contains('sk-test-secret')));
      expect(files.diagnostics, isEmpty);
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

    test('a symlinked directory pointing outside is not listed', () async {
      write('$base/outside/leak.txt', 'x');
      Link('$dir/linked').createSync('$base/outside');
      write('$dir/own.md', 'x');

      final files = await load();

      expect(files.skills.single.companions, ['own.md']);
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);
  });

  /// `SkillFiles.sessionRoots` (design.md change `add-agent-skills`, D17;
  /// agent-permissions «Относительный корень extra_roots защищён в сессии»;
  /// решения Q27, Q44, Q46).
  ///
  /// Фиксируемый API: поле `SkillFiles.sessionRoots` (`List<String>`, в ядре
  /// по умолчанию пустое) — корни, которые защищает политика сессии:
  /// `sessionSkillRootsFor(cwd:, extraRoots:)` плюс канонические абсолютные и
  /// `~`-элементы `query.extraRoots`; не зависит от доверия проекта.
  group('sessionRoots', () {
    test('the default in the core is an empty list', () {
      expect(const SkillFiles().sessionRoots, isEmpty);
      expect(SkillFiles.empty.sessionRoots, isEmpty);
    });

    test('levels up to the git root and relative extra_roots, as '
        'sessionSkillRootsFor gives them', () async {
      final work = '$repo/apps/demo';
      Directory(work).createSync(recursive: true);

      final files = await load(cwd: work, extra: ['.claude/skills']);

      expect(
        files.sessionRoots,
        containsAll(
          await sessionSkillRootsFor(cwd: work, extraRoots: ['.claude/skills']),
        ),
      );
      expect(files.sessionRoots, contains('$work/.claude/skills'));
      expect(files.sessionRoots, contains('$repo/.agents/skills'));
    });

    test('absolute and ~ elements of extra_roots are added in canonical '
        'form, an unknown scheme and ~user are not', () async {
      Directory('$base/abs/skills').createSync(recursive: true);

      final files = await load(
        extra: [
          '$base/abs/skills',
          '~/mine/skills',
          '~other/skills',
          'builtin://x',
        ],
      );

      expect(files.sessionRoots, contains('$base/abs/skills'));
      expect(files.sessionRoots, contains('$userHome/mine/skills'));
      expect(
        files.sessionRoots.where(
          (r) => r.contains('other') || r.contains('builtin'),
        ),
        isEmpty,
      );
    });

    test('an untrusted project still has its session roots (Q27)', () async {
      final files = await load(trusted: false, extra: ['.claude/skills']);

      expect(files.skills, isEmpty);
      expect(files.sessionRoots, contains('$repo/.claude/skills'));
      expect(files.sessionRoots, contains('$repo/.agents/skills'));
    });

    test('roots are listed whether they exist or not', () async {
      final files = await load();

      expect(files.sessionRoots, contains('$repo/.codelab/skills'));
      expect(Directory('$repo/.codelab/skills').existsSync(), isFalse);
    });
  });
}
