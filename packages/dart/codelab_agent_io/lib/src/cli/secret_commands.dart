import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/config_writer.dart' show ConfigWriteSeam;
import '../config/yaml_reader.dart';
import '../secrets/open_secret_store.dart';
import '../secrets/secret_admin.dart';
import '../secrets/secret_migrator.dart';
import '../secrets/secret_process_runner.dart';
import '../secrets/secret_read_only_hint.dart';
import 'exit_codes.dart';
import 'secret_input.dart';
import '../util/silent_logger.dart';

// Тип перенесён в `open_secret_store.dart`, чтобы `SecretMigrator` (слой
// `secrets/`) не импортировал `cli/`; прежние импорты `show SecretStoreOpener`
// из этого файла продолжают работать.
export '../secrets/open_secret_store.dart' show SecretStoreOpener;

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

  /// Имя секрета из первого позиционного аргумента. Проверяется
  /// `SecretNames.problem` внутри `SecretCommands.set`, поэтому приложению
  /// достаточно передать строку как есть: неверное имя даёт код `64` и
  /// справку, а не исключение разбора.
  final String name;

  /// Переменные процесса: из них берутся `CODELAB_HOME`, `CODELAB_CONFIG`,
  /// `CODELAB_SECRET_*`. В `toString` не попадают. Приложение передаёт
  /// `Platform.environment`, тест — явную карту (настоящий `~/.codelab`
  /// тесты не читают).
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

  /// Имя удаляемого секрета; неверное имя — код `64` со справкой, а не
  /// исключение. Отсутствующее в хранилище имя — не ошибка (идемпотентность).
  final String name;

  /// Переменные процесса: `CODELAB_HOME`, `CODELAB_CONFIG` и настройки
  /// бэкенда. Приложение передаёт `Platform.environment`, тест — явную карту.
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

  /// Переменные процесса: из них берутся `CODELAB_HOME`, `CODELAB_CONFIG` и
  /// имена (не значения) заданных `CODELAB_SECRET_*`, которые `list` печатает
  /// отдельной строкой. Приложение передаёт `Platform.environment`.
  final Map<String, String> environment;
}

/// Параметры `secret migrate`, уже разобранные приложением (design.md change
/// `add-config-literal-secrets-and-migrate`, D7).
///
/// Почему отдельный тип: разбор argv — дело `package:args` каждого
/// приложения, общая часть получает типизированный вход, одинаковый у
/// `codelab` и `codelab-agent`. Значения секретов в параметрах нет вовсе:
/// движок читает их из файлов конфига, stdin не читается.
///
/// Как использовать: флаги слоёв как есть из argv — [project], [local],
/// [all]; без них переносится слой `user`. [all] вместе с [project] или
/// [local] — ошибка использования (`64`). [cwd] — значение `--cwd` либо
/// каталог процесса; [dryRun] — только план; [force] — заменить секрет с
/// другим значением (безвозвратно).
final class SecretMigrateOptions {
  const SecretMigrateOptions({
    required this.environment,
    required this.cwd,
    this.project = false,
    this.local = false,
    this.all = false,
    this.dryRun = false,
    this.force = false,
  });

  /// Переменные процесса (`CODELAB_HOME`, `CODELAB_CONFIG`, `CODELAB_SECRET_*`);
  /// в `toString` не попадают.
  final Map<String, String> environment;

  /// Корень проекта для слоёв `project` и `local` и для доверия проекту.
  final String cwd;

  /// `--project`: перенести секреты слоя `project` (вместо `user`).
  final bool project;

  /// `--local`: перенести секреты слоя `local` (вместо `user`).
  final bool local;

  /// `--all`: перенести все слои сразу; несовместим с [project] и [local]
  /// (ошибка использования, код `64`).
  final bool all;

  /// `--dry-run`: только план и отчёт, файлы конфига и хранилище не меняются.
  final bool dryRun;

  /// `--force`: заменить уже сохранённый секрет с другим значением;
  /// безвозвратно, поэтому по умолчанию выключено.
  final bool force;
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
    this.replaced = false,
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

  /// `set` заменил уже существовавший секрет (`SecretUpdated`). Нужен
  /// `provider add --api-key-stdin`: он печатает предупреждение о замене
  /// (design.md change `add-config-writer-and-reload`, D6), не разбирая
  /// текст `stdout`.
  final bool replaced;
}

