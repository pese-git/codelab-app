import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../env/local_execution_env.dart';
import '../project/project_files_loader.dart';
import '../secrets/open_secret_store.dart';
import 'exit_codes.dart';
import 'secret_commands.dart' show SecretStoreOpener;
import 'silent_logger.dart';

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
  ///
  /// [platform] подменяет `Platform.operatingSystem` (подсказка секретов на
  /// Windows, D7); [openStore] — только для тестов: фейковое хранилище секретов
  /// вместо `openSecretStore` (D9).
  ConfigCommands({
    @visibleForTesting ProjectFilesSource? projectFiles,
    @visibleForTesting Duration projectFilesTimeout = _defaultTimeout,
    @visibleForTesting String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
  }) : _projectFiles = projectFiles,
       _projectFilesTimeout = projectFilesTimeout,
       _platform = platform ?? Platform.operatingSystem,
       _openStore =
           openStore ??
           (({required choice, required environment, required home}) =>
               openSecretStore(
                 choice: choice,
                 environment: environment,
                 home: home,
                 logger: const SilentLogger(),
                 platform: platform,
               ));

  /// Как `_projectFilesTimeout` рантайма (D14 change `add-agent-project-files`): `check` показывает то, что
  /// увидит сессия.
  static const _defaultTimeout = Duration(seconds: 5);

  final ProjectFilesSource? _projectFiles;
  final Duration _projectFilesTimeout;
  final String _platform;
  final SecretStoreOpener _openStore;

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
    final List<ConfigTree> layers;
    try {
      // Флагов у `check` нет: проверяется то, что увидит `serve` без флагов.
      final loadedWithLayers = ConfigLoader().loadWithLayers(
        cwd: options.cwd,
        environment: options.environment,
        platform: _platform,
      );
      loaded = loadedWithLayers.result;
      layers = loadedWithLayers.layers;
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
    // Состояние секретов — только у валидного конфига (D9): у невалидного
    // ссылки не проверены, и хранилище не нужно.
    final secretLines = issues.isEmpty && config != null
        ? await _secretLines(options, loaded, config, layers)
        : const <String>[];
    return ConfigCommandResult(
      exitCode: issues.isEmpty ? configValidExit : configInvalidExit,
      stdout: [
        'Sources: ${loaded.sources.join(', ')}',
        for (final issue in issues) '$issue',
        for (final warning in loaded.warnings) 'warning: $warning',
        ...fileLines,
        ...secretLines,
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
        logger: const SilentLogger(),
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

  /// Строки состояния секретов (agent-configuration «config check показывает
  /// состояние секретов»; design.md change `add-agent-secret-store`, D9).
  ///
  /// Почему здесь, а не в ядре: ядро не знает хранилища, а подсказки
  /// (`codelab secret set`, `secrets.backend: file`) — тексты CLI. Ссылки
  /// собираются в порядке конфига: ключ провайдера, затем шаблоны его
  /// заголовков, затем `env`/`headers` MCP-серверов.
  ///
  /// Для чего: пользователь видит ненайденный секрет до первого хода, но код
  /// выхода не меняется — секрет нужен только при выборе этой модели (та же
  /// логика, что `config.provider.key_missing`). Без ссылок хранилище не
  /// вызывается и вывод прежний; исключение — бэкенд `file`: строка об
  /// открытом тексте печатается всегда (CFG-11), а права файла проверяются
  /// через `names()` (значения не читаются, файл не создаётся). Найденный
  /// секрет строки не даёт, значение читается в память и отбрасывается;
  /// резолвер без режима отладки, логгер тихий.
  Future<List<String>> _secretLines(
    CheckOptions options,
    ConfigLoadResult loaded,
    CoreConfig config,
    List<ConfigTree> layers,
  ) async {
    final references = _secretReferences(config, layers, loaded);
    final choice = loaded.host?.secretsBackend;
    if (references.isEmpty && choice != 'file') {
      return const [];
    }
    final String home;
    try {
      home = codelabHomeOf(options.environment);
    } on ConfigUsageException {
      return const [];
    }
    final DescribedSecretStore store;
    try {
      store = _openStore(
        choice: choice,
        environment: options.environment,
        home: home,
      );
    } on SecretStoreUnavailableException catch (error) {
      return [
        'warning: secrets: ${error.backend} is unavailable '
            '(${error.reason})',
      ];
    }
    final backend = store.backend;
    final lines = <String>[];
    if (references.isNotEmpty) {
      lines.add(
        backend.unavailableReason == null
            ? 'note: secrets backend: ${backend.id}'
            : 'note: secrets backend: ${backend.id} '
                  '(${backend.unavailableReason})',
      );
    }
    var reasonShown = false;
    if (backend.id == 'file') {
      lines.add(
        'warning: secrets: file backend stores secrets unencrypted in '
        '$home/secrets.yaml',
      );
      try {
        // Только проверка прав и формата файла: отсутствующий файл не
        // создаётся, значения не читаются.
        await store.names();
      } on SecretStoreUnavailableException catch (error) {
        // Права (`<path> has permissions 0644; run: chmod 600 <path>`) — своя
        // строка с готовой командой исправления (D9). Остальные отказы
        // (ссылка, каталог, размер) — `file is unavailable (<причина>)`,
        // как у недоступного бэкенда; вторая строка по тому же отказу не
        // печатается.
        lines.add(
          error.reason.contains(' has permissions ')
              ? 'warning: secrets: ${error.reason}'
              : 'warning: secrets: file is unavailable (${error.reason})',
        );
        reasonShown = true;
      } on Object catch (error) {
        lines.add(
          'warning: secrets: ${backend.id} is unavailable '
          '(secret store failed: ${error.runtimeType})',
        );
        reasonShown = true;
      }
    }
    final resolver = SecretResolver(
      store: store,
      environment: options.environment,
      logger: const SilentLogger(),
    );
    for (final reference in references) {
      switch (await resolver.secret(reference.name, purpose: reference.key)) {
        case SecretFound():
          break;
        case SecretMissing():
          lines.add(
            'warning: ${reference.location}: ${reference.key}: '
            '${_missingText(reference.name, backend.id)}',
          );
        case SecretUnavailable(:final backend, :final reason):
          if (!reasonShown) {
            reasonShown = true;
            lines.add('warning: secrets: $backend is unavailable ($reason)');
          }
      }
    }
    return lines;
  }

  /// Текст «секрет не задан» с подсказкой по бэкенду (D9): у `env` — переменная
  /// или `secrets.backend: file` (на Windows только переменная, D7), у
  /// остальных — `codelab secret set`.
  String _missingText(String name, String backendId) {
    if (backendId != 'env') {
      return 'secret $name is not set; run: codelab secret set $name';
    }
    final variable = SecretNames.envOverride(name);
    return _platform == 'windows'
        ? 'secret $name is not set; set $variable'
        : "secret $name is not set; set $variable or add "
              "'secrets.backend: file' and run: codelab secret set $name";
  }

  /// Ссылки на секреты конфига без повторов имён: первое упоминание даёт
  /// ключ и место для строки `warning:`.
  List<_SecretReference> _secretReferences(
    CoreConfig config,
    List<ConfigTree> layers,
    ConfigLoadResult loaded,
  ) {
    final out = <_SecretReference>[];
    final seen = <String>{};
    void add(String name, KeyPath key) {
      if (seen.add(name)) {
        out.add(
          _SecretReference(
            name: name,
            key: key.value,
            location: _locationOf(key, layers, loaded),
          ),
        );
      }
    }

    for (final provider in config.providers) {
      final at = KeyPath('providers').child(provider.config.name);
      if (provider.key case SecretKeyRef(:final name)) {
        add(name, at.child('api_key_secret'));
      }
      for (final MapEntry(key: header, value: template)
          in provider.headerTemplates.entries) {
        for (final name in template.names) {
          add(name, at.child('headers').child(header));
        }
      }
    }
    for (final server in config.mcpServers) {
      final at = KeyPath('mcp.servers').at(server.name);
      for (final MapEntry(key: field, value: template)
          in server.secretValues.entries) {
        // Ключ шаблона — `env.<KEY>` или `headers.<Name>`.
        final dot = field.indexOf('.');
        final path = at
            .child(field.substring(0, dot))
            .child(field.substring(dot + 1));
        for (final name in template.names) {
          add(name, path);
        }
      }
    }
    return out;
  }

  /// `файл:строка:столбец` слоя, который последним задал ключ; слой без
  /// позиций (окружение, флаги) и неизвестное место дают имя источника.
  String _locationOf(
    KeyPath key,
    List<ConfigTree> layers,
    ConfigLoadResult loaded,
  ) {
    for (final layer in layers.reversed) {
      final position = layer.positions[key.value];
      if (position != null) {
        return '${layer.source}:${position.line}:${position.column}';
      }
    }
    return loaded.sources.isEmpty ? 'config' : loaded.sources.last;
  }

  /// `путь[:строка[:столбец]]` диагностики.
  String _where(ExtensionDiagnostic item) {
    final line = item.line;
    final column = item.column;
    return '${item.path}${line == null ? '' : ':$line'}'
        '${column == null ? '' : ':$column'}';
  }
}

/// Ссылка на секрет конфига: имя, путь ключа и место ключа в файле.
final class _SecretReference {
  const _SecretReference({
    required this.name,
    required this.key,
    required this.location,
  });

  final String name;
  final String key;
  final String location;
}
