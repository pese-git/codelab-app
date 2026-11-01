import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/yaml_reader.dart';
import '../secrets/open_secret_store.dart';
import '../secrets/secret_admin.dart';
import '../secrets/secret_process_runner.dart';
import 'exit_codes.dart';
import 'secret_input.dart';
import 'silent_logger.dart';

/// Открывает хранилище секретов по значению `secrets.backend` (design.md
/// change `add-agent-secret-store`, D7, D8).
///
/// Почему тип: `SecretCommands` и `ConfigCommands` получают хранилище одним
/// способом, а тесты подменяют его фейком, не создавая файлов. По умолчанию —
/// `openSecretStore` с тихим логгером. [choice] — значение `secrets.backend`
/// (`null` — `auto`), [home] — `$CODELAB_HOME`. Недопустимое значение —
/// `SecretStoreUnavailableException`.
typedef SecretStoreOpener =
    DescribedSecretStore Function({
      required String? choice,
      required Map<String, String> environment,
      required String home,
    });

/// Параметры `secret set`, уже разобранные приложением (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему не флаги строкой: разбор аргументов — дело `package:args` каждого
/// приложения, общая часть получает типизированный вход. Значение секрета в
/// параметрах отсутствует намеренно: оно читается только из stdin. Если
/// пользователь передал значение позиционным аргументом, приложение сообщает
/// лишь факт — [hasValueArgument]; сам аргумент не доходит до общей части и
/// поэтому не может быть напечатан.
final class SecretSetOptions {
  const SecretSetOptions({
    required this.name,
    required this.environment,
    this.hasValueArgument = false,
  });

  final String name;

  /// Переменные процесса: из них берутся `CODELAB_HOME`, `CODELAB_CONFIG`,
  /// `CODELAB_SECRET_*`. В `toString` не попадают.
  final Map<String, String> environment;

  /// Передан лишний позиционный аргумент (вероятно, значение секрета).
  final bool hasValueArgument;
}

/// Параметры `secret delete`, уже разобранные приложением (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему отдельный тип: приложение разбирает аргументы само (`package:args`),
/// а общая часть получает только имя и окружение — одинаково для `codelab` и
/// `codelab-agent`.
///
/// Для чего: `SecretCommands.delete` проверяет [name] правилами
/// `SecretNames` и читает из [environment] `CODELAB_HOME` и настройки
/// бэкенда; значения секрета не требует и не печатает.
///
/// Как использовать: `SecretDeleteOptions(name: 'codelab/openai',
/// environment: Platform.environment)`.
final class SecretDeleteOptions {
  const SecretDeleteOptions({required this.name, required this.environment});

  final String name;
  final Map<String, String> environment;
}

/// Параметры `secret list`, уже разобранные приложением (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему отдельный тип: у `list` нет аргументов, но вход общей части обязан
/// быть одинаков для обоих бинарей и расширяем без смены сигнатур.
///
/// Для чего: [environment] даёт `CODELAB_HOME`, настройки бэкенда и имена
/// переменных `CODELAB_SECRET_*`, которые `list` показывает только именами.
///
/// Как использовать: `SecretListOptions(environment: Platform.environment)`.
final class SecretListOptions {
  const SecretListOptions({required this.environment});

  final Map<String, String> environment;
}

/// Результат подкоманды `secret`: код выхода и строки двух потоков.
///
/// Почему данные, а не печать: приложение само пишет в свои stdout/stderr, а
/// тест сравнивает вывод `codelab` и `codelab-agent` построчно (D8).
final class SecretCommandResult {
  const SecretCommandResult({
    required this.exitCode,
    this.stdout = const [],
    this.stderr = const [],
    this.showUsage = false,
  });

  /// `0`, `1` (ошибка хранилища или конфигурации) или `64` (ошибка
  /// использования или значения).
  final int exitCode;

  /// Строки для stdout приложения (без перевода строки).
  final List<String> stdout;

  /// Строки для stderr приложения.
  final List<String> stderr;

  /// Приложение должно добавить к stderr справку `secret`: ошибка
  /// использования (неверное имя, значение аргументом).
  final bool showUsage;
}

