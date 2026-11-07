import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/config_loader.dart';
import '../config/config_writer.dart' show ConfigWriteSeam;
import '../secrets/secret_process_runner.dart';
import 'config_commands.dart' show ConfigCommandResult;
import 'config_edit_runner.dart';
import 'config_output.dart' show configLayerName;
import 'exit_codes.dart';
import 'secret_commands.dart';
import 'secret_input.dart';

/// Параметры `mcp add`, уже разобранные приложением (design.md change
/// `add-config-writer-and-reload`, D6).
///
/// Почему пары `KEY=VALUE` строками: разбор пары и ответ «неверный формат» —
/// общие у `codelab-agent` и `codelab`; значение пары в текст ошибки не
/// попадает (в нём мог оказаться токен).
///
/// Как использовать: для `stdio` заданы [command], [args] и [env]; для `http`
/// — [url] и [headers]. [disabled] — `--disabled` (`enabled: false`).
/// [project] и [local] — флаги слоя; оба вместе — код `64`.
///
/// Значение секрета в параметрах отсутствует намеренно (R8-5, D11): флаги
/// [headerStdin] и [envStdin] называют только имя заголовка или переменной, а
/// само значение читается из `SecretInput`. Оба списка — потому что флаг
/// повторяемый: приложение передаёт всё, что получило, а ошибку «больше
/// одного» (код `64`) даёт общая часть, одинаково для обоих бинарей.
final class McpAddOptions {
  const McpAddOptions({
    required this.name,
    required this.cwd,
    required this.environment,
    this.type,
    this.command,
    this.args = const [],
    this.env = const [],
    this.url,
    this.headers = const [],
    this.disabled = false,
    this.project = false,
    this.local = false,
    this.headerStdin = const [],
    this.headerScheme,
    this.envStdin = const [],
  });

  /// Повторяемый `--header-stdin <Name>`: значение заголовка из stdin
  /// (только `http`). Допустим не больше одного флага `-stdin` на вызов.
  final List<String> headerStdin;

  /// `--header-scheme <Scheme>`: префикс заголовка (`Bearer`); только вместе с
  /// `--header-stdin`. В хранилище лежит один токен, схема остаётся в конфиге.
  final String? headerScheme;

  /// Повторяемый `--env-stdin <NAME>`: значение переменной из stdin (только
  /// `stdio`).
  final List<String> envStdin;

  /// Имя сервера: ключ `mcp.servers[<name>]`.
  final String name;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса (`CODELAB_HOME` и др.).
  final Map<String, String> environment;

  /// `--type`: `stdio` или `http`.
  final String? type;

  /// `--command` (только `stdio`).
  final String? command;

  /// Повторяемый `--arg` (только `stdio`).
  final List<String> args;

  /// Повторяемый `--env KEY=VALUE` (только `stdio`).
  final List<String> env;

  /// `--url` (только `http`).
  final String? url;

  /// Повторяемый `--header KEY=VALUE` (только `http`).
  final List<String> headers;

  /// `--disabled`.
  final bool disabled;

  /// `--project`: писать в `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: писать в `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Параметры `mcp list`.
final class McpListOptions {
  const McpListOptions({required this.cwd, required this.environment});

  /// Каталог проекта, для которого загружается конфиг.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME`.
  final Map<String, String> environment;
}

/// Параметры `mcp remove <name>`. Оба флага слоя — код `64`.
final class McpRemoveOptions {
  const McpRemoveOptions({
    required this.name,
    required this.cwd,
    required this.environment,
    this.project = false,
    this.local = false,
  });

  /// Имя удаляемого сервера (только по `name`, не по номеру).
  final String name;

  /// Каталог проекта для слоёв `project` и `local`.
  final String cwd;

  /// Переменные процесса: `CODELAB_HOME` и др.
  final Map<String, String> environment;

  /// `--project`: править `<cwd>/.codelab/config.yaml`.
  final bool project;

