import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Ветки fail-closed `ProjectFilesLoader`, недостижимые через публичный
/// конструктор (agent-project-context «Граница чтения файлов проекта»:
/// «Окружение без PathResolver», «Путь подменён после проверки»; design.md
/// change `add-agent-project-files`, D2). Тесты идут через
/// `ProjectFilesLoader.testing` — точку внедрения окружения и подмены пути.
void main() {
  late String base;
  late String repo;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('project_seam_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    Directory('$repo/.git').createSync(recursive: true);
  });

  Future<ProjectFiles> load(ProjectFilesLoader loader, {bool trusted = true}) =>
      loader.load(
        ProjectFilesQuery(
          cwd: repo,
          projectTrusted: trusted,
          contextMaxBytes: 32768,
          cancel: CancelToken.none,
        ),
      );

  group('an environment without PathResolver', () {
    test('AGENTS.md is not read: empty context, unreadable', () async {
      File('$repo/AGENTS.md').writeAsStringSync('rule A');
      final loader = ProjectFilesLoader.testing(
        home: null,
        local: _NoResolverEnv(LocalExecutionEnv(cwd: base)),
      );

      final files = await load(loader);

      expect(files.context, isEmpty);
      // Каталоги шаблонов и агентов тоже не читаются без резолвера, поэтому
      // диагностик несколько; нужная — по пути файла контекста.
      final diagnostic = files.diagnostics.singleWhere(
        (d) => d.path == '$repo/AGENTS.md',
      );
      expect(diagnostic.code, 'unreadable');
      expect(diagnostic.level, DiagnosticLevel.warning);
      // Текст ветки «нет PathResolver», а не ошибки realpath.
      expect(
        diagnostic.message,
        contains(
          'the environment cannot resolve real paths; the file is not read',
        ),
      );
      expect(diagnostic.message, isNot(contains('rule A')));
    });

    test('a template directory is not read either: unreadable', () async {
      Directory('$repo/.codelab/prompts').createSync(recursive: true);
      File('$repo/.codelab/prompts/review.md').writeAsStringSync('body');
      final loader = ProjectFilesLoader.testing(
        home: null,
        local: _NoResolverEnv(LocalExecutionEnv(cwd: base)),
      );

      // contextMaxBytes: 0 отключает чтение контекста (AGENTS.md), поэтому
      // остаются только диагностики каталогов prompts/agents.
      final files = await loader.load(
        ProjectFilesQuery(
          cwd: repo,
          projectTrusted: true,
          contextMaxBytes: 0,
          cancel: CancelToken.none,
        ),
      );

      expect(files.templates, isEmpty);
      expect([
        for (final d in files.diagnostics) d.code,
      ], everyElement('unreadable'));
      final prompts = files.diagnostics.singleWhere(
        (d) => d.path == '$repo/.codelab/prompts',
      );
      expect(prompts.code, 'unreadable');
      expect(
        prompts.message,
        contains(
          'the environment cannot resolve real paths; the directory is not read',
        ),
      );
    });
  });

  group('the path is swapped after the check', () {
    test('AGENTS.md replaced by a symlink out of the root: nothing read, '
        'outside_root', () async {
      File('$repo/AGENTS.md').writeAsStringSync('rule A');
      File('$base/outside.md').writeAsStringSync('top secret');
      var swaps = 0;
      final loader = ProjectFilesLoader.testing(
        home: null,
        local: LocalExecutionEnv(cwd: base),
        beforeOpen: (path) async {
          swaps++;
          File(path).deleteSync();
          Link(path).createSync('$base/outside.md');
        },
      );

      final files = await load(loader);

      expect(swaps, 1);
      expect(files.context, isEmpty);
      final diagnostic = files.diagnostics.single;
      expect(diagnostic.code, 'outside_root');
      expect(
        diagnostic.message,
        contains('the file changed while it was being opened and is not read'),
      );
      expect(diagnostic.path, '$repo/AGENTS.md');
      expect(diagnostic.message, isNot(contains('top secret')));
    }, skip: Platform.isWindows ? 'symlink needs privileges' : false);
  });
}

/// Окружение, делегирующее файлу и shell, но без `PathResolver` и
/// `DirectoryListing`: так выглядит хост, не умеющий `realpath`.
final class _NoResolverEnv implements ExecutionEnv {
  _NoResolverEnv(this._inner);

  final ExecutionEnv _inner;

  @override
  String get cwd => _inner.cwd;

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
