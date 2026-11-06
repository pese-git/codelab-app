/// Файловая реализация порта `AgentConfigStore` (client-agent-setup «Снимок и
/// запись конфига агента»; `dart-agent-and-clients` §12.4.2; design.md change
/// `add-provider-setup-ui`, D6).
library;

import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        Clock,
        ConfigConflictException,
        ConfigEdit,
        ConfigException,
        ConfigInlineSecretException,
        ConfigIssue,
        ConfigIssueKind,
        ConfigLayer,
        ConfigLoadResult,
        ConfigSnapshot,
        ConfigTarget,
        LogLevel,
        Logger,
        SystemClock;
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        ClientSecretAccess,
        ConfigLoader,
        ConfigUsageException,
        ConfigWriter,
        IoSecretProcessRunner,
        codelabHomeOf;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import '../config/config_values.dart';

/// Читает и пишет конфиг агента в файлах через `ConfigWriter` и
/// `ConfigLoader` `codelab_agent_io`.
///
/// Почему отдельный класс: страницам настроек нужны слои, итог загрузки,
/// источник каждого ключа и перевод исключений писателя в исходы — а клиентам
/// нельзя импортировать `codelab_agent_*` (`AGENTS.md` §5). Логику записи
/// (блокировка, fingerprint, атомарная замена, сохранение комментариев)
/// держит `ConfigWriter`; здесь только сборка и перевод.
///
/// Для чего: единая реализация порта для app и CLI; те же `CODELAB_HOME`,
/// окружение и `cwd`, что у агента из `SettingsAccess` (D5), поэтому проверка
/// «агент примет конфиг» совпадает с загрузкой агента.
///
/// Как использовать: composition root собирает один экземпляр на страницу —
/// `FileAgentConfigStore(paths: access.paths, environment: окружение агента,
/// secrets: `ClientSecretAccess`, переоткрытый при открытии страницы)`.
/// `snapshot(cwd:)` при открытии, после своей записи и после `ConfigConflict`;
/// слежения за файлом нет. `apply` НЕ повторяет запись при конфликте (SETUP-6)
/// и не перехватывает прочие исключения: это ошибки программиста.
final class FileAgentConfigStore implements AgentConfigStore {
  FileAgentConfigStore({
    required ConfigPaths paths,
    required Map<String, String> environment,
    required ClientSecretAccess secrets,
    Logger? logger,
    ConfigLoader? loader,
    Clock? clock,
    Random? random,
  }) : _paths = paths,
       // CODELAB_HOME профиля важнее окружения клиента: тот же дом, что у агента.
       _environment = Map.unmodifiable({
         ...environment,
         'CODELAB_HOME': paths.codelabHome,
       }),
       _secrets = secrets,
       _logger = logger ?? const _QuietLogger(),
       _loader = loader ?? ConfigLoader(),
       _clock = clock ?? const SystemClock(),
       _random = random ?? Random.secure(),
       _lastCwd = paths.projectDir;

  final ConfigPaths _paths;
  final Map<String, String> _environment;
  final ClientSecretAccess _secrets;
  final Logger _logger;
  final ConfigLoader _loader;
  final Clock _clock;
  final Random _random;

  /// `cwd` последнего снимка: писатель проверяет по нему проектные слои при
  /// записи в слой `user`.
  String? _lastCwd;