  /// `--local`: править `<cwd>/.codelab/config.local.yaml`.
  final bool local;
}

/// Общая реализация подкоманд `mcp add|list|remove` для `codelab-agent` и
/// `codelab` (design.md change `add-config-writer-and-reload`, D6).
///
/// Почему `McpServerCommands`, а не `McpCommands`: чтобы не путать с
/// агентской командой `/mcp` (D12).
///
/// Для чего: правит список `mcp.servers` файла слоя через `ConfigWriter`
/// (`UpsertMcpServer`, `RemoveMcpServer`) и показывает серверы файлов без
/// подключения к ним. Литеральный токен в заголовке или `env` писатель
/// отклоняет с подсказкой `${secret:codelab/mcp/<server>/<key>}` (код `1`).
///
/// Как использовать: `await McpServerCommands().add(options)` и аналогично
/// `list`/`remove`; напечатать `stdout`/`stderr` и завершиться с `exitCode`.
final class McpServerCommands {
  McpServerCommands({
    @visibleForTesting SecretProcessRunner? processRunner,
    @visibleForTesting Clock? clock,
    @visibleForTesting Random? random,
    @visibleForTesting String? platform,
    @visibleForTesting SecretStoreOpener? openStore,
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
  }) : _platform = platform ?? Platform.operatingSystem,
       // Швы тестов `platform` и `openStore` передаются дальше без изменений.
       _secrets = SecretCommands(
         runner: processRunner,
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
  final SecretCommands _secrets;
  final ConfigEditRunner _runner;

  /// `add`: добавляет сервер или заменяет одноимённый на месте (D6).
  ///
  /// Ошибки использования (код `64`): нет или неизвестен `--type`, нет
  /// `--command` у `stdio` или `--url` у `http`, флаги чужого типа, пара без
  /// `=`.
  ///
  /// Флаги `--header-stdin`/`--env-stdin` (R8-5, D11) сохраняют секрет в
  /// хранилище под `SecretNames.forMcp(<server>, <ключ>)` и пишут в файл
  /// только ссылку `${secret:<имя>}`; значение читается из [input]
  /// (по умолчанию `StdinSecretInput`). Порядок как у
  /// `provider add --api-key-stdin`: кандидат без записи, проверка
  /// коллизии имени, `SecretCommands.set` (проверка хранилища, чтение,
  /// сохранение), одна атомарная запись. Сбой записи после сохранения — код
  /// `1`, stderr называет сохранённое имя.
  Future<ConfigCommandResult> add(
    McpAddOptions options, [
    SecretInput? input,
  ]) async {
    ConfigCommandResult usage(String message) => ConfigCommandResult(
      exitCode: configUsageExit,
      stderr: ['mcp add: $message'],
    );
    if (!isValidMcpServerName(options.name)) {
      return usage('the server name must not contain whitespace, [, ] or "');
    }
    // Один флаг `-stdin` на вызов: stdin один, два значения потребовали бы
    // протокола разделителей, неоднозначного при скрытом вводе (D11).
    if (options.headerStdin.length + options.envStdin.length > 1) {
      return usage(
        'only one of --header-stdin, --env-stdin can be used per call',
      );
    }
    if (options.headerScheme != null && options.headerStdin.isEmpty) {
      return usage('--header-scheme requires --header-stdin');
    }
    final type = options.type;
    final server = <String, Object?>{'name': options.name};
    // Ключ заголовка или переменной, значение которого придёт из stdin.
    String? stdinKey;
    switch (type) {
      case 'stdio':
        if ((options.command ?? '').isEmpty) {
          return usage('--command is required for --type stdio');
        }
        if (options.url != null || options.headers.isNotEmpty) {
          return usage('--url and --header are for --type http');
        }
        if (options.headerStdin.isNotEmpty) {
          return usage('--header-stdin is for --type http');
        }
        final env = _pairs(options.env);
        if (env == null) {
          return usage('--env expects KEY=VALUE');
        }
        stdinKey = options.envStdin.isEmpty ? null : options.envStdin.single;
        if (stdinKey != null) {
          if (_stdinKeyProblem(stdinKey, '--env-stdin') case final problem?) {
            return usage(problem);
          }
          if (env.containsKey(stdinKey)) {
            return usage('--env-stdin name is also set by --env');
          }
          env[stdinKey] = _reference(options.name, stdinKey, null);
        }
        server
          ..['type'] = 'stdio'
          ..['command'] = options.command;
        if (options.args.isNotEmpty) {
          server['args'] = options.args;
        }
        if (env.isNotEmpty) {
          server['env'] = env;
        }
      case 'http':
        if ((options.url ?? '').isEmpty) {
          return usage('--url is required for --type http');
        }
        if (options.command != null ||
            options.args.isNotEmpty ||
            options.env.isNotEmpty) {
          return usage('--command, --arg and --env are for --type stdio');
        }
        if (options.envStdin.isNotEmpty) {
          return usage('--env-stdin is for --type stdio');
        }
        final headers = _pairs(options.headers);
        if (headers == null) {
          return usage('--header expects KEY=VALUE');
        }
        stdinKey = options.headerStdin.isEmpty
            ? null
            : options.headerStdin.single;
        if (stdinKey != null) {
          if (_stdinKeyProblem(stdinKey, '--header-stdin')
              case final problem?) {
            return usage(problem);
          }
          // Заголовки регистронезависимы (RFC 9110): `authorization` и
          // `Authorization` — один заголовок.
          final lower = stdinKey.toLowerCase();
          if (headers.keys.any((key) => key.toLowerCase() == lower)) {
            return usage('--header-stdin name is also set by --header');
          }
          final scheme = options.headerScheme;
          if (scheme != null && !_schemeFormat.hasMatch(scheme)) {
            return usage(
              '--header-scheme must be a token of letters, digits and '
              "!#%&'*+.^_`|~- (RFC 9110)",
            );
          }
          headers[stdinKey] = _reference(options.name, stdinKey, scheme);
        }
        server
          ..['type'] = 'http'
          ..['url'] = options.url;
        if (headers.isNotEmpty) {
          server['headers'] = headers;
        }
      case null:
        return usage('--type is required (stdio or http)');
      default:
        return usage('--type must be stdio or http');
    }
    if (options.disabled) {
      server['enabled'] = false;
    }
    List<ConfigEdit> editsFor(ConfigSnapshot _) => [UpsertMcpServer(server)];

    var secretStdout = const <String>[];
    var secretStderr = const <String>[];
    final secretName = stdinKey == null
        ? null
        : SecretNames.forMcp(options.name, stdinKey);
    if (secretName != null) {
      // Шаг 1 D11: итог проверяется без записи, чтобы заведомо негодную
      // правку не предварял ввод и сохранение секрета.
      final check = await _runner.apply(
        label: 'mcp add',
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
      // Коллизия имени: молчаливая замена чужого секрета увела бы токен
      // другого сервера или провайдера (D11, Risks «Межсерверная коллизия»).
      final conflict = _nameConflict(options, secretName, stdinKey!);
      if (conflict != null) {
        return conflict;
      }
      // Шаги 2–4: проверка хранилища, чтение и сохранение — та же
      // последовательность и те же тексты, что у `secret set`.
      final stored = await _secrets.set(
        SecretSetOptions(name: secretName, environment: options.environment),
        input ?? StdinSecretInput(),
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
        label: 'mcp add',
        environment: options.environment,
        cwd: options.cwd,
        project: options.project,
        local: options.local,
        edits: editsFor,
      );
    } on Object catch (error) {
      if (secretName == null) {
        rethrow;
      }
      // Защитный рубеж шага 5: секрет уже в хранилище, и пользователь должен
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
        if (secretName == null) {
          return result;
        }
        // Секрет остаётся в хранилище: без ссылки он безвреден, а повтор
        // команды заменит его (D11).
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
            'Updated mcp.servers[${options.name}] in ${result.path}',
            ...ConfigEditRunner.successLines(result),
          ],
          stderr: secretStderr,
        );
    }
  }

