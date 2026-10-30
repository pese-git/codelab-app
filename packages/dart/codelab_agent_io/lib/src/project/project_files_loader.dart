import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../env/host_path.dart';
import '../env/local_execution_env.dart';

/// Читает файлы проекта и пользователя с локальной файловой системы процесса
/// агента (design.md change `add-agent-project-files`, D1, D2, D4–D6;
/// `agent-core-architecture` §11.5).
///
/// Почему не env сессии: чтение идёт внутри `createSession`, до ответа
/// `session/new`, когда клиент ещё не знает `sessionId` (ACP-8); в ACP нет
/// `stat` и листинга каталога, а `$CODELAB_HOME` лежит на машине агента.
///
/// Для чего: реализация порта [ProjectFilesSource] для настольных хостов.
/// Сейчас читает файлы инструкций `AGENTS.md`/`CLAUDE.md` (E-01); шаблоны
/// команд и определения агентов добавят следующие итерации в тот же метод.
///
/// Как использовать: хост создаёт один загрузчик —
/// `ProjectFilesLoader(home: codelabHomeOf(env), local: LocalExecutionEnv(...))` —
/// и кладёт его в `AgentCoreServices.projectFiles`. `home: null` выключает
/// пользовательскую область (сценарий `--llm-script` не трогает
/// `$CODELAB_HOME`, D16). Метод [load] не бросает для ошибок файлов: каждая
/// ошибка — диагностика. Содержимое файлов в диагностики не попадает (D14).
///
/// Безопасность (приоритет 1): каждое чтение идёт через
/// `BoundedEnv.wrap(local, корень области)`; путь, чей `realpath` вне корня
/// (symlink наружу), отклоняется до чтения с диагностикой `outside_root`.
/// Единственная операция вне границы — проверка существования `<каталог>/.git`
/// у предков `cwd` при поиске корня репозитория; содержимое `.git` не
/// читается.
final class ProjectFilesLoader implements ProjectFilesSource {
  /// [local] — именно [LocalExecutionEnv]: граница чтения опирается на его
  /// `realpath` (`PathResolver`), а окружение без резолвера оставило бы
  /// границу лексической, и symlink наружу прошёл бы незамеченным
  /// (приоритет 1). Поэтому тип сужен до реализации, которая резолвер имеет.
  ProjectFilesLoader({required this.home, required LocalExecutionEnv local})
    : _local = local;

  /// `$CODELAB_HOME`; `null` — пользовательская область не читается.
  final String? home;
  final LocalExecutionEnv _local;

