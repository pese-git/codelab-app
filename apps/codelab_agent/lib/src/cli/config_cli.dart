import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        CheckOptions,
        ConfigCommands,
        ConfigGetLayer,
        ConfigGetOptions,
        ConfigPathOptions,
        ConfigSetOptions,
        ConfigUnsetOptions;

import 'write_cli_support.dart';

const _cwdHelp =
    'Project directory for the project and local layers '
    '(default: current).';

/// Парсер команды `config` (design.md change `add-agent-configuration`, D13;
/// `add-config-writer-and-reload`, D6).
///
/// Почему отдельный файл: `serve_args.dart` и так велик, а `config`
/// регистрируется рядом с `serve` в одном верхнем парсере (`addCommand`) и не
/// добавляет условий в разбор `serve`. Подкоманды: `check`, `path`, `get`,
/// `set`, `unset`; `migrate` и прочее не регистрируются (agent-binary
/// «Подкоманда config бинаря»).
final ArgParser configParser = ArgParser()
  ..addCommand(
    'check',
    ArgParser()..addOption(
      'cwd',
      help: 'Project directory to load config for (default: current).',
    ),
  )
  ..addCommand(
    'path',
    withLayerFlags(ArgParser()..addOption('cwd', help: _cwdHelp)),
  )
  ..addCommand(
    'get',
    ArgParser()
      ..addOption(
        'layer',
        allowed: [for (final layer in ConfigGetLayer.values) layer.name],
        help: 'Layer to read (default: the winning layer of all).',
      )
      ..addOption('cwd', help: _cwdHelp),
  )
  ..addCommand(
    'set',
    withLayerFlags(ArgParser()..addOption('cwd', help: _cwdHelp)),
  )
  ..addCommand(
    'unset',
    withLayerFlags(ArgParser()..addOption('cwd', help: _cwdHelp)),
  );

/// Справка команды `config` (в stderr при коде `64`).
String configUsage() =>
    'Usage: codelab-agent config check [--cwd <dir>]\n'
    '       codelab-agent config path [--project | --local] [--cwd <dir>]\n'
    '       codelab-agent config get <key> '
    '[--layer user|project|local|merged] [--cwd <dir>]\n'
    '       codelab-agent config set <key> <value> '
    '[--project | --local] [--cwd <dir>]\n'
    '       codelab-agent config unset <key> '
    '[--project | --local] [--cwd <dir>]\n\n'
    '`check` loads the configuration like `serve` does and prints sources, '
    'issues and warnings. `get` prints the raw value of a key and its layer '
    '(references like \${VAR} are not expanded, secret-like values are '
    'masked). `set` and `unset` edit one config file in place and keep its '
    'comments. Nothing prints secret values.';

/// Выполняет `codelab-agent config …` и возвращает код выхода.
///
/// Как использовать: [config] — результат разбора команды `config` верхним
/// парсером. Без подкоманды, с неизвестной подкомандой или неверным числом
/// аргументов — справка в stderr и код `64`. Тексты и коды даёт общий
/// `ConfigCommands` (D13, D6): `codelab config …` печатает то же. Токены argv не
/// цитируются: среди них может быть значение секрета (agent-secrets; D8).
/// [commands] — шов тестов.
Future<int> runConfigCommand(
  ArgResults config, {
  required Map<String, String> environment,
  required String cwd,
  required IOSink out,
  required IOSink err,
  ConfigCommands? commands,
}) async {
  final sub = config.command;
  if (sub == null) {
    return usageFailure(
      err,
      config.rest.isEmpty
          ? 'config needs a subcommand: check, path, get, set or unset'
          : 'unknown config arguments (${config.rest.length})',
      configUsage(),
    );
  }
  final wanted = switch (sub.name) {
    'get' || 'unset' => 1,
    'set' => 2,
    _ => 0,
  };
  if (sub.rest.length != wanted) {
    return usageFailure(
      err,
      sub.rest.length > wanted
          ? 'unknown config arguments (${sub.rest.length - wanted})'
          : 'config ${sub.name} needs ${wanted == 1 ? 'a key' : 'a key and a value'}',
      configUsage(),
    );
  }
  final service = commands ?? ConfigCommands();
  final dir = sub.option('cwd') ?? cwd;
  if (sub.name == 'check') {
    return printResult(
      await service.check(CheckOptions(cwd: dir, environment: environment)),
      out,
      err,
    );
  }
  if (sub.name == 'get') {
    return printResult(
      await service.get(
        ConfigGetOptions(
          key: sub.rest.single,
          cwd: dir,
          environment: environment,
          layer: ConfigGetLayer.parse(sub.option('layer')),
        ),
      ),
      out,
      err,
    );
  }
  return printResult(
    switch (sub.name) {
      'path' => await service.path(
        ConfigPathOptions(
          cwd: dir,
          environment: environment,
          // Без флагов — все слои; флаг выбирает один (D6).
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      'set' => await service.set(
        ConfigSetOptions(
          key: sub.rest[0],
          value: sub.rest[1],
          cwd: dir,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
      _ => await service.unset(
        ConfigUnsetOptions(
          key: sub.rest.single,
          cwd: dir,
          environment: environment,
          project: sub.flag('project'),
          local: sub.flag('local'),
        ),
      ),
    },
    out,
    err,
  );
}
