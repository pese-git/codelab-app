import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/config_paths.dart';
import '../config/config_writer.dart' show ConfigWriteSeam;
import '../env/local_execution_env.dart';
import '../project/project_files_loader.dart';
import '../secrets/open_secret_store.dart';
import '../secrets/secret_process_runner.dart';
import '../state/last_model_file.dart';
import 'config_edit_runner.dart';
import 'config_output.dart';
import 'exit_codes.dart';
import '../util/silent_logger.dart';

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

/// Слой, из которого читает `config get` (design.md change
/// `add-config-writer-and-reload`, D6).
///
/// Почему отдельный enum: у чтения, в отличие от записи, есть ещё итоговый
/// вид [merged] — значение слоя-победителя среди всех слоёв, включая файл
/// `CODELAB_CONFIG`, окружение и флаги. Без флага приложение передаёт [merged]:
/// так `config get agent.default_model` показывает и `CODELAB_MODEL`.
///
/// Как использовать: приложение разбирает значение `--layer` через [parse], а
/// допустимые значения опции берёт из `values.map((l) => l.name)`; разбора
/// строки в каждом приложении отдельно нет (ревью итерации 4, arch L1).
/// Приложение (`codelab`) держит свой литерал допустимых значений `--layer`
/// без импорта этого пакета; его равенство [values] проверяет тест.
enum ConfigGetLayer {
  /// Слой-победитель среди всех слоёв — значение по умолчанию.
  merged,

  /// Только `$CODELAB_HOME/config.yaml`.
  user,

  /// Только `<cwd>/.codelab/config.yaml`.
  project,

  /// Только `<cwd>/.codelab/config.local.yaml`.
  local;

  /// Слой по имени из `--layer`; `null` (флаг не задан) — [merged].
  /// Неизвестное имя — [ArgumentError]: приложение отсекает его списком
  /// допустимых значений опции, до вызова.
  static ConfigGetLayer parse(String? name) =>
      name == null ? merged : values.byName(name);
}