/// Общая реализация подкоманд `secret set|delete|list` для `codelab-agent` и
/// `codelab` (design.md change `add-agent-secret-store`, D8; agent-secrets
/// «Подкоманды secret»).
///
/// Почему в `codelab_agent_io`: тексты, правила и коды выхода должны жить в
/// одном месте, иначе два бинаря разойдутся; здесь есть `dart:io` и бэкенды.
/// Логику записи, проверок и результатов даёт [SecretAdmin], здесь только
/// чтение настроек бэкенда, ввод значения и тексты для терминала.
///
/// Для чего: подкоманды работают без запуска агента и без ACP. Бэкенд берётся
/// из `secrets.backend` файлов `$CODELAB_HOME/config.yaml` и `CODELAB_CONFIG`
/// — и только этот ключ: полная загрузка конфига заблокировала бы ровно ту
/// команду, которая чинит конфиг с ключом, вписанным значением (CFG-9,
/// подсказка `inlineSecret`). Значения и длины секретов не печатаются
/// никогда; ошибки читаются из результатов [SecretAdmin], а не из исключений
/// хранилища.
///
/// Как использовать: `await SecretCommands().set(SecretSetOptions(…),
/// StdinSecretInput())` (аналогично [delete], [list]); напечатать `stdout` и
/// `stderr` результата, при [SecretCommandResult.showUsage] — ещё справку
/// `secret`, и завершиться с `exitCode`. [runner] и [platform] — швы для
/// бэкенда `file` и тестов Windows, [openStore] — только для тестов.
final class SecretCommands {
  SecretCommands({
    SecretProcessRunner? runner,
    @visibleForTesting String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
  }) : _platform = platform ?? Platform.operatingSystem,
       _openStore =
           openStore ??
           (({required choice, required environment, required home}) =>
               openSecretStore(
                 choice: choice,
                 environment: environment,
                 home: home,
                 logger: const SilentLogger(),
                 runner: runner,
                 platform: platform,
               ));

  final String _platform;
  final SecretStoreOpener _openStore;

  /// `set <name>`: значение только из [input] (D8, шаги 1–6).
  Future<SecretCommandResult> set(
    SecretSetOptions options,
    SecretInput input,
  ) async {
    final name = options.name;
    if (SecretNames.problem(name) case final problem?) {
      return _usage(problem);
    }
    if (options.hasValueArgument) {
      // Сам аргумент не печатается и сюда не доходит (D8, шаг 2).
      return _usage('pass the secret value on stdin, not as an argument');
    }
    final opened = _open(options.environment);
    if (opened.failure case final failure?) {
      return failure;
    }
    final session = opened.session!;
    // Имя, бэкенд только для чтения и коллизия — до чтения значения: ключ,
    // который всё равно будет отвергнут, вводить незачем (D8, шаг 3–4).
    if (await session.admin.checkStore(name) case final refusal?) {
      return _writeResult(refusal, name, session);
    }
    final String raw;
    try {
      raw =
          (input.hasTerminal
              ? await input.readHidden('Secret value for $name: ')
              : await input.readAll()) ??
          '';
    } on MultilineSecretException {
      // Вставка нескольких строк: сохранить одну из них молча было бы ошибкой
      // (D8, шаг 5).
      return session.finish(
        configUsageExit,
        stderr: ['secret value must be a single line'],
      );
    } on FormatException {
      return session.finish(
        configUsageExit,
        stderr: ['secret value must be valid UTF-8'],
      );
    }
    return _writeResult(
      await session.admin.store(name, _withoutLineEnd(raw)),
      name,
      session,
    );
  }

  /// `delete <name>`: идемпотентно, отсутствующее имя — код `0`.
  Future<SecretCommandResult> delete(SecretDeleteOptions options) async {
    final name = options.name;
    if (SecretNames.problem(name) case final problem?) {
      return _usage(problem);
    }
    final opened = _open(options.environment);
    if (opened.failure case final failure?) {
      return failure;
    }
    final session = opened.session!;
    return switch (await session.admin.delete(name)) {
      SecretDeleted(:final backend) => session.finish(
        configValidExit,
        stdout: ['Deleted secret $name from $backend'],
      ),
      SecretNotSet(:final backend) => session.finish(
        configValidExit,
        stdout: ['Secret $name was not set in $backend'],
      ),
      SecretInvalidName(:final reason) => _usage(reason),
      final SecretReadOnly readOnly => session.finish(
        configInvalidExit,
        stderr: [_readOnlyHint(readOnly, session.home)],
      ),
      SecretFailed(:final reason) => session.finish(
        configInvalidExit,
        stderr: ['cannot delete secret $name: $reason'],
      ),
    };
  }

