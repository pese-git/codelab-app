import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/config_writer.dart' show ConfigWriteSeam;
import '../secrets/open_secret_store.dart';
import '../secrets/secret_process_runner.dart';
import 'config_commands.dart' show ConfigCommandResult;
import 'config_edit_runner.dart';
import 'config_output.dart';
import 'exit_codes.dart';
import 'secret_commands.dart';
import 'secret_input.dart';
import 'silent_logger.dart';

/// Параметры `provider add`, уже разобранные приложением (design.md change
/// `add-config-writer-and-reload`, D6; `agent-core-architecture` §17.5.5).
///
/// Почему поля `kind`, `model`, `contextWindow` могут быть `null`, а число —
/// строкой: разбор значений и ответ «не хватает `--kind`» должны быть общими у
/// `codelab-agent` и `codelab` (код `64` и тексты), поэтому приложение
/// передаёт то, что получило из argv, а проверяет `ProviderCommands`.
///
/// Как использовать: [id] — позиционный аргумент; из [apiKeySecret],
/// [apiKeyEnv] и [apiKeyStdin] допустим не больше одного. Заданный способ
/// ключа заменяет прежний источник в файле (R4-4). [makeDefault] — флаг
/// `--default` (`agent.default_model: <id>/<model>`). [project] и [local] —
/// флаги слоя; оба вместе — код `64`.
final class ProviderAddOptions {
  const ProviderAddOptions({
    required this.id,
    required this.cwd,
    required this.environment,
    this.kind,
    this.baseUrl,
    this.model,
    this.contextWindow,
    this.apiKeySecret,
    this.apiKeyEnv,
    this.apiKeyStdin = false,
    this.makeDefault = false,
    this.project = false,
    this.local = false,
  });

  /// Идентификатор провайдера (`[a-z0-9_-]+`).
  final String id;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME` и др.
  final Map<String, String> environment;

  /// `--kind`: `openai-compatible`, `anthropic` или `gemini`.
  final String? kind;

  /// `--base-url`.
  final String? baseUrl;

  /// `--model`: идентификатор модели провайдера.
  final String? model;

  /// `--context-window`: целое ≥ 1 строкой, как в argv.
  final String? contextWindow;

  /// `--api-key-secret`: имя секрета хранилища.
  final String? apiKeySecret;

  /// `--api-key-env`: имя переменной окружения.
  final String? apiKeyEnv;

  /// `--api-key-stdin`: ключ читается из stdin и сохраняется в хранилище.
  final bool apiKeyStdin;

  /// `--default`: сделать `<id>/<model>` моделью по умолчанию.
  final bool makeDefault;

  /// `--project`: писать в `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: писать в `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Параметры `provider list`.
final class ProviderListOptions {
  const ProviderListOptions({required this.cwd, required this.environment});

  /// Каталог проекта, для которого загружается конфиг.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME`, ключи API.
  final Map<String, String> environment;
}