  /// Схема заголовка (`Bearer`): без пробелов и `$`, чтобы значение
  /// `"<схема> ${secret:…}"` не превратилось во что-то иное.
  /// Схема авторизации — `token` RFC 9110 без `$` (D11): иначе значение
  /// заголовка могло бы нести подстановку или разделитель.
  static final _schemeFormat = RegExp(r"^[!#%&'*+.^_`|~0-9A-Za-z-]+$");

  /// Значение `headers.<Name>` или `env.<NAME>`: только ссылка на секрет, при
  /// заданной [scheme] — с префиксом (`Bearer ${secret:…}`).
  static String _reference(String server, String key, String? scheme) {
    final ref = '\${secret:${SecretNames.forMcp(server, key)}}';
    return scheme == null ? ref : '$scheme $ref';
  }

  /// Проблема имени заголовка или переменной из `-stdin` (текст без самого
  /// имени: в поле имени часто вписывают сам токен, D6, D11).
  static String? _stdinKeyProblem(String key, String flag) {
    if (key.isEmpty) {
      return '$flag expects a name';
    }
    if (literalSecretTag(key) != null) {
      return '$flag expects a header or variable name, not a secret value';
    }
    return null;
  }

  /// Ссылка `${secret:<имя>}` в значениях конфига.
  static final _secretReference = RegExp(r'\$\{secret:([^}$]{1,200})\}');

