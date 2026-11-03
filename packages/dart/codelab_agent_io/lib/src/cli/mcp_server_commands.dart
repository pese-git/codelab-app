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
  });

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
    @visibleForTesting Future<void> Function(ConfigWriteSeam point)? writeSeam,
  }) : _platform = platform ?? Platform.operatingSystem,
       _runner = ConfigEditRunner(
         processRunner: processRunner,
         clock: clock,
         random: random,
         platform: platform,
         seam: writeSeam,
       );

  final String _platform;
  final ConfigEditRunner _runner;

  /// Имя не должно ломать запись пути `mcp.servers[<name>]`.
  static final _nameFormat = RegExp(r'^[^\s\[\]"]+$');

  /// `add`: добавляет сервер или заменяет одноимённый на месте (D6).
  ///
  /// Ошибки использования (код `64`): нет или неизвестен `--type`, нет
  /// `--command` у `stdio` или `--url` у `http`, флаги чужого типа, пара без
  /// `=`.
  Future<ConfigCommandResult> add(McpAddOptions options) async {
    ConfigCommandResult usage(String message) => ConfigCommandResult(
      exitCode: configUsageExit,
      stderr: ['mcp add: $message'],
    );
    if (!_nameFormat.hasMatch(options.name)) {
      return usage('the server name must not contain whitespace, [, ] or "');
    }
    final type = options.type;
    final server = <String, Object?>{'name': options.name};
    switch (type) {
      case 'stdio':
        if ((options.command ?? '').isEmpty) {
          return usage('--command is required for --type stdio');
        }
        if (options.url != null || options.headers.isNotEmpty) {
          return usage('--url and --header are for --type http');
        }
        final env = _pairs(options.env);
        if (env == null) {
          return usage('--env expects KEY=VALUE');
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
        final headers = _pairs(options.headers);
        if (headers == null) {
          return usage('--header expects KEY=VALUE');
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
    final outcome = await _runner.apply(
      label: 'mcp add',
      environment: options.environment,
      cwd: options.cwd,
      project: options.project,
      local: options.local,
      edits: (_) => [UpsertMcpServer(server)],
    );
    return switch (outcome) {
      EditFinished(:final result) => result,
      EditWritten(:final result) => ConfigCommandResult(
        exitCode: configValidExit,
        stdout: [
          'Updated mcp.servers[${options.name}] in ${result.path}',
          ...ConfigEditRunner.successLines(result),
        ],
      ),
    };
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
    if (!_nameFormat.hasMatch(options.name)) {
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