  ConfigWriter _writer(String? cwd) => ConfigWriter(
    codelabHome: codelabHomeOf(_environment),
    environment: _environment,
    loader: _loader,
    logger: _logger,
    processRunner: const IoSecretProcessRunner(),
    clock: _clock,
    random: _random,
    cwd: cwd,
  );

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async {
    _lastCwd = cwd;
    final layers = <ConfigLayer, ConfigSnapshot>{};
    final ConfigLoadResult loaded;
    try {
      final writer = _writer(cwd);
      for (final target in [
        const ConfigTarget.user(),
        ConfigTarget.project(cwd),
        ConfigTarget.projectLocal(cwd),
      ]) {
        try {
          layers[target.layer] = await writer.read(target);
        } on ConfigException {
          // Слой с битым YAML остаётся вне карты; причину называет загрузчик
          // (`loaded.issues`), а страница не пишет файл (D10, `Unreadable`).
          _logger.log(
            LogLevel.warning,
            'config.snapshot.layer_unreadable',
            fields: {'layer': target.layer.name},
          );
        }
      }
      loaded = _load(cwd, _environment);
    } on ConfigUsageException catch (error) {
      // `~user` в CODELAB_HOME или `.toml` в --config: проблема загрузки, а не
      // исключение; страница покажет текст и не будет писать.
      return AgentConfigSnapshot.fromLayers(
        cwd: cwd,
        layers: layers,
        loaded: ConfigLoadResult(issues: [_usageIssue(error)]),
        secrets: _secrets.backend,
      );
    }
    final external = _ExternalOrigins(this, cwd, loaded);
    return AgentConfigSnapshot.fromLayers(
      cwd: cwd,
      layers: layers,
      loaded: loaded,
      secrets: _secrets.backend,
      externalOrigin: external.of,
      externalSources: {
        ...AgentConfigSnapshot.defaultExternalSources,
        ..._pathForms(_paths.extraConfig),
        ..._pathForms(_environment['CODELAB_CONFIG']),
      },
    );
  }

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    try {
      final result = await _writer(_lastCwd).apply(base, edits);
      return ConfigSaved(
        fingerprint: result.fingerprint,
        warnings: result.warnings,
        restartRequiredKeys: result.restartRequiredKeys,
      );
    } on ConfigConflictException catch (error) {
      return ConfigConflict(error.path);
    } on ConfigInlineSecretException catch (error) {
      // Подкласс `ConfigException`: проверяется раньше него, иначе подсказка
      // «сохраните значение как секрет» превратилась бы в общий отказ.
      return ConfigInlineSecret(
        key: error.key,
        suggestedSecretName: error.suggestedSecretName,
      );
    } on ConfigException catch (error) {
      return ConfigRejected(error.issues);
    }
  }

  /// Путь `--config` как передан и в каноническом виде (ссылки и `..`
  /// раскрыты): загрузчик может назвать файл любым из них, а при несовпадении
  /// неверное значение внешнего ключа сошло бы за «ключ отсутствует» и
  /// страница показала бы Ready вместо Unreadable.
  Set<String> _pathForms(String? path) {
    if (path == null || path.isEmpty) {
      return const {};
    }
    final forms = {path};
    try {
      forms.add(File(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      // Файла нет: остаётся только исходный путь.
    }
    return forms;
  }

  ConfigLoadResult _load(String cwd, Map<String, String> environment) =>
      _loader.load(
        cwd: cwd,
        environment: environment,
        extraConfig: _paths.extraConfig,
      );

  ConfigIssue _usageIssue(ConfigUsageException error) => ConfigIssue(
    kind: ConfigIssueKind.value,
    key: '',
    source: error.source ?? 'config',
    message: error.message,
  );
}

/// Определяет, откуда пришёл лист, которого нет в файловых слоях: из файла
/// `--config` или из окружения.
///
/// Почему повторная загрузка: у итога загрузки нет разбивки по слоям, а
/// публичного разборщика YAML у моста нет. Загрузка без переменных `CODELAB_*`
/// (кроме `CODELAB_HOME` и `CODELAB_CONFIG`) даёт значения файлов; совпавший
/// лист пришёл из `--config`, иначе — из окружения. Выполняется лениво и один
/// раз, только если файл `--config` задан.
final class _ExternalOrigins {
  _ExternalOrigins(this._store, this._cwd, this._loaded);

  final FileAgentConfigStore _store;
  final String _cwd;
  final ConfigLoadResult _loaded;
  Map<String, Object?>? _withoutEnv;

  ConfigSourceView? of(String key) {
    final extra =
        _store._paths.extraConfig ?? _store._environment['CODELAB_CONFIG'];
    if (extra != null && extra.isNotEmpty) {
      final files = _withoutEnv ??= _store._load(_cwd, {
        for (final entry in _store._environment.entries)
          if (!entry.key.startsWith('CODELAB_') ||
              entry.key == 'CODELAB_HOME' ||
              entry.key == 'CODELAB_CONFIG')
            entry.key: entry.value,
      }).values;
      if (files.containsKey(key) &&
          sameConfigValue(files[key], _loaded.values[key])) {
        return ConfigSourceView(kind: ConfigSourceKind.extraFile, label: extra);
      }
    }
    return const ConfigSourceView(
      kind: ConfigSourceKind.environment,
      label: 'env',
    );
  }
}

final class _QuietLogger implements Logger {
  const _QuietLogger();

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