/// Параметры `config path`, уже разобранные приложением (D6).
///
/// Как использовать: без [project] и [local] — вывести все слои и файл
/// `CODELAB_CONFIG`; с одним из них — только путь файла слоя. Оба флага —
/// код `64`. [cwd] — `--cwd` подкоманды или каталог процесса.
final class ConfigPathOptions {
  const ConfigPathOptions({
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME`, `CODELAB_CONFIG`.
  final Map<String, String> environment;

  /// `--project`: вывести только путь `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: вывести только путь `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Параметры `config get <key> [--layer …]` (D6).
///
/// Значения переменных окружения из [environment] в вывод не попадают
/// (R0-2).
final class ConfigGetOptions {
  const ConfigGetOptions({
    required this.key,
    required this.cwd,
    required this.environment,
    this.layer = ConfigGetLayer.merged,
  });

  /// Путь ключа в форме `KeyPath` (`providers.gw.headers`, `mcp.servers[gh]`).
  final String key;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME`, `CODELAB_CONFIG`, `CODELAB_*`.
  final Map<String, String> environment;

  /// `--layer`; по умолчанию [ConfigGetLayer.merged].
  final ConfigGetLayer layer;
}

/// Параметры `config set <key> <value>` (D6). [value] — строка из argv,
/// разбираемая `SettingsRegistry.parseCliValue`; в вывод и ошибки не
/// попадает. Оба флага слоя — код `64`.
final class ConfigSetOptions {
  const ConfigSetOptions({
    required this.key,
    required this.value,
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  /// Путь ключа в форме `KeyPath`.
  final String key;

  /// Новое значение строкой, как в argv.
  final String value;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME` и др.
  final Map<String, String> environment;

  /// `--project`: писать в `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: писать в `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Параметры `config unset <key>` (D6): принимает и ключ вне реестра, если он
/// есть в файле (так удаляются опечатки и `api_key`). Оба флага слоя — код
/// `64`.
final class ConfigUnsetOptions {
  const ConfigUnsetOptions({
    required this.key,
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  /// Путь ключа в форме `KeyPath`.
  final String key;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME` и др.
  final Map<String, String> environment;

  /// `--project`: править `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: править `<cwd>/.codelab/config.local.yaml`.
  final bool local;
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
    @visibleForTesting SecretProcessRunner? processRunner,
    @visibleForTesting Clock? clock,
    @visibleForTesting Random? random,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
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
               )),
       _runner = ConfigEditRunner(
         processRunner: processRunner,
         clock: clock,
         random: random,
         platform: platform,
         seam: writeSeam,
       );

  /// Как `_projectFilesTimeout` рантайма (D14 change `add-agent-project-files`): `check` показывает то, что
  /// увидит сессия.
  static const _defaultTimeout = Duration(seconds: 5);

  final ProjectFilesSource? _projectFiles;
  final Duration _projectFilesTimeout;
  final String _platform;
  final SecretStoreOpener _openStore;
  final ConfigEditRunner _runner;

  /// `path`: файлы слоёв конфига (D6). Ничего не читает и не создаёт, кроме
  /// проверки существования.
  ///
  /// Без [ConfigPathOptions.project] и [ConfigPathOptions.local] — по строке на слой (`user`, `project`,
  /// `local`) и, если задана `CODELAB_CONFIG`, на её файл, с пометкой
  /// `exists`/`missing`; со слоем — один путь без пометки, удобный для
  /// `$EDITOR $(codelab config path --local)`.
  Future<ConfigCommandResult> path(ConfigPathOptions options) async {
    final layer = ConfigFileLayer.fromFlags(
      project: options.project,
      local: options.local,
    );
    if (layer == null) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config path: ${ConfigFileLayer.conflictMessage}'],
      );
    }
    final cwd = options.cwd;
    if (!Directory(cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config path: no such directory: $cwd'],
      );
    }
    final String home;
    try {
      home = codelabHomeOf(options.environment);
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config path: ${error.message}'],
      );
    }
    // Пути считает та же функция, что и писатель: `--local` указывает на
    // файл, в который пишет `config set --local` (ревью итерации 4, arch L3).
    final files = {
      for (final file in ConfigFileLayer.values)
        file: configLayerFilePath(file.target(cwd), home),
    };
    if (options.project || options.local) {
      return ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [files[layer]!],
      );
    }
    String mark(String path) =>
        '$path (${FileSystemEntity.isFileSync(path) ? 'exists' : 'missing'})';
    final extra = options.environment['CODELAB_CONFIG'];
    return ConfigCommandResult(
      exitCode: configValidExit,
      stdout: [
        for (final MapEntry(:key, :value) in files.entries)
          '${key.name}: ${mark(value)}',
        if (extra != null && extra.isNotEmpty) 'CODELAB_CONFIG: ${mark(extra)}',
      ],
    );
  }

  /// `get`: сырое значение ключа из слоя-победителя и имя слоя, с
  /// маскированием R0-2 (D6; `maskConfigValue`).
  ///
  /// Почему сырое: `${VAR}` и `${secret:…}` не раскрываются ни при каком
  /// слое, включая `merged`: значение переменной — содержимое окружения, а оно
  /// может быть секретом. Работает и с невалидным конфигом (так находят
  /// ошибку): перечитываются слои загрузчика, а не итог. Исключение — файл с
  /// синтаксической ошибкой: его слоя нет, и подкоманда называет ошибку вместо
  /// ложного «ключ не задан».
  ///
  /// Коды: `0` значение найдено; `1` ключа нет в слое или файл не
  /// разобран; `64` неверный путь, каталог или `CODELAB_HOME`.
  Future<ConfigCommandResult> get(ConfigGetOptions options) async {
    if (splitKeyPath(options.key) == null) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config get: not a valid key path'],
      );
    }
    if (!Directory(options.cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config get: no such directory: ${options.cwd}'],
      );
    }
    final ({ConfigLoadResult result, List<ConfigTree> layers}) loaded;
    try {
      loaded = ConfigLoader().loadWithLayers(
        cwd: options.cwd,
        environment: options.environment,
        platform: _platform,
      );
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config get: ${error.message}'],
      );
    }
    final syntax = [
      for (final issue in loaded.result.issues)
        if (issue.kind == ConfigIssueKind.syntax) '$issue',
    ];
    if (syntax.isNotEmpty) {
      return ConfigCommandResult(exitCode: configInvalidExit, stderr: syntax);
    }
    final only = switch (options.layer) {
      ConfigGetLayer.merged => null,
      ConfigGetLayer.user => ConfigLayerKind.user,
      ConfigGetLayer.project => ConfigLayerKind.project,
      ConfigGetLayer.local => ConfigLayerKind.projectLocal,
    };
    final found = findLayerValue(loaded.layers, options.key, only: only);
    if (found == null) {
      return ConfigCommandResult(
        exitCode: configInvalidExit,
        stderr: [
          'config get: ${options.key} is not set'
              '${options.layer == ConfigGetLayer.merged ? '' : ' in the ${options.layer.name} layer'}',
        ],
      );
    }
    return ConfigCommandResult(
      exitCode: configValidExit,
      stdout: [
        ...renderConfigValue(
          maskConfigValue(found.value, key: options.key, layer: found.layer),
        ),
        'layer: ${configLayerName(found.layer.kind)}',
      ],
    );
  }

  /// `set`: записывает значение ключа в слой через `ConfigWriter` (D5, D6).
  ///
  /// Значение разбирает `SettingsRegistry.parseCliValue`; неизвестный ключ и
  /// неверное значение — код `64`, значение не цитируется. Ключ из
  /// `inlineSecretKeys` реестру не предъявляется: ответ должен быть «секрет
  /// значением» (код `1` с подсказкой `codelab secret set`), а не «неизвестный
  /// ключ» (D5, порядок проверок писателя).
  Future<ConfigCommandResult> set(ConfigSetOptions options) async {
    final key = options.key;
    final segments = splitKeyPath(key);
    if (segments == null) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config set: not a valid key path'],
      );
    }
    final last = segments.last;
    final Object value;
    if (!last.isElement && inlineSecretKeys.contains(last.value)) {
      // Значение уходит писателю как есть и отвергается им без цитирования.
      value = options.value;
    } else {
      final descriptor = SettingsRegistry.lookup(key);
      if (descriptor == null) {
        final near = _nearestSettingKey(key, segments);
        return ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: [
            'config set: unknown key $key'
                '${near == null ? '' : '; did you mean $near?'}',
          ],
        );
      }
      try {
        value = SettingsRegistry.parseCliValue(descriptor, options.value);
      } on ConfigValueException catch (error) {
        return ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: ['config set: ${error.key}: expected ${error.expected}'],
        );
      }
    }
    final outcome = await _runner.apply(
      label: 'config set',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [SetValue(key, value)],
    );
    return switch (outcome) {
      EditFinished(:final result) => result,
      EditWritten(:final result) => ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [
          'Updated $key in ${result.path}',
          ...ConfigEditRunner.successLines(result),
        ],
      ),
    };
  }

  /// `unset`: удаляет ключ из слоя (D6). Принимает и ключ вне реестра, если
  /// он есть в файле: так удаляются опечатки и запрещённый `api_key`.
  /// Ключа в файле нет — код `0` без записи (идемпотентно, как `secret
  /// delete`).
  Future<ConfigCommandResult> unset(ConfigUnsetOptions options) async {
    final key = options.key;
    if (splitKeyPath(key) == null) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config unset: not a valid key path'],
      );
    }
    final outcome = await _runner.apply(
      label: 'config unset',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [UnsetValue(key)],
      // Наличие — по пути, а не по значению: `max_steps:` (null) в файле есть.
      shortCircuit: (snapshot) => configKeyPresent(snapshot, key)
          ? null
          : ConfigCommandResult(
              exitCode: configValidExit,
              stdout: ['$key is not set in ${snapshot.path}'],
            ),
    );
    return switch (outcome) {
      EditFinished(:final result) => result,
      EditWritten(:final result) => ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [
          'Removed $key from ${result.path}',
          ...ConfigEditRunner.successLines(result),
        ],
      ),
    };
  }

  /// Ближайший ключ реестра для подсказки «did you mean»: шаблоны с `*`
  /// получают сегменты пользователя на месте звёздочек, поэтому опечатка в
  /// `providers.gw.kindd` находит `providers.gw.kind`.
  String? _nearestSettingKey(String key, List<KeyPathSegment> segments) {
    final candidates = <String>[];
    for (final d in SettingsRegistry.all) {
      final pattern = d.key.split('.');
      if (pattern.length != segments.length) {
        continue;
      }
      candidates.add(
        [
          for (var i = 0; i < pattern.length; i++)
            pattern[i] == '*' ? segments[i].value : pattern[i],
        ].join('.'),
      );
    }
    return nearestKey(key, candidates);
  }

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
        if (issues.isEmpty && config != null)
          ...await _modelLines(options, config),
        issues.isEmpty
            ? 'Config: valid'
            : 'Config: invalid (issues: ${issues.length})',
      ],
    );
  }

  /// Строка `Default model: <p>/<m> (<source>)` и предупреждение о
  /// нечитаемом файле последней модели (design.md change
  /// `optional-default-model`, D9).
  ///
  /// Почему здесь: после того как `agent.default_model` стал необязательным,
  /// пользователь должен видеть, какую модель получит новая сессия, и почему.
  /// Модель считает та же чистая функция ядра [selectSessionModel], что и
  /// рантайм, поэтому вывод `codelab-agent` и `codelab` совпадает с поведением.
  /// Файл [FileLastModelStore] только читается и только если модель конфига
  /// неявная; запись и создание каталога `state/` — не здесь. Нечитаемый файл
  /// даёт `warning: <path>: last model state ignored: <reason>` (причина —
  /// категория без содержимого) и переход к следующему шагу выбора.
  Future<List<String>> _modelLines(
    CheckOptions options,
    CoreConfig config,
  ) async {
    final capture = _CaptureLogger();
    ModelId? last;
    String? path;
    if (config.defaultModelSource != DefaultModelSource.config) {
      final store = FileLastModelStore(
        codelabHome: codelabHomeOf(options.environment),
        logger: capture,
      );
      path = store.path;
      last = await store.read();
    }
    final (model, source) = selectSessionModel(
      config,
      last,
      StaticModelCatalog(config.providers, logger: const SilentLogger()),
      effort: config.effort,
    );
    return [
      for (final reason in capture.reasons)
        'warning: $path: last model state ignored: $reason',
      'Default model: ${model.provider}/${model.id} (${source.wireName})',
    ];
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

/// Собирает причины `model.last_used.ignored` для строки `warning:` команды
/// `config check`: журнала у команды нет, а причина (категория без
/// содержимого файла) нужна в выводе.
final class _CaptureLogger implements Logger {
  final reasons = <String>[];

  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    if (event == 'model.last_used.ignored') {
      reasons.add('${fields['reason']}');
    }
  }
}