  /// Отказ (код `1`) при коллизии имени [secretName] до чтения stdin или
  /// `null` (D11, Risks «Межсерверная коллизия имён»).
  ///
  /// Два случая: имя упомянуто в загруженном конфиге (`${secret:…}` или
  /// `api_key_secret`) другим сервером или провайдером, либо `forMcp` другого
  /// сервера конфига с тем же ключом даёт то же имя (`GH`/`gh`). Собственное
  /// имя сервера не считается (повторный `mcp add`). Ошибка загрузки слоёв
  /// здесь не отказ: итог уже проверен `dryRun`.
  ConfigCommandResult? _nameConflict(
    McpAddOptions options,
    String secretName,
    String key,
  ) {
    final List<ConfigTree> layers;
    try {
      layers = ConfigLoader()
          .loadWithLayers(
            cwd: options.cwd,
            environment: options.environment,
            platform: _platform,
          )
          .layers;
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['mcp add: ${error.message}'],
      );
    }
    String? owner;
    void refs(String path, Object? node) {
      if (owner != null) {
        return;
      }
      switch (node) {
        case final String text:
          final isName = path.endsWith('.api_key_secret') && text == secretName;
          if (isName ||
              _secretReference
                  .allMatches(text)
                  .any((m) => m.group(1) == secretName)) {
            owner = path;
          }
        case final Map<Object?, Object?> map:
          for (final MapEntry(:key, :value) in map.entries) {
            refs('$path.$key', value);
          }
        case final List<Object?> list:
          for (var i = 0; i < list.length; i++) {
            refs('$path[$i]', list[i]);
          }
      }
    }

    for (final layer in layers) {
      final providers = layer.values['providers'];
      if (providers is Map<Object?, Object?>) {
        for (final MapEntry(key: id, value: body) in providers.entries) {
          refs('providers.$id', body);
        }
      }
      final mcp = layer.values['mcp'];
      final servers = mcp is Map<Object?, Object?> ? mcp['servers'] : null;
      if (servers is! List<Object?>) {
        continue;
      }
      for (final element in servers) {
        if (element is! Map<Object?, Object?>) {
          continue;
        }
        final other = element['name'];
        if (other is! String || other == options.name) {
          continue;
        }
        refs('mcp.servers[$other]', element);
        if (owner == null && SecretNames.forMcp(other, key) == secretName) {
          owner = 'mcp.servers[$other]';
        }
      }
    }
    if (owner case final used?) {
      return ConfigCommandResult(
        exitCode: configInvalidExit,
        stderr: [
          'secret $secretName is already used by $used; store the value '
              'with codelab secret set <another name> and reference it with '
              '--header/--env',
        ],
      );
    }
    return null;
  }

  /// `list`: серверы файлов по слоям — имя, тип, слой, `enabled` (D6). К
  /// серверам подключения нет, значения `env` и заголовков не читаются и не
  /// печатаются.
  Future<ConfigCommandResult> list(McpListOptions options) async {
    if (!Directory(options.cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['mcp list: no such directory: ${options.cwd}'],
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
        stderr: ['mcp list: ${error.message}'],
      );
    }
    final syntax = [
      for (final issue in loaded.result.issues)
        if (issue.kind == ConfigIssueKind.syntax) '$issue',
    ];
    if (syntax.isNotEmpty) {
      return ConfigCommandResult(exitCode: configInvalidExit, stderr: syntax);
    }
    final lines = <String>[];
    for (final layer in loaded.layers) {
      final servers = (layer.values['mcp'] as Map?)?['servers'];
      if (servers is! List<Object?>) {
        continue;
      }
      for (final server in servers) {
        if (server is! Map || server['name'] is! String) {
          continue;
        }
        lines.add(
          '${server['name']}  type: ${server['type']}  '
          'layer: ${configLayerName(layer.kind)}  '
          'enabled: ${server['enabled'] != false}',
        );
      }
    }
    return ConfigCommandResult(exitCode: configValidExit, stdout: lines);
  }

  /// `remove`: удаляет сервер по имени (`RemoveMcpServer`, D6). Сервера в
  /// файле нет — код `0` без записи. Недопустимое имя — код `64`.
  Future<ConfigCommandResult> remove(McpRemoveOptions options) async {
    // Имя проверяется как у `add`: `a]` или `a b` не должны превратиться в
    // чужой путь `mcp.servers[…]`.
    if (!isValidMcpServerName(options.name)) {
      return const ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: [
          'mcp remove: the server name must not contain whitespace, [, ] or "',
        ],
      );
    }
    final key = 'mcp.servers[${options.name}]';
    final outcome = await _runner.apply(
      label: 'mcp remove',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [RemoveMcpServer(options.name)],
      // Только по `name`: `mcp remove 0` не затрагивает первый сервер.
      shortCircuit: (snapshot) =>
          configKeyPresent(snapshot, key, byNumber: false)
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

  /// Пары `KEY=VALUE` в отображение; `null` — пара без `=` или с пустым
  /// ключом. Делится по первому `=`: значение может содержать `=`.
  Map<String, String>? _pairs(List<String> pairs) {
    final out = <String, String>{};
    for (final pair in pairs) {
      final eq = pair.indexOf('=');
      if (eq <= 0) {
        return null;
      }
      out[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return out;
  }
}
