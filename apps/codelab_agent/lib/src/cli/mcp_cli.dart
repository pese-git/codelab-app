import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show McpAddOptions, McpListOptions, McpRemoveOptions, McpServerCommands;

import 'write_cli_support.dart';

/// Парсер команды `mcp` (design.md change `add-config-writer-and-reload`, D6).
///
/// Почему отдельный файл: как `provider_cli.dart`, команда регистрируется
/// рядом с `serve` и не добавляет условий в разбор `serve`. Это правка
/// *файлов* конфига; агентская команда `/mcp` (D12) — другое.
final ArgParser mcpParser = ArgParser()
  ..addCommand(
    'add',
    withLayerFlags(
      ArgParser()
        ..addOption('type', help: 'stdio or http.')
        ..addOption('command', help: 'Executable of a stdio server.')
        ..addMultiOption(
          'arg',
          splitCommas: false,
          help: 'Argument of a stdio server; repeat for more.',
        )
        ..addMultiOption(
          'env',
          splitCommas: false,
          help: 'KEY=VALUE variable of a stdio server; repeat for more.',
        )
        ..addOption('url', help: 'Address of an http server.')
        ..addMultiOption(
          'header',
          splitCommas: false,
          help: 'KEY=VALUE header of an http server; repeat for more.',
        )
        ..addFlag(
          'disabled',
          negatable: false,
          help: 'Write the server with enabled: false.',
        ),
    ),
  )
  ..addCommand(
    'list',
    ArgParser()..addOption(
      'cwd',
      help: 'Project directory to load config for (default: current).',
    ),
  )
  ..addCommand('remove', withLayerFlags(ArgParser()));

/// Справка команды `mcp` (в stderr при коде `64`).
String mcpUsage() =>
    'Usage: codelab-agent mcp add <name> --type stdio --command <cmd> '
    '[--arg <a>]... [--env KEY=VALUE]...\n'
    '       codelab-agent mcp add <name> --type http --url <url> '
    '[--header KEY=VALUE]...\n'
    '           [--disabled] [--project | --local]\n'
    '       codelab-agent mcp list [--cwd <dir>]\n'
    '       codelab-agent mcp remove <name> [--project | --local]\n\n'
    'Edits the config file in place; it does not connect to servers. Put '
    r'secrets in headers and variables as ${secret:name} or ${VAR}.';

/// Выполняет `codelab-agent mcp …` и возвращает код выхода.
///
/// Как использовать: [mcp] — результат разбора команды `mcp` верхним
/// парсером. Без подкоманды, с неизвестной подкомандой или неверным числом
/// аргументов — справка в stderr и код `64`; остальное даёт общий
/// `McpServerCommands`. Значения `--env` и `--header` не цитируются.
Future<int> runMcpCommand(
  ArgResults mcp, {
  required Map<String, String> environment,
  required String cwd,
  required IOSink out,
  required IOSink err,
  McpServerCommands? commands,
}) async {
  final sub = mcp.command;
  if (sub == null) {
    return usageFailure(
      err,
      mcp.rest.isEmpty
          ? 'mcp needs a subcommand: add, list or remove'
          : 'unknown mcp arguments (${mcp.rest.length})',
      mcpUsage(),
    );
  }
  final wanted = sub.name == 'list' ? 0 : 1;
  if (sub.rest.length != wanted) {
    return usageFailure(
      err,
      sub.rest.length > wanted
          ? 'unknown mcp arguments (${sub.rest.length - wanted})'
          : 'mcp ${sub.name} needs the server name',
      mcpUsage(),
    );
  }
  final service = commands ?? McpServerCommands();
  if (sub.name == 'list') {
    return printResult(
      await service.list(
        McpListOptions(cwd: sub.option('cwd') ?? cwd, environment: environment),
      ),
      out,
      err,
    );
  }
  if (sub.name == 'remove') {
    return printResult(
      await service.remove(
        McpRemoveOptions(
          name: sub.rest.single,
          cwd: cwd,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      out,
      err,
    );
  }
  return printResult(
    await service.add(
      McpAddOptions(
        name: sub.rest.single,
        cwd: cwd,
        environment: environment,
        type: sub.option('type'),
        command: sub.option('command'),
        args: sub.multiOption('arg'),
        env: sub.multiOption('env'),
        url: sub.option('url'),
        headers: sub.multiOption('header'),
        disabled: sub.flag('disabled'),
        project: sub.flag('project'),
        local: sub.flag('local'),
      ),
    ),
    out,
    err,
  );
}
