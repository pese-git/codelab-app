import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Шаблонная часть `ProjectFilesLoader` на реальных файлах (agent-slash-
/// commands «Каталоги шаблонов команд и доверие», «Формат шаблона и
/// проверка»; agent-project-context «Граница чтения файлов проекта»;
/// design.md change `add-agent-project-files`, D2, D3, D4, D6). Настоящий
/// `~/.codelab` не читается: `home` задаётся явно.
void main() {
  late String base;
  late String repo;
  late String home;
  late String projectDir;
  late String userDir;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('prompt_templates_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    home = '$base/home';
    projectDir = '$repo/.codelab/prompts';
    userDir = '$home/prompts';
    Directory('$repo/.git').createSync(recursive: true);
    Directory(userDir).createSync(recursive: true);
  });

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  void writeBytes(String path, List<int> bytes) => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(Uint8List.fromList(bytes));

  Future<ProjectFiles> load({
    bool trusted = false,
    String? withHome,
    int max = 32768,
    CancelToken? cancel,
  }) =>
      ProjectFilesLoader(
        home: withHome,
        local: LocalExecutionEnv(cwd: base),
      ).load(
        ProjectFilesQuery(
          cwd: repo,
          projectTrusted: trusted,
          contextMaxBytes: max,
          cancel: cancel ?? CancelToken.none,
        ),
      );

  List<String> names(ProjectFiles files) => [
    for (final t in files.templates) t.path.split('/').last,
  ];

  List<String> codes(ProjectFiles files) => [
    for (final d in files.diagnostics) d.code,
  ];

  group('trust', () {
    test(
      'an untrusted project is not read and gives one info diagnostic',
      () async {
        // Невалидный UTF-8: прочитай загрузчик файл, была бы `not_utf8`.
        writeBytes('$projectDir/review.md', [0xff, 0xfe, 0xfd]);
        write('$projectDir/other.md', 'x');

        final files = await load(withHome: home);

        expect(files.templates, isEmpty);
        final d = files.diagnostics.single;
        expect(d.code, 'untrusted_project');
        expect(d.level, DiagnosticLevel.info);
        expect(d.path, projectDir);
      },
    );

    test(
      'an untrusted project without the directory gives no diagnostic',
      () async {
        final files = await load(withHome: home);

        expect(files.diagnostics, isEmpty);
      },
    );

    test('a trusted project is read', () async {
      write('$projectDir/review.md', 'Project body');

      final files = await load(trusted: true, withHome: home);

      final t = files.templates.single;
      expect(t.path, '$projectDir/review.md');
      expect(t.scope, ExtensionScope.project);
      expect(t.body, 'Project body');
      expect(t.frontmatter, isNull);
      expect(files.diagnostics, isEmpty);
    });

    test(
      'the user directory is read whether the project is trusted or not',
      () async {
        write('$userDir/mine.md', 'User body');

        for (final trusted in [false, true]) {
          final files = await load(trusted: trusted, withHome: home);

          final t = files.templates.single;
          expect(t.path, '$userDir/mine.md');
          expect(t.scope, ExtensionScope.user);
        }
      },
    );

    test('home null: the user directory is not read', () async {
      write('$userDir/mine.md', 'User body');

      final files = await load();

      expect(files.templates, isEmpty);
      expect(files.diagnostics, isEmpty);
    });

    test('a project and a user template of one name both reach the core, '
        'which lets the project win', () async {
      write('$projectDir/review.md', 'project body');
      write('$userDir/review.md', 'user body');

      final files = await load(trusted: true, withHome: home);
      final parsed = parseCommandTemplates(files.templates);

      expect(files.templates, hasLength(2));
      expect(parsed.templates.single.body, 'project body');
      expect(parsed.diagnostics.single.code, 'shadowed');
    });
  });

  group('limits', () {
    test('101 files: the first 100 by name, one warning', () async {
      for (var i = 0; i <= 100; i++) {
        write('$userDir/t${i.toString().padLeft(3, '0')}.md', 'b$i');
      }

      final files = await load(withHome: home);

      expect(files.templates, hasLength(100));
      expect(names(files).first, 't000.md');
      expect(names(files).last, 't099.md');
      final d = files.diagnostics.single;
      expect(d.code, 'limit_exceeded');
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, userDir);
    });

    test('exactly 100 files give no diagnostic', () async {
      for (var i = 0; i < 100; i++) {
        write('$userDir/t${i.toString().padLeft(3, '0')}.md', 'b$i');
      }

      final files = await load(withHome: home);

      expect(files.templates, hasLength(100));
      expect(files.diagnostics, isEmpty);
    });

    test('a 65 KiB file is too_large and is not read', () async {
      // Невалидный UTF-8 в большом файле: прочитай загрузчик его, была бы
      // `not_utf8`.
      writeBytes('$userDir/big.md', List.filled(65 * 1024, 0xff));

      final files = await load(withHome: home);

      expect(files.templates, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'too_large');
      expect(d.path, '$userDir/big.md');
    });

    test('a 64 KiB file is read', () async {
      write('$userDir/edge.md', 'a' * (64 * 1024));

      final files = await load(withHome: home);

      expect(files.templates.single.body, hasLength(64 * 1024));
      expect(files.diagnostics, isEmpty);
    });

    test('templates are read when the context budget is 0', () async {
      write('$userDir/mine.md', 'x');

      final files = await load(withHome: home, max: 0);

      expect(files.templates, hasLength(1));
    });
  });

  group('what is listed', () {
    test('subdirectories are not entered, dotfiles and other files are '
        'skipped silently', () async {
      write('$userDir/sub/inner.md', 'inner');
      write('$userDir/.hidden.md', 'hidden');
      write('$userDir/notes.txt', 'text');
      write('$userDir/ok.md', 'ok');

      final files = await load(withHome: home);

      expect(names(files), ['ok.md']);
      expect(files.diagnostics, isEmpty);
    });

    test('a file that is not UTF-8 is a warning and is skipped', () async {
      writeBytes('$userDir/latin.md', [0x63, 0xe9, 0x64]);
      write('$userDir/ok.md', 'ok');

      final files = await load(withHome: home);

      expect(names(files), ['ok.md']);
      final d = files.diagnostics.single;
      expect(d.code, 'not_utf8');
      expect(d.level, DiagnosticLevel.warning);
    });

    test('frontmatter is split and carries file positions', () async {
      write(
        '$userDir/review.md',
        '---\r\ndescription: Code review\r\n---\r\nReview \$1\r\n',
      );

      final files = await load(withHome: home);

      final t = files.templates.single;
      expect(t.frontmatter!.values, {'description': 'Code review'});
      expect(
        t.frontmatter!.positions['description'],
        const ConfigPosition(2, 1),
      );
      expect(t.body, 'Review \$1\n');
      expect(t.bodyLine, 4);
    });

    test(
      'a broken frontmatter is an error diagnostic, not a failure',
      () async {
        write(
          '$userDir/review.md',
          '---\ndescription: one\ndescription: two\n---\nBody',
        );
        write('$userDir/ok.md', 'ok');

        final files = await load(withHome: home);

        expect(names(files), ['ok.md']);
        final d = files.diagnostics.single;
        expect(d.code, 'profile');
        expect(d.path, '$userDir/review.md');
        expect([d.line, d.column], [3, 1]);
        expect(d.message, contains('first defined at 2:1'));
      },
    );

    test('contents of a file never reach a diagnostic', () async {
      write(
        '$userDir/review.md',
        '---\nsk-test-secret: &a v\n---\nBody sk-test-secret',
      );

      final files = await load(withHome: home);

      for (final d in files.diagnostics) {
        expect('${d.message} ${d.path}', isNot(contains('sk-test-secret')));
      }
    });
  });

  group('the read boundary', () {
    test('a symlink to a file outside is outside_root and not read', () async {
      write('$base/outside.md', 'secret outside');
      Directory(projectDir).createSync(recursive: true);
      Link('$projectDir/leak.md').createSync('$base/outside.md');

      final files = await load(trusted: true, withHome: home);

      expect(files.templates, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.level, DiagnosticLevel.warning);
      expect(d.path, '$projectDir/leak.md');
    });

    test('a symlink to a file inside the directory is read', () async {
      write('$projectDir/real.md', 'real body');
      Link('$projectDir/alias.md').createSync('$projectDir/real.md');

      final files = await load(trusted: true, withHome: home);

      expect(names(files), ['alias.md', 'real.md']);
      expect(
        [for (final t in files.templates) t.body],
        ['real body', 'real body'],
      );
    });

    test('a symlink to a file in the repo but outside the prompts directory '
        'is outside_root', () async {
      write('$repo/README.md', 'readme');
      Directory(projectDir).createSync(recursive: true);
      Link('$projectDir/readme.md').createSync('$repo/README.md');

      final files = await load(trusted: true, withHome: home);

      expect(files.templates, isEmpty);
      expect(codes(files), ['outside_root']);
    });

    test('a prompts directory that is a symlink outside the project is '
        'outside_root', () async {
      write('$base/elsewhere/leak.md', 'secret');
      Directory('$repo/.codelab').createSync(recursive: true);
      Link(projectDir).createSync('$base/elsewhere');

      final files = await load(trusted: true, withHome: home);

      expect(files.templates, isEmpty);
      final d = files.diagnostics.single;
      expect(d.code, 'outside_root');
      expect(d.path, projectDir);
    });

    test('a user prompts directory that is a symlink outside the home is '
        'outside_root', () async {
      Directory(userDir).deleteSync();
      write('$base/elsewhere/leak.md', 'secret');
      Link(userDir).createSync('$base/elsewhere');

      final files = await load(withHome: home);

      expect(files.templates, isEmpty);
      expect(codes(files), ['outside_root']);
    });

    test('a FIFO named like a template is not opened: unreadable, no block, '
        'in the project and the user directory', () async {
      for (final dir in [projectDir, userDir]) {
        Directory(dir).createSync(recursive: true);
        final made = await Process.run('mkfifo', ['$dir/x.md']);
        expect(made.exitCode, 0, reason: '${made.stderr}');
      }
      write('$userDir/ok.md', 'fine');

      // Открытие FIFO на чтение ждёт писателя: загрузчик обязан отказать по
      // `stat`, не вызывая `open`.
      final files = await load(
        trusted: true,
        withHome: home,
      ).timeout(const Duration(seconds: 10));

      expect(names(files), ['ok.md']);
      expect(codes(files), ['unreadable', 'unreadable']);
      expect(
        {for (final d in files.diagnostics) d.path},
        {'$projectDir/x.md', '$userDir/x.md'},
      );
    }, skip: Platform.isWindows ? 'no mkfifo' : false);

    test('a directory named like a template is not read', () async {
      Directory('$userDir/dir.md').createSync();

      final files = await load(withHome: home);

      expect(files.templates, isEmpty);
      expect(files.diagnostics, isEmpty);
    });

    test('a cancelled token stops reading between files', () async {
      write('$userDir/a.md', 'a');
      write('$userDir/b.md', 'b');
      final source = CancelTokenSource()..cancel();

      final files = await load(withHome: home, cancel: source.token);

      expect(files.templates, isEmpty);
    });
  });
}