  /// `list`: бэкенд, имена по алфавиту и имена переменных переопределения.
  Future<SecretCommandResult> list(SecretListOptions options) async {
    final opened = _open(options.environment);
    if (opened.failure case final failure?) {
      return failure;
    }
    final session = opened.session!;
    return switch (await session.admin.list()) {
      SecretListing(:final backend, :final names, :final overrides) =>
        session.finish(
          configValidExit,
          stdout: [
            backend.unavailableReason == null
                ? 'Backend: ${backend.id}'
                : 'Backend: ${backend.id} (${backend.unavailableReason})',
            ...names,
            if (overrides.isNotEmpty)
              'Environment overrides: ${overrides.join(', ')}',
          ],
        ),
      SecretListFailed(:final reason) => session.finish(
        configInvalidExit,
        stderr: ['cannot list secrets: $reason'],
      ),
    };
  }

  SecretCommandResult _writeResult(
    SecretWriteOutcome outcome,
    String name,
    _Session session,
  ) => switch (outcome) {
    SecretStored(:final backend) => session.finish(
      configValidExit,
      stdout: ['Stored secret $name in $backend'],
    ),
    SecretUpdated(:final backend) => session.finish(
      configValidExit,
      stdout: ['Updated secret $name in $backend'],
    ),
    SecretInvalidName(:final reason) => _usage(reason),
    SecretInvalidValue(:final reason) => session.finish(
      configUsageExit,
      stderr: [reason],
    ),
    SecretCollision(:final other, :final variable) => session.finish(
      configUsageExit,
      stderr: [
        'secret name $name collides with $other (both map to $variable)',
      ],
    ),
    final SecretReadOnly readOnly => session.finish(
      configInvalidExit,
      stderr: [_readOnlyHint(readOnly, session.home)],
    ),
    SecretFailed(:final reason) => session.finish(
      configInvalidExit,
      stderr: ['cannot store secret $name: $reason'],
    ),
  };

  /// Подсказка бэкенда только для чтения (D8, п. 3) с настоящим путём
  /// `$CODELAB_HOME`; на Windows `file` не предлагается (D7, D14).
  String _readOnlyHint(SecretReadOnly readOnly, String home) {
    final head = 'secret store ${readOnly.backend} is read-only.';
    return readOnly.fileBackendOffered
        ? "$head Add 'secrets.backend: file' to $home/config.yaml to store "
              'secrets in $home/secrets.yaml (plaintext, 0600), or set '
              '${readOnly.variable} in the environment'
        : '$head Set ${readOnly.variable} in the environment';
  }