  /// Предел обхода вверх к корню репозитория (D5, пункт 1; D6).
  static const maxLevels = 64;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    final diagnostics = <ExtensionDiagnostic>[];
    final context = <ContextFile>[];
    var root = ContextRoot.cwd;
    if (query.contextMaxBytes > 0) {
      root = await _loadContext(query, context, diagnostics);
    }
    return ProjectFiles(
      context: context,
      contextRoot: root,
      diagnostics: diagnostics,
    );
  }

  /// Файлы контекста в порядке «пользовательский, затем от корня к `cwd`»
  /// (D5, пункт 1).
  Future<ContextRoot> _loadContext(
    ProjectFilesQuery query,
    List<ContextFile> out,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    final max = query.contextMaxBytes;
    final homeDir = home;
    if (homeDir != null && !query.cancel.isCancelled) {
      final env = await BoundedEnv.wrap(_local, homeDir);
      final file = await _readFile(
        env,
        '$homeDir/AGENTS.md',
        max,
        diagnostics,
        displayPath: r'$CODELAB_HOME/AGENTS.md',
        scope: ExtensionScope.user,
      );
      if (file != null) {
        out.add(file);
      }
    }

    final (:levels, :found) = await _findRoot(query.cwd, diagnostics);
    final root = levels.first;
    final env = await BoundedEnv.wrap(_local, root);
    for (final dir in levels) {
      if (query.cancel.isCancelled) {
        break;
      }
      final prefix = dir == root ? '' : '${dir.substring(root.length + 1)}/';
      final agents = '$dir/AGENTS.md';
      final claude = '$dir/CLAUDE.md';
      var name = 'AGENTS.md';
      var path = agents;
      if (!await _exists(env, agents)) {
        name = 'CLAUDE.md';
        path = claude;
      } else if (await _exists(env, claude)) {
        diagnostics.add(
          ExtensionDiagnostic(
            path: claude,
            level: DiagnosticLevel.info,
            code: 'shadowed',
            message: 'CLAUDE.md is ignored: AGENTS.md exists at the same level',
          ),
        );
      }
      final file = await _readFile(
        env,
        path,
        max,
        diagnostics,
        displayPath: '$prefix$name',
        scope: ExtensionScope.project,
      );
      if (file != null) {
        out.add(file);
      }
    }
    return found ? ContextRoot.git : ContextRoot.cwd;
  }

  /// Каталоги от корня репозитория к [cwd] и признак «репозиторий найден».
  ///
  /// Репозитория нет или он дальше [maxLevels] — единственный уровень `cwd`;
  /// в предел это даёт диагностику `info` (D6).
  Future<({List<String> levels, bool found})> _findRoot(
    String cwd,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    final up = <String>[];
    var dir = cwd.length > 1 && cwd.endsWith('/')
        ? cwd.substring(0, cwd.length - 1)
        : cwd;
    while (up.length < maxLevels) {
      up.add(dir);
      // `.git` — каталог или файл (worktree, submodule): важна только запись.
      // Symlink маркером не считается: `stat` его не раскрывает, а цель
      // лежит вне проверяемой границы; чужой репозиторий мог бы подложить
      // `.git` -> куда угодно и сдвинуть корень поиска.
      if (await _local.stat('$dir/.git') case Ok(
        :final value,
      ) when value.type == FileType.directory || value.type == FileType.file) {
        return (levels: up.reversed.toList(), found: true);
      }
      final slash = dir.lastIndexOf('/');
      if (slash <= 0) {
        // Дошли до корня файловой системы без репозитория.
        return (levels: [cwd], found: false);
      }
      dir = dir.substring(0, slash);
    }
    diagnostics.add(
      ExtensionDiagnostic(
        path: cwd,
        level: DiagnosticLevel.info,
        code: 'limit_exceeded',
        message:
            'no git repository within $maxLevels levels above the working '
            'directory; only the working directory is searched',
      ),
    );
    return (levels: [cwd], found: false);
  }

  /// Есть ли запись по [path] внутри границы [env]. Symlink наружу тоже
  /// «есть»: решение об отказе принимает [_readFile] с диагностикой.
  Future<bool> _exists(ExecutionEnv env, String path) async =>
      switch (await env.stat(path)) {
        Ok() => true,
        Err(:final error) => error.code == FileErrorCode.outsideWorkspace,
      };

  /// Читает файл контекста не больше `max + 1` байт (D5, пункт 4).
  ///
  /// Граница проверяется `realpath` через [env]; дальше читается уже
  /// проверенный реальный путь. Лишний байт нужен сборщику, чтобы отличить
  /// «файл ровно по бюджету» от «файл больше бюджета»; полный размер `M` —
  /// из `stat`, файл целиком не читается.
  Future<ContextFile?> _readFile(
    ExecutionEnv env,
    String path,
    int max,
    List<ExtensionDiagnostic> diagnostics, {
    required String displayPath,
    required ExtensionScope scope,
  }) async {
    void report(DiagnosticLevel level, String code, String message) =>
        diagnostics.add(
          ExtensionDiagnostic(
            path: path,
            level: level,
            code: code,
            message: message,
          ),
        );

    // `BoundedEnv` реализует `PathResolver`, потому что его реализует
    // `LocalExecutionEnv` (ENV-4). Иначе читать нельзя: без `realpath`
    // граница лексическая.
    if (env is! PathResolver) {
      report(
        DiagnosticLevel.warning,
        'unreadable',
        'the environment cannot resolve real paths; the file is not read',
      );
      return null;
    }
    final real = await (env as PathResolver).realpath(path);
    final String realPath;
    switch (real) {
      case Ok(:final value):
        realPath = value;
      case Err(:final error):
        switch (error.code) {
          case FileErrorCode.notFound:
            return null;
          case FileErrorCode.outsideWorkspace:
            report(
              DiagnosticLevel.warning,
              'outside_root',
              'the file resolves outside its root and is not read',
            );
          default:
            report(
              DiagnosticLevel.warning,
              'unreadable',
              'the file cannot be read: ${error.code.name}',
            );
        }
        return null;
    }
    final stat = await env.stat(realPath);
    if (stat case Ok(:final value) when value.type == FileType.file) {
      final size = value.size ?? 0;
      try {
        final bytes = await _readPrefix(realPath, max + 1);
        if (bytes == null) {
          report(
            DiagnosticLevel.warning,
            'outside_root',
            'the file changed while it was being opened and is not read',
          );
          return null;
        }
        final partial = size > bytes.length;
        final text = _decode(bytes, partial: partial);
        if (text == null) {
          report(
            DiagnosticLevel.warning,
            'not_utf8',
            'the file is not valid UTF-8 and is skipped',
          );
          return null;
        }
        return ContextFile(
          path: displayPath,
          content: text.startsWith('\u{FEFF}') ? text.substring(1) : text,
          totalBytes: size > bytes.length ? size : null,
          scope: scope,
        );
      } on io.FileSystemException {
        report(
          DiagnosticLevel.warning,
          'unreadable',
          'the file cannot be read',
        );
        return null;
      }
    }
    report(
      DiagnosticLevel.warning,
      'unreadable',
      'the path is not a regular file',
    );
    return null;
  }

  /// Читает первые [count] байт проверенного [corePath]; `null` — файл
  /// подменили между проверкой и открытием.
  ///
  /// После `open` путь проверяется ещё раз: `resolveSymbolicLinks` должен
  /// совпасть с проверенным реальным путём, а открытый путь — оставаться
  /// обычным файлом. Остаточный TOCTOU: в Dart нет `O_NOFOLLOW`, поэтому
  /// подмена между повторной проверкой и `read` возможна; её цена — чтение
  /// одного файла, который владелец каталога уже мог положить сам, а не обход
  /// контейнмента для произвольных путей. FIFO отсекает `stat` до `open`
  /// (открытие FIFO на чтение блокируется).
  Future<Uint8List?> _readPrefix(String corePath, int count) async {
    final host = toHostPath(corePath, windows: io.Platform.isWindows);
    final file = await io.File(host).open();
    try {
      if (await io.File(host).resolveSymbolicLinks() != host ||
          (await io.FileStat.stat(host)).type != io.FileSystemEntityType.file) {
        return null;
      }
      return await file.read(count);
    } finally {
      await file.close();
    }
  }

  /// Строгое декодирование UTF-8. У префикса (файл больше прочитанного)
  /// оборванная последовательность в конце не ошибка: до трёх байт хвоста
  /// отбрасываются.
  String? _decode(Uint8List bytes, {required bool partial}) {
    for (var drop = 0; drop <= (partial ? 3 : 0); drop++) {
      if (drop > bytes.length) {
        break;
      }
      try {
        return utf8.decode(
          Uint8List.sublistView(bytes, 0, bytes.length - drop),
        );
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
