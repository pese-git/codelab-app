import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Часть определений агентов в `ProjectFilesLoader` на реальных файлах
/// (agent-definitions «Каталоги определений агентов и доверие», «Формат
/// определения и проверка»; agent-project-context «Граница чтения файлов
/// проекта»; design.md change `add-agent-project-files`, D2, D3, D4, D6, D10;
/// CFG-6). Настоящий `~/.codelab` не читается: `home` задаётся явно.
void main() {
  late String base;
  late String repo;
  late String home;
  late String projectDir;
  late String userDir;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('agent_definitions_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    home = '$base/home';
    projectDir = '$repo/.codelab/agents';
    userDir = '$home/agents';
    Directory('$repo/.git').createSync(recursive: true);
    Directory(userDir).createSync(recursive: true);
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  void writeBytes(String path, List<int> bytes) => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(Uint8List.fromList(bytes));

  String agent(String name, {String description = 'An agent'}) =>
      '---\nname: $name\ndescription: $description\n---\nBody of $name\n';

  Future<ProjectFiles> load({
    bool trusted = false,
    String? withHome,
    CancelToken? cancel,
  }) =>
      ProjectFilesLoader(
        home: withHome,
        local: LocalExecutionEnv(cwd: base),
      ).load(
        ProjectFilesQuery(
          cwd: repo,
          projectTrusted: trusted,
          contextMaxBytes: 32768,
          cancel: cancel ?? CancelToken.none,
        ),
      );

  List<String> names(ProjectFiles files) => [
    for (final t in files.agents) t.path.split('/').last,
  ];

  List<String> codes(ProjectFiles files) => [
    for (final d in files.diagnostics) d.code,
  ];

  group('trust (CFG-6)', () {
    test(
      'an untrusted project is not read and gives one info diagnostic',
      () async {
        // Невалидный UTF-8: прочитай загрузчик файл, была бы `not_utf8`.
        writeBytes('$projectDir/reviewer.md', [0xff, 0xfe, 0xfd]);
        write('$projectDir/other.md', agent('other'));

        final files = await load(withHome: home);

        expect(files.agents, isEmpty);
        final d = files.diagnostics.single;
        expect(d.code, 'untrusted_project');
        expect(d.level, DiagnosticLevel.info);
        expect(d.path, projectDir);
        expect(d.message, contains('agent definitions'));
      },
    );

    test(
      'an untrusted project without the directory gives no diagnostic',
      () async {
        expect((await load(withHome: home)).diagnostics, isEmpty);
      },
    );

    test('a trusted project is read', () async {
      write('$projectDir/reviewer.md', agent('reviewer'));

      final files = await load(trusted: true, withHome: home);

      final a = files.agents.single;
      expect(a.path, '$projectDir/reviewer.md');
      expect(a.scope, ExtensionScope.project);
      expect(a.frontmatter!.values['name'], 'reviewer');
      expect(a.body, 'Body of reviewer\n');
      expect(files.diagnostics, isEmpty);
    });

    test(
      'the user directory is read whether the project is trusted or not',
      () async {
        write('$userDir/mine.md', agent('mine'));

        for (final trusted in [false, true]) {
          final files = await load(trusted: trusted, withHome: home);

          expect(files.agents.single.path, '$userDir/mine.md');
          expect(files.agents.single.scope, ExtensionScope.user);
        }
      },
    );

    test('home null: the user directory is not read', () async {
      write('$userDir/mine.md', agent('mine'));

      final files = await load();

      expect(files.agents, isEmpty);
      expect(files.diagnostics, isEmpty);
    });

    test(
      'templates and agents do not mix: each directory feeds its own list',
      () async {
        write('$home/prompts/review.md', 'template body');
        write('$userDir/reviewer.md', agent('reviewer'));

        final files = await load(withHome: home);

        expect(
          [for (final t in files.templates) t.path.split('/').last],
          ['review.md'],
        );
        expect(names(files), ['reviewer.md']);
      },
    );

    test(
      'a project and a user definition of one name both reach the core, '
      'which lets the project win and keeps the project description',
      () async {
        write(
          '$projectDir/reviewer.md',
          agent('reviewer', description: 'project'),
        );
        write('$userDir/reviewer.md', agent('reviewer', description: 'user'));

        final files = await load(trusted: true, withHome: home);
        final parsed = parseAgentDefinitions(
          files.agents,
          models: FixedModelCatalog(const []),
        );

        expect(files.agents, hasLength(2));
        expect(parsed.agents.single.description, 'project');
        expect(parsed.diagnostics.single.code, 'shadowed');
        expect(parsed.diagnostics.single.path, '$userDir/reviewer.md');
      },
    );
  });

  group('limits', () {
    test('101 files: the first 100 by name, one warning', () async {
      for (var i = 0; i <= 100; i++) {
        final n = i.toString().padLeft(3, '0');
        write('$userDir/a$n.md', agent('a$n'));
      }

      final files = await load(withHome: home);

      expect(files.agents, hasLength(100));
      expect(names(files).first, 'a000.md');
      expect(names(files).last, 'a099.md');
      final d = files.diagnostics.single;
      expect(d.code, 'limit_exceeded');
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, userDir);
      expect(d.message, contains('agent definitions'));
    });

    test('a 65 KiB file is too_large and is not read', () async {
      writeBytes('$userDir/big.md', List.filled(65 * 1024, 0xff));

      final files = await load(withHome: home);

      expect(files.agents, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'too_large');
      expect(d.path, '$userDir/big.md');
    });

    test('a file that is not UTF-8 is a warning and is skipped', () async {
      writeBytes('$userDir/latin.md', [0x63, 0xe9, 0x64]);
      write('$userDir/ok.md', agent('ok'));

      final files = await load(withHome: home);

      expect(names(files), ['ok.md']);
      expect(files.diagnostics.single.code, 'not_utf8');
    });

    test(
      'a broken frontmatter is an error diagnostic, not a failure',
      () async {
        write('$userDir/bad.md', '---\nname: a\nname: b\n---\nBody');
        write('$userDir/ok.md', agent('ok'));

        final files = await load(withHome: home);

        expect(names(files), ['ok.md']);
        final d = files.diagnostics.single;
        expect(d.code, 'profile');
        expect(d.path, '$userDir/bad.md');
      },
    );
  });

  group('multi-line tools and comments reach the core as a list', () {
    test('frontmatter of the issue example', () async {
      write(
        '$userDir/reviewer.md',
        '---\n'
            'name: reviewer\n'
            'description: "Reviews: changes"  # a comment\n'
            'tools:\n'
            '  - read\n'
            '  - "search"\n'
            '  - ls\n'
            '  - mcp__github__*\n'
            '---\nBody\n',
      );

      final files = await load(withHome: home);
      final parsed = parseAgentDefinitions(
        files.agents,
        models: FixedModelCatalog(const []),
      );

      expect(parsed.diagnostics, isEmpty);
      expect(parsed.agents.single.description, 'Reviews: changes');
      expect(parsed.agents.single.tools, [
        'read',
        'search',
        'ls',
        'mcp__github__*',
      ]);
    });
  });

  group('the read boundary', () {
    test('a symlink to a file outside is outside_root and not read', () async {
      write('$base/outside.md', agent('leak'));
      Directory(projectDir).createSync(recursive: true);
      Link('$projectDir/leak.md').createSync('$base/outside.md');

      final files = await load(trusted: true, withHome: home);

      expect(files.agents, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.path, '$projectDir/leak.md');
    });

    test('an agents directory that is a symlink outside the project is '
        'outside_root', () async {
      write('$base/elsewhere/leak.md', agent('leak'));
      Directory('$repo/.codelab').createSync(recursive: true);
      Link(projectDir).createSync('$base/elsewhere');

      final files = await load(trusted: true, withHome: home);

      expect(files.agents, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.path, projectDir);
    });

    test('a user agents directory that is a symlink outside the home is '
        'outside_root', () async {
      Directory(userDir).deleteSync();
      write('$base/elsewhere/leak.md', agent('leak'));
      Link(userDir).createSync('$base/elsewhere');

      final files = await load(withHome: home);

      expect(files.agents, isEmpty);
      expect(codes(files), ['outside_root']);
    });

    test(
      'a FIFO named like a definition is not opened: unreadable, no block',
      () async {
        final made = await Process.run('mkfifo', ['$userDir/x.md']);
        expect(made.exitCode, 0, reason: '${made.stderr}');
        write('$userDir/ok.md', agent('ok'));

        final files = await load(
          withHome: home,
        ).timeout(const Duration(seconds: 10));

        expect(names(files), ['ok.md']);
        expect(codes(files), ['unreadable']);
      },
      skip: Platform.isWindows ? 'no mkfifo' : false,
    );

    test('a cancelled token stops reading between files', () async {
      write('$userDir/a.md', agent('a'));
      write('$userDir/b.md', agent('b'));
      final source = CancelTokenSource()..cancel();

      final files = await load(withHome: home, cancel: source.token);

      expect(files.agents, isEmpty);
    });

    test('contents of a definition never reach a diagnostic', () async {
      write(
        '$userDir/a.md',
        '---\nsk-test-secret: &a v\n---\nBody sk-test-secret',
      );

      final files = await load(withHome: home);

      for (final d in files.diagnostics) {
        expect('${d.message} ${d.path}', isNot(contains('sk-test-secret')));
      }
    });
  });
}