/// Общая реализация подкоманд `secret set|delete|list|migrate` для `codelab-agent` и
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
/// StdinSecretInput())` (аналогично [delete], [list], [migrate]); напечатать `stdout` и
/// `stderr` результата, при [SecretCommandResult.showUsage] — ещё справку
/// `secret`, и завершиться с `exitCode`. [runner] и [platform] — швы для
/// бэкенда `file` и тестов Windows, [openStore] — только для тестов.
final class SecretCommands {
  SecretCommands({
    SecretProcessRunner? runner,
    @visibleForTesting String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
  }) : _runnerArg = runner,
       _writeSeam = writeSeam,
       _platform = platform ?? Platform.operatingSystem,
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

  final SecretProcessRunner? _runnerArg;
  final Future<void> Function(ConfigWriteSeam point)? _writeSeam;
  final String _platform;
  final SecretStoreOpener _openStore;

  /// `set <name>`: значение только из [input] (D8, шаги 1–6).
  Future<SecretCommandResult> set(
    SecretSetOptions options,
    SecretInput input,
  ) async {
    final name = options.name;
    if (_nameProblem(name) case final problem?) {
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
    if (_nameProblem(name) case final problem?) {
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
        stderr: [secretReadOnlyHint(readOnly, session.home)],
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

  /// `migrate`: переносит литеральные секреты файлов конфига в хранилище
  /// (agent-secrets «Подкоманда secret migrate»; design.md change
  /// `add-config-literal-secrets-and-migrate`, D7).
  ///
  /// Почему здесь только обёртка: находки, имена, порядок записи и атомарность
  /// принадлежат [SecretMigrator], который вызывает и codelab-app (D8); здесь
  /// флаги слоёв, печать отчёта строками и общий для подкоманд `secret`
  /// `warning: secrets are stored unencrypted in …`. Stdin не читается,
  /// значения секретов в результат не попадают.
  Future<SecretCommandResult> migrate(SecretMigrateOptions options) async {
    if (options.all && (options.project || options.local)) {
      return _usage(
        'secret migrate: --all cannot be combined with --project or --local',
      );
    }
    final layers = options.all
        ? const {
            ConfigLayer.user,
            ConfigLayer.project,
            ConfigLayer.projectLocal,
          }
        : options.project || options.local
        ? {
            if (options.project) ConfigLayer.project,
            if (options.local) ConfigLayer.projectLocal,
          }
        : const {ConfigLayer.user};
    final report =
        await SecretMigrator(
          processRunner: _runnerArg,
          platform: _platform,
          // Швы тестов `SecretCommands` пробрасываются движку; в рабочем коде
          // это `openSecretStore` и `null`.
          // ignore: invalid_use_of_visible_for_testing_member
          openStore: _openStore,
          // ignore: invalid_use_of_visible_for_testing_member
          writeSeam: _writeSeam,
        ).run(
          SecretMigrationOptions(
            cwd: options.cwd,
            environment: options.environment,
            layers: layers,
            dryRun: options.dryRun,
            force: options.force,
          ),
        );
    return SecretCommandResult(
      exitCode: report.exitCode,
      showUsage: report.showUsage,
      stdout: report.stdoutLines,
      stderr: [
        ...report.warnings,
        // Как у `_Session.finish`: каждая подкоманда при бэкенде `file`,
        // в том числе при ошибке (D8 change `add-agent-secret-store`).
        if (report.backendId == 'file')
          'warning: secrets are stored unencrypted in '
              '${codelabHomeOf(options.environment)}/secrets.yaml',
        ...report.problems,
      ],
    );
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
      replaced: true,
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
      stderr: [secretReadOnlyHint(readOnly, session.home)],
    ),
    SecretFailed(:final reason) => session.finish(
      configInvalidExit,
      stderr: ['cannot store secret $name: $reason'],
    ),
  };

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

  /// Проблема имени для `set` и `delete`: сначала «имя похоже на значение»,
  /// затем правила `SecretNames` (design.md change
  /// `add-config-literal-secrets-and-migrate`, D6).
  ///
  /// Почему порядок: токен, вставленный вместо имени, обычно нарушает и
  /// правила имён (регистр), но подсказка «передайте значение через stdin»
  /// полезнее общей фразы о формате. Текст не содержит имени (оно могло быть
  /// ключом), а `SecretNames.problem` не меняется. Хранилище до этой проверки
  /// не открывается.
  String? _nameProblem(String name) {
    if (literalSecretTag(name) != null) {
      return 'the secret name looks like a secret value; pass the value on '
          'stdin';
    }
    return SecretNames.problem(name);
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
    bool replaced = false,
  }) => SecretCommandResult(
    exitCode: exitCode,
    replaced: replaced,
    stdout: stdout,
    stderr: [
      ...warnings,
      if (store.backend.id == 'file')
        'warning: secrets are stored unencrypted in $home/secrets.yaml',
      ...stderr,
    ],
  );
}
