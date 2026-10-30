import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../env/local_execution_env.dart';
import '../project/project_files_loader.dart';
import 'exit_codes.dart';

/// Параметры `config check`, уже разобранные приложением (D13).
///
/// Почему не флаги строкой: разбор аргументов — дело `package:args` каждого
/// приложения (в allowlist `codelab_agent_io` его нет), а общая часть
/// получает типизированный вход.
///
/// Как использовать: [cwd] — каталог проекта (приложение подставляет текущий,
/// если `--cwd` не задан), [environment] — переменные процесса
/// (`Platform.environment`).
final class CheckOptions {
  const CheckOptions({required this.cwd, required this.environment});

  /// Каталог проекта: корень, от которого ищется `.codelab/config.yaml`.
  final String cwd;

  /// Переменные процесса: из них берутся `CODELAB_HOME`, `HOME` и ключи API.
  final Map<String, String> environment;
}

/// Результат подкоманды: код выхода и строки двух потоков (D13).
///
/// Почему данные, а не печать: приложение само пишет в свои stdout/stderr,
/// а тест сравнивает вывод `codelab` и `codelab-agent` построчно.
final class ConfigCommandResult {
  const ConfigCommandResult({
    required this.exitCode,
    this.stdout = const [],
    this.stderr = const [],
  });

  /// [configValidExit], [configInvalidExit] или [configUsageExit].
  final int exitCode;

  /// Строки для stdout приложения (без перевода строки).
  final List<String> stdout;

  /// Строки для stderr приложения: тексты ошибок использования и сбоев.
  final List<String> stderr;
}

/// Общая реализация подкоманд `config` для `codelab-agent` и `codelab`
/// (design.md change `add-agent-configuration`, D13; `agent-core-architecture`
/// §17.5.5).
///
/// Почему в `codelab_agent_io`: тексты, правила и коды выхода должны жить в
/// одном месте, иначе два бинаря разойдутся. Здесь есть `dart:io` и
/// [ConfigLoader].
///
/// Для чего: [check] выполняет полную загрузку §15.5 без запуска агента, а
/// для валидного конфига ещё и проверяет файлы проекта — шаблоны команд и
/// определения агентов (change `add-agent-project-files`, D13). Ничего не
/// пишет на диск, не читает stdin, значений секретов и фрагментов файлов не
/// печатает: [ConfigIssue.message] и `ExtensionDiagnostic.message` строятся
/// из фиксированных текстов, путей и типов (CFG-2; D14 change
/// `add-agent-configuration` и `add-agent-project-files`).
///
/// Как использовать: `await ConfigCommands().check(CheckOptions(cwd: …,
/// environment: Platform.environment))`, затем напечатать `stdout`/`stderr`
/// результата и завершиться с `exitCode`.
final class ConfigCommands {
  /// [projectFiles] и [projectFilesTimeout] — только для тестов: подмена
  /// источника файлов проекта (зависший порт) и короткий предел фазы. В
  /// приложениях — `ConfigCommands()`: загрузчик по умолчанию, предел 5 с.
  ConfigCommands({
    @visibleForTesting ProjectFilesSource? projectFiles,
    @visibleForTesting Duration projectFilesTimeout = _defaultTimeout,
  }) : _projectFiles = projectFiles,
       _projectFilesTimeout = projectFilesTimeout;

  /// Как `_projectFilesTimeout` рантайма (D14 change `add-agent-project-files`): `check` показывает то, что
  /// увидит сессия.
  static const _defaultTimeout = Duration(seconds: 5);

  final ProjectFilesSource? _projectFiles;
  final Duration _projectFilesTimeout;