  /// Отбрасывает один завершающий `\n` или `\r\n` (D8, шаг 5): второй перевод
  /// строки остаётся в значении и отвергается проверкой «одна строка».
  String _withoutLineEnd(String raw) {
    if (raw.endsWith('\r\n')) {
      return raw.substring(0, raw.length - 2);
    }
    if (raw.endsWith('\n')) {
      return raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  SecretCommandResult _usage(String message) => SecretCommandResult(
    exitCode: configUsageExit,
    stderr: [message],
    showUsage: true,
  );

  bool _isEmpty(String? value) => value == null || value.isEmpty;

  /// Читает `secrets.backend`, открывает хранилище и собирает контекст
  /// подкоманды; ошибка конфигурации или хранилища — готовый результат.
  ({_Session? session, SecretCommandResult? failure}) _open(
    Map<String, String> environment,
  ) {
    // Без CODELAB_HOME, HOME и USERPROFILE `codelabHomeOf` вернул бы
    // `./.codelab`: `secrets.yaml` лёг бы в текущий каталог (возможно, в
    // git-репозиторий). Отказ только у `secret`; `serve` не меняется
    // (ревью итерации 4).
    if (_isEmpty(environment['CODELAB_HOME']) &&
        userHomeOf(environment) == null) {
      return (
        session: null,
        failure: const SecretCommandResult(
          exitCode: configUsageExit,
          stderr: ['cannot find the home folder: set CODELAB_HOME or HOME'],
        ),
      );
    }
    final String home;
    try {
      home = codelabHomeOf(environment);
    } on ConfigUsageException catch (error) {
      return (
        session: null,
        failure: SecretCommandResult(
          exitCode: configUsageExit,
          stderr: [error.message],
        ),
      );
    }
    final choice = _backendChoice(home, environment);
    if (choice.failure case final failure?) {
      return (session: null, failure: failure);
    }
    final DescribedSecretStore store;
    try {
      store = _openStore(
        choice: choice.value,
        environment: environment,
        home: home,
      );
    } on SecretStoreUnavailableException catch (error) {
      // Недопустимое значение: тот же текст, что у `ConfigLoader`, с ключом.
      return (
        session: null,
        failure: SecretCommandResult(
          exitCode: configInvalidExit,
          stderr: ['secrets.backend: ${error.reason}'],
        ),
      );
    }
    return (
      session: _Session(
        home: home,
        store: store,
        warnings: choice.warnings,
        admin: SecretAdmin(
          store: store,
          environment: environment,
          platform: _platform,
        ),
      ),
      failure: null,
    );
  }

  /// `secrets.backend` из `$CODELAB_HOME/config.yaml`, затем из файла
  /// `CODELAB_CONFIG` (он сильнее), без остальной проверки схемы (D8).
  ///
  /// Проектные слои не читаются: подкомандам не нужен `cwd`, а проектные слои
  /// ключ и так не дают (`trust.dart`). Отсутствующий файл пропускается;
  /// нечитаемый или с синтаксической ошибкой — код `1` (`ConfigIssue`
  /// печатается так же, как у `config check`).
  ({String? value, List<String> warnings, SecretCommandResult? failure})
  _backendChoice(String home, Map<String, String> environment) {
    String? value;
    final warnings = <String>[];
    final extra = environment['CODELAB_CONFIG'];
    // Те же проверки, что у `ConfigLoader`. Нарушение — не ошибка подкоманды
    // (о ней скажет `config check`), но и молча пропускать файл нельзя:
    // пользователь не узнал бы, почему бэкенд не тот.
    final extraProblem = extra == null || extra.isEmpty
        ? null
        : _extraProblem(extra);
    if (extraProblem != null) {
      warnings.add('warning: CODELAB_CONFIG ignored: $extraProblem');
    }
    final paths = [
      ('$home/config.yaml', ConfigLayerKind.user),
      if (extra != null && extra.isNotEmpty && extraProblem == null)
        (extra, ConfigLayerKind.extra),
    ];
    for (final (path, kind) in paths) {
      if (!FileSystemEntity.isFileSync(path)) {
        continue;
      }
      final String text;
      try {
        if (File(path).statSync().size > maxConfigBytes) {
          throw const FormatException('larger than 1 MiB');
        }
        text = utf8.decode(File(path).readAsBytesSync());
      } on FileSystemException {
        return (value: null, warnings: warnings, failure: _unreadable(path));
      } on FormatException {
        return (value: null, warnings: warnings, failure: _unreadable(path));
      }
      final read = readYamlTree(text, source: path, kind: kind);
      final tree = read.tree;
      if (tree == null) {
        return (
          value: null,
          warnings: warnings,
          failure: SecretCommandResult(
            exitCode: configInvalidExit,
            stderr: [for (final issue in read.issues) '$issue'],
          ),
        );
      }
      final secrets = tree.values['secrets'];
      if (secrets is Map<String, Object?> && secrets.containsKey('backend')) {
        final backend = secrets['backend'];
        // Не строка — недопустимое значение; `openSecretStore` назовёт
        // допустимые, не цитируя ввод.
        value = backend is String ? backend : '';
      }
    }
    return (value: value, warnings: warnings, failure: null);
  }

  /// Причина, по которой `CODELAB_CONFIG` не читается, или `null`; проверки
  /// загрузчика (`checkConfigEnvPath`), без дублирования правил.
  String? _extraProblem(String extra) {
    try {
      checkConfigEnvPath(extra);
      return null;
    } on ConfigUsageException catch (error) {
      return error.message;
    }
  }

  SecretCommandResult _unreadable(String path) => SecretCommandResult(
    exitCode: configInvalidExit,
    stderr: ['cannot read the config file: $path'],
  );
}

/// Контекст одной подкоманды: каталог, хранилище и администратор.
///
/// Почему класс: `finish` добавляет к любому исходу подкоманды строку
/// `warning: secrets are stored unencrypted in <path>` при бэкенде `file`
/// (D8: каждая подкоманда, в том числе при ошибке) — в одном месте.
final class _Session {
  _Session({
    required this.home,
    required this.store,
    required this.admin,
    this.warnings = const [],
  });

  final String home;
  final DescribedSecretStore store;
  final SecretAdmin admin;

  /// Предупреждения чтения настроек (`CODELAB_CONFIG` пропущен): идут первыми.
  final List<String> warnings;

  SecretCommandResult finish(
    int exitCode, {
    List<String> stdout = const [],
    List<String> stderr = const [],
  }) => SecretCommandResult(
    exitCode: exitCode,
    stdout: stdout,
    stderr: [
      ...warnings,
      if (store.backend.id == 'file')
        'warning: secrets are stored unencrypted in $home/secrets.yaml',
      ...stderr,
    ],
  );
}
