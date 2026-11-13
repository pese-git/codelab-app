import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Пустая строка в `home` и `userHome` — «пользовательской области нет», а не
/// корень файловой системы (ревью итерации 5 change `add-agent-skills`,
/// приоритет 1: `'$home/skills'` при `home == ''` указывал бы на `/skills`,
/// а `'$home/AGENTS.md'` — на `/AGENTS.md`).
///
/// Почему так: `parseServeArgs` под `--llm-script` кладёт в `codelabHome`
/// пустую строку (D16, D19), и хост, передав её загрузчику как есть, открыл бы
/// корень диска. Проверка идёт через окружение без `PathResolver`: оно не
/// читает файлы, а загрузчик называет каждый пробуемый путь в диагностике
/// `unreadable` (`project_files_loader_seam_test.dart`), поэтому путь вне
/// заданных корней виден без подмены файловой системы.
void main() {
  late String repo;
  late String base;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('empty_home_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    Directory('$repo/.git').createSync(recursive: true);
  });

  ProjectFilesLoader loader({String? home, String? userHome}) =>
      ProjectFilesLoader.testing(
        home: home,
        userHome: userHome,
        local: _NoResolverEnv(LocalExecutionEnv(cwd: base)),
      );

  Future<Set<String>> probedPaths(ProjectFilesLoader loader) async {
    final files = await loader.load(
      ProjectFilesQuery(
        cwd: repo,
        projectTrusted: false,
        contextMaxBytes: 32768,
        cancel: CancelToken.none,
      ),
    );
    final skills = await loader.loadSkills(
      SkillFilesQuery(
        cwd: repo,
        projectTrusted: false,
        cancel: CancelToken.none,
      ),
    );
    return {
      for (final d in [...files.diagnostics, ...skills.diagnostics]) d.path,
    };
  }

  test('control: a non-empty home and userHome are probed', () async {
    final paths = await probedPaths(
      loader(home: '$base/h', userHome: '$base/u'),
    );

    expect(
      paths,
      containsAll([
        '$base/h/AGENTS.md',
        '$base/h/skills',
        '$base/h/prompts',
        '$base/u/.agents/skills',
      ]),
    );
  });

  test('home: "" and userHome: "" mean no user area: nothing under the '
      'filesystem root is probed', () async {
    final paths = await probedPaths(loader(home: '', userHome: ''));

    expect([
      for (final p in paths)
        if (p.startsWith('/skills') ||
            p.startsWith('/AGENTS.md') ||
            p.startsWith('/prompts') ||
            p.startsWith('/agents') ||
            p.startsWith('/.agents'))
          p,
    ], isEmpty);
  });
}

/// Окружение без `PathResolver`: читает через вложенное, но резолвера не имеет.
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