  /// Печатает слои, проблемы и предупреждения, итог — последней строкой.
  ///
  /// Асинхронен, потому что `ProjectFilesLoader` читает файлы через порты
  /// ядра (D13). Диагностика файлов проекта идёт строками `warning:` и
  /// `note:` перед итогом и не влияет ни на итог, ни на код выхода: файлы
  /// проекта не мешают запуску (D6).
  Future<ConfigCommandResult> check(CheckOptions options) async {
    if (!Directory(options.cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config check: no such directory: ${options.cwd}'],
      );
    }
    final ConfigLoadResult loaded;
    try {
      // Флагов у `check` нет: проверяется то, что увидит `serve` без флагов.
      loaded = ConfigLoader().load(
        cwd: options.cwd,
        environment: options.environment,
      );
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config check: ${error.message}'],
      );
    }
    final issues = loaded.issues;
    final config = loaded.config;
    // Невалидный конфиг: каталога моделей и доверия нет, файлы проекта не
    // проверяются (D13).
    final fileLines = issues.isEmpty && config != null
        ? await _projectFileLines(options, config)
        : const <String>[];
    return ConfigCommandResult(
      exitCode: issues.isEmpty ? configValidExit : configInvalidExit,
      stdout: [
        'Sources: ${loaded.sources.join(', ')}',
        for (final issue in issues) '$issue',
        for (final warning in loaded.warnings) 'warning: $warning',
        ...fileLines,
        issues.isEmpty
            ? 'Config: valid'
            : 'Config: invalid (issues: ${issues.length})',
      ],
    );
  }

  /// Строки диагностики файлов проекта (D13): `warning:` для уровней `error`
  /// и `warning`, `note:` для `untrusted_project`; прочие `info` (`shadowed`)
  /// не печатаются.
  ///
  /// Доверие считается как в `serve` (D4): канонический `cwd` (форма ядра,
  /// `LocalExecutionEnv.realpath`, как `AgentRuntime._canonicalCwd`)
  /// сравнивается с `trusted_projects` конфига; без раскрытого `realpath`
  /// проект недоверенный (fail-closed). Каталог моделей собирается из
  /// провайдеров загруженного конфига, как у хоста (`StaticModelCatalog`).
  ///
  /// Фаза не должна ронять `check` и держать его вечно (как фаза рантайма,
  /// D14 change `add-agent-project-files`): исключение даёт одну строку
  /// `warning:` с типом исключения, отсутствие ответа за [_projectFilesTimeout]
  /// — строку о таймауте; код выхода от файлов проекта не зависит.
  Future<List<String>> _projectFileLines(
    CheckOptions options,
    CoreConfig config,
  ) async {
    var shown = Directory(options.cwd).absolute.path;
    final cancel = CancelTokenSource();
    try {
      final local = LocalExecutionEnv(
        cwd: shown,
        hostEnvironment: options.environment,
      );
      final String cwd;
      final bool trusted;
      switch (await local.realpath(shown)) {
        case Ok(:final value):
          cwd = value;
          // `trustedProjects` уже канонические (`ConfigLoader`, хостовая
          // форма); `samePath` ядра не экспортируется, поэтому сравнение
          // строк после приведения `\\` к `/` (форма ядра на Windows).
          trusted = config.trustedProjects.any(
            (r) => r.replaceAll('\\', '/') == value,
          );
        case Err():
          cwd = local.cwd;
          trusted = false;
      }
      shown = cwd;
      final source =
          _projectFiles ??
          ProjectFilesLoader(
            home: codelabHomeOf(options.environment),
            local: local,
          );
      final files = await source
          .load(
            ProjectFilesQuery(
              cwd: cwd,
              projectTrusted: trusted,
              contextMaxBytes: config.projectContextMaxBytes,
              cancel: cancel.token,
            ),
          )
          .then<ProjectFiles?>((value) => value)
          .timeout(_projectFilesTimeout, onTimeout: () => null);
      if (files == null) {
        // Загрузчик перестаёт читать (D6), результат выбрасывается.
        cancel.cancel();
        return [
          'warning: $cwd: project files were not read within '
              '${_projectFilesTimeout.inSeconds} s',
        ];
      }
      final models = StaticModelCatalog(
        config.providers,
        logger: const _SilentLogger(),
      );
      final diagnostics = [
        ...files.diagnostics,
        ...parseCommandTemplates(files.templates).diagnostics,
        ...parseAgentDefinitions(files.agents, models: models).diagnostics,
      ];
      return [
        for (final item in diagnostics)
          if (item.level != DiagnosticLevel.info)
            'warning: ${_where(item)}: ${item.message}'
          else if (item.code == 'untrusted_project')
            'note: ${item.path}: the project is not trusted; '
                'add it to trusted_projects',
      ];
    } on Object catch (error) {
      // Только тип исключения: текст может содержать пути и фрагменты (D14).
      cancel.cancel();
      return [
        'warning: $shown: project files could not be read: '
            '${error.runtimeType}',
      ];
    } finally {
      cancel.dispose();
    }
  }

  /// `путь[:строка[:столбец]]` диагностики.
  String _where(ExtensionDiagnostic item) {
    final line = item.line;
    final column = item.column;
    return '${item.path}${line == null ? '' : ':$line'}'
        '${column == null ? '' : ':$column'}';
  }
}

/// Тихий логгер для каталога моделей внутри [ConfigCommands].
///
/// Почему: `StaticModelCatalog` требует `Logger` и пишет в него события о
/// моделях, а `check` печатает результат только строками своего вывода
/// (stdout/stderr — контракт D13), поэтому события лога были бы шумом.
///
/// Как использовать: передавать `const _SilentLogger()` только в каталог
/// `check`; в хостах (`serve`) живёт настоящий логгер.
final class _SilentLogger implements Logger {
  const _SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