/// Параметры `provider remove <id>`. Оба флага слоя — код `64`.
final class ProviderRemoveOptions {
  const ProviderRemoveOptions({
    required this.id,
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  /// Идентификатор удаляемого провайдера.
  final String id;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME` и др.
  final Map<String, String> environment;

  /// `--project`: править `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: править `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Общая реализация подкоманд `provider add|list|remove` для `codelab-agent`
/// и `codelab` (design.md change `add-config-writer-and-reload`, D6;
/// agent-configuration «Подкоманды записи и чтения конфига»).
///
/// Почему в `codelab_agent_io`: тексты, коды выхода и порядок шагов
/// `--api-key-stdin` должны быть одни у обоих бинарей; здесь есть
/// `ConfigWriter` и хранилища секретов.
///
/// Для чего: `add` — одна правка `ConfigWriter.apply` со списком `SetValue`
/// (провайдер, модель, ссылка на ключ, `--default`); `--api-key-stdin`
/// добавляет шаги D6: проверка кандидата без записи, проверка хранилища и
/// чтение ключа через `SecretCommands.set`, и только затем запись конфига
/// с `api_key_secret: codelab/<id>`. В конфиг попадает только имя секрета.
/// `list` показывает состояние ключей без значений; `remove` — `RemoveTable`.
///
/// Как использовать: `await ProviderCommands().add(options, StdinSecretInput())`
/// и аналогично `list`/`remove`; напечатать `stdout`/`stderr` результата и
/// завершиться с `exitCode` (`0`, `1`, `64`). [processRunner], [clock], [random],
/// [writeSeam] и [openStore] — швы тестов.
final class ProviderCommands {
  ProviderCommands({
    @visibleForTesting SecretProcessRunner? processRunner,
    @visibleForTesting Clock? clock,
    @visibleForTesting Random? random,
    @visibleForTesting String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
  }) : _platform = platform ?? Platform.operatingSystem,
       _openStore =
           openStore ??
           (({required choice, required environment, required home}) =>
               openSecretStore(
                 choice: choice,
                 environment: environment,
                 home: home,
                 logger: const SilentLogger(),
                 runner: processRunner,
                 platform: platform,
               )),
       _secrets = SecretCommands(
         runner: processRunner,
         // Швы тестов `platform` и `openStore` передаются дальше без изменений.
         // ignore: invalid_use_of_visible_for_testing_member
         platform: platform,
         // ignore: invalid_use_of_visible_for_testing_member
         openStore: openStore,
       ),
       _runner = ConfigEditRunner(
         processRunner: processRunner,
         clock: clock,
         random: random,
         platform: platform,
         seam: writeSeam,
       );

  final String _platform;
  final SecretStoreOpener _openStore;
  final SecretCommands _secrets;
  final ConfigEditRunner _runner;

  static final _idFormat = RegExp(r'^[a-z0-9_-]+$');
  static final _modelFormat = RegExp(r'^[^\s"]+$');
  static final _plainSegment = RegExp(r'^[A-Za-z0-9_\-]+$');

  /// Взаимоисключающие источники ключа провайдера (`resolve.dart`: «api_key,
  /// api_key_env and api_key_secret are mutually exclusive»). Литеральный
  /// `api_key` — тоже источник (R8-6; design.md change
  /// `add-config-literal-secrets-and-migrate`, D4): `add` с любым из флагов
  /// ключа удаляет его той же правкой, иначе рядом с новой ссылкой остался бы
  /// старый секрет в файле и пара источников.
  static const _keySourceFields = ['api_key', 'api_key_env', 'api_key_secret'];

  /// `add`: провайдер, его модель и ссылка на ключ одной правкой (D6).
  ///
  /// Ошибки использования (код `64`): неверный `id`, нет `--kind`, `--model`
  /// или `--context-window`, неверное значение флага, больше одного способа
  /// задать ключ. Значения флагов в тексты не попадают.
  Future<ConfigCommandResult> add(
    ProviderAddOptions options,
    SecretInput input,
  ) async {
    final id = options.id;
    ConfigCommandResult usage(String message) => ConfigCommandResult(
      exitCode: configUsageExit,
      stderr: ['provider add: $message'],
    );
    if (!_idFormat.hasMatch(id)) {
      return usage('the provider id must match [a-z0-9_-]+');
    }
    final model = options.model;
    // Недостающие флаги — одной строкой: иначе пользователь узнаёт о них по
    // одному, по запуску на каждый (ревью итерации 4, arch L8).
    final missing = [
      if (options.kind == null) '--kind',
      if (model == null || model.isEmpty) '--model',
      if (options.contextWindow == null) '--context-window',
    ];
    if (missing.isNotEmpty) {
      return usage('missing required options: ${missing.join(', ')}');
    }
    if (!_modelFormat.hasMatch(model!)) {
      return usage('--model must not contain whitespace or quotes');
    }
    final keyFlags = [
      options.apiKeySecret != null,
      options.apiKeyEnv != null,
      options.apiKeyStdin,
    ].where((set) => set).length;
    if (keyFlags > 1) {
      return usage(
        'use only one of --api-key-secret, --api-key-env and --api-key-stdin',
      );
    }

    final prefix = 'providers.$id';
    final modelKey =
        '$prefix.models.${_plainSegment.hasMatch(model) ? model : '"$model"'}';
    final secretName = 'codelab/$id';
    final sets = <ConfigEdit>[];
    // Каждое значение разбирает реестр по типу ключа: тексты ошибок общие с
    // `config set`.
    ConfigCommandResult? failure;
    void put(String key, String raw) {
      if (failure != null) {
        return;
      }
      try {
        sets.add(
          SetValue(
            key,
            SettingsRegistry.parseCliValue(SettingsRegistry.lookup(key)!, raw),
          ),
        );
      } on ConfigValueException catch (error) {
        failure = usage('${error.key}: expected ${error.expected}');
      }
    }

    put('$prefix.kind', options.kind!);
    if (options.baseUrl case final url?) {
      put('$prefix.base_url', url);
    }
    put('$modelKey.context_window', options.contextWindow!);
    if (options.apiKeySecret case final name?) {
      put('$prefix.api_key_secret', name);
    }
    if (options.apiKeyEnv case final variable?) {
      put('$prefix.api_key_env', variable);
    }
    if (options.apiKeyStdin) {
      put('$prefix.api_key_secret', secretName);
    }
    if (options.makeDefault) {
      put('agent.default_model', '$id/$model');
    }
    if (failure case final bad?) {
      return bad;
    }

    // Новый способ ключа заменяет прежний (R4-4): в файле не остаётся пары
    // `api_key_env` + `api_key_secret`. Правки строятся от снимка попытки:
    // повтор после конфликта видит свежий файл.
    final replacesKeySource =
        options.apiKeySecret != null ||
        options.apiKeyEnv != null ||
        options.apiKeyStdin;
    final chosenKeyField = options.apiKeyEnv != null
        ? 'api_key_env'
        : 'api_key_secret';
    List<ConfigEdit> editsFor(ConfigSnapshot snapshot) => [
      ...sets,
      if (replacesKeySource)
        for (final field in _keySourceFields)
          if (field != chosenKeyField &&
              configKeyPresent(snapshot, '$prefix.$field'))
            UnsetValue('$prefix.$field'),
    ];

    var secretStdout = const <String>[];
    var secretStderr = const <String>[];
    if (options.apiKeyStdin) {
      // Шаг 1 D6: итог проверяется без записи, чтобы заведомо негодную правку
      // не предварял ввод и сохранение ключа.
      final check = await _runner.apply(
        label: 'provider add',
        environment: options.environment,
        cwd: options.cwd,
        project: options.project,
        local: options.local,
        edits: editsFor,
        dryRun: true,
      );
      if (check case EditFinished(:final result)) {
        return result;
      }
      // Шаги 2–4 D6: проверка хранилища, ввод и сохранение ключа — та же
      // последовательность и те же тексты, что у `secret set`.
      final stored = await _secrets.set(
        SecretSetOptions(name: secretName, environment: options.environment),
        input,
      );
      if (stored.exitCode != 0) {
        return ConfigCommandResult(
          exitCode: stored.exitCode,
          stdout: stored.stdout,
          stderr: stored.stderr,
        );
      }
      secretStdout = [
        ...stored.stdout,
        if (stored.replaced)
          'warning: replaced the existing secret $secretName',
      ];
      secretStderr = stored.stderr;
    }

    final ConfigEditOutcome outcome;
    try {
      outcome = await _runner.apply(
        label: 'provider add',
        environment: options.environment,
        cwd: options.cwd,
        project: options.project,
        local: options.local,
        edits: editsFor,
      );
    } on Object catch (error) {
      if (!options.apiKeyStdin) {
        rethrow;
      }
      // Защитный рубеж шага 5: ключ уже в хранилище, и пользователь должен
      // узнать об этом, даже если запись упала неожиданным исключением. Только
      // тип: текст мог бы цитировать значения (CFG-10).
      return ConfigCommandResult(
        exitCode: configInvalidExit,
        stdout: secretStdout,
        stderr: [
          ...secretStderr,
          'the secret $secretName was stored; the config was not changed: '
              'unexpected ${error.runtimeType}',
        ],
      );
    }
    switch (outcome) {
      case EditFinished(:final result):
        if (!options.apiKeyStdin) {
          return result;
        }
        // Шаг 5 не удался: секрет остаётся в хранилище. Он безвреден без
        // ссылки, а повтор команды перезапишет его тем же значением (D6).
        return ConfigCommandResult(
          exitCode: result.exitCode,
          stdout: secretStdout,
          stderr: [
            ...secretStderr,
            'the secret $secretName was stored; the config was not changed: '
                '${result.stderr.join('; ')}',
          ],
        );
      case EditWritten(:final result):
        return ConfigCommandResult(
          exitCode: configValidExit,
          stdout: [
            ...secretStdout,
            'Updated $prefix in ${result.path}',
            ...ConfigEditRunner.successLines(result),
          ],
          stderr: secretStderr,
        );
    }
  }

  /// `list`: `Secrets: <backend>` и по строке на провайдера итогового
  /// конфига (D6).
  ///
  /// Строка: `<id>  kind: …  base_url: …  models: …  key: …`. Вид и адрес —
  /// сырые значения слоёв с маскированием R0-2 (раскрытый `${VAR}` итога
  /// конфига мог бы быть секретом); модели — из итога; источник ключа — без
  /// значения: `secret codelab/x: found|not set|unavailable` или
  /// `env VAR: set|not set`. Невалидный конфиг — код `1` с проблемами.
  Future<ConfigCommandResult> list(ProviderListOptions options) async {
    if (!Directory(options.cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['provider list: no such directory: ${options.cwd}'],
      );
    }
    final ({ConfigLoadResult result, List<ConfigTree> layers}) loaded;
    final String home;
    try {
      home = codelabHomeOf(options.environment);
      loaded = ConfigLoader().loadWithLayers(
        cwd: options.cwd,
        environment: options.environment,
        platform: _platform,
      );
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['provider list: ${error.message}'],
      );
    }
    final config = loaded.result.config;
    if (config == null) {
      return ConfigCommandResult(
        exitCode: configInvalidExit,
        stderr: [for (final issue in loaded.result.issues) '$issue'],
      );
    }
    SecretResolver? resolver;
    String backendLine;
    try {
      final store = _openStore(
        choice: loaded.result.host?.secretsBackend,
        environment: options.environment,
        home: home,
      );
      final info = store.backend;
      backendLine = info.unavailableReason == null
          ? 'Secrets: ${info.id}'
          : 'Secrets: ${info.id} (${info.unavailableReason})';
      resolver = SecretResolver(
        store: store,
        environment: options.environment,
        logger: const SilentLogger(),
      );
    } on SecretStoreUnavailableException catch (error) {
      backendLine = 'Secrets: ${error.backend} (unavailable: ${error.reason})';
    }

    String shown(String key, {String fallback = '-'}) {
      final found = findLayerValue(loaded.layers, key);
      if (found == null) {
        return fallback;
      }
      return renderConfigValue(
        maskConfigValue(found.value, key: key, layer: found.layer),
      ).join(' ');
    }

    final lines = <String>[backendLine];
    for (final provider in config.providers) {
      final name = provider.config.name;
      final prefix =
          'providers.${_plainSegment.hasMatch(name) ? name : '"$name"'}';
      String envKeyState(String? variable) => variable == null
          ? 'from environment'
          : 'env $variable: '
                '${(options.environment[variable] ?? '').isEmpty ? 'not set' : 'set'}';
      final keyState = switch (provider.key) {
        // Литеральный `api_key` файла (R8-4) — не ссылка: `key` пуст, а
        // значение лежит в `ProviderConfig.apiKey`. Значение не печатается.
        null when provider.config.literalApiKey => 'literal in config file',
        // `api_key: ${VAR}` (R8-8): ключ взят из переменной при загрузке;
        // источник показывается как у `api_key_env`, значение — нет.
        null when provider.config.apiKey != null => envKeyState(
          _referencedVariable(findLayerValue(loaded.layers, '$prefix.api_key')),
        ),
        null => 'none',
        UnusableKeyRef() => 'unusable reference (looks like a secret value)',
        EnvKeyRef(:final variable) =>
          'env $variable: '
              '${(options.environment[variable] ?? '').isEmpty ? 'not set' : 'set'}',
        SecretKeyRef(:final name) =>
          'secret $name: ${await _secretState(resolver, name)}',
      };
      lines.add(
        '$name  kind: ${shown('$prefix.kind')}  '
        'base_url: ${shown('$prefix.base_url', fallback: '(default)')}  '
        'models: ${provider.models.keys.join(', ')}  key: $keyState',
      );
    }
    return ConfigCommandResult(exitCode: configValidExit, stdout: lines);
  }

  /// `remove`: удаляет таблицу провайдера (`RemoveTable`, D6). Ссылка из
  /// `agent.*` делает итог невалидным (R3-1): код `1`, файл не меняется, и к
  /// проблеме добавляется подсказка сменить модель. Провайдера в файле нет —
  /// код `0` без записи.
  Future<ConfigCommandResult> remove(ProviderRemoveOptions options) async {
    final key = 'providers.${options.id}';
    if (!_idFormat.hasMatch(options.id)) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['provider remove: the provider id must match [a-z0-9_-]+'],
      );
    }
    final outcome = await _runner.apply(
      label: 'provider remove',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [RemoveTable(key)],
      // Наличие — по пути, а не по значению: `gw:` (null) в файле есть.
      shortCircuit: (snapshot) => configKeyPresent(snapshot, key)
          ? null
          : ConfigCommandResult(
              exitCode: configValidExit,
              stdout: ['$key is not set in ${snapshot.path}'],
            ),
    );
    return switch (outcome) {
      EditFinished(:final result, :final issues) =>
        // Подсказка — по ключу проблемы, а не по подстроке текста: путь файла
        // с " agent." в имени каталога не должен её вызывать.
        issues.any((issue) => issue.key.startsWith('agent.'))
            ? ConfigCommandResult(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: [
                  ...result.stderr,
                  'change the model first: config set agent.default_model '
                      '<provider>/<model>',
                ],
              )
            : result,
      EditWritten(:final result) => ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [
          'Removed $key from ${result.path}',
          ...ConfigEditRunner.successLines(result),
        ],
      ),
    };
  }

  /// Имя переменной, если значение `api_key` — ровно одна ссылка `${VAR}`.
  static String? _referencedVariable(LayerValue? found) {
    final value = found?.value;
    return value is String
        ? RegExp(
            r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$',
          ).firstMatch(value)?.group(1)
        : null;
  }

  Future<String> _secretState(SecretResolver? resolver, String name) async {
    if (resolver == null) {
      return 'unavailable';
    }
    return switch (await resolver.secret(name, purpose: 'provider list')) {
      SecretFound() => 'found',
      SecretMissing() => 'not set',
      SecretUnavailable() => 'unavailable',
    };
  }
}
