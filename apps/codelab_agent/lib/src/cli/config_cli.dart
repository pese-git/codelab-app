import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show CheckOptions, ConfigCommands;

import '../serve/exit_codes.dart';

/// Парсер команды `config` (design.md change `add-agent-configuration`, D13).
///
/// Почему отдельный файл: `serve_args.dart` и так велик, а `config`
/// регистрируется рядом с `serve` в одном верхнем парсере (`addCommand`) и не
/// добавляет условий в разбор `serve`. Единственная подкоманда — `check`;
/// `set`, `migrate` и прочее не регистрируются (agent-binary «Подкоманда
/// config бинаря»): запись конфига — не часть этого change.
final ArgParser configParser = ArgParser()
  ..addCommand(
    'check',
    ArgParser()..addOption(
      'cwd',
      help: 'Project directory to load config for (default: current).',
    ),
  );

/// Справка команды `config` (в stderr при коде `64`).
String configUsage() =>
    'Usage: codelab-agent config check [--cwd <dir>]\n\n'
    'Loads the configuration like `serve` does and prints sources, issues '
    'and warnings. It never writes files and never prints secret values.';

/// Выполняет `codelab-agent config …` и возвращает код выхода.
///
/// Как использовать: [config] — результат разбора команды `config` верхним
/// парсером. Без подкоманды `check`, с неизвестной подкомандой или лишними
/// аргументами — справка в stderr и [usageExit]. Тексты и коды `check` даёт
/// общий `ConfigCommands` (D13): `codelab config check` печатает то же.
Future<int> runConfigCommand(
  ArgResults config, {
  required Map<String, String> environment,
  required String cwd,
  required IOSink out,
  required IOSink err,
}) async {
  final check = config.command;
  if (check == null || check.name != 'check' || check.rest.isNotEmpty) {
    final rest = check == null ? config.rest : check.rest;
    err.writeln(
      rest.isEmpty
          ? 'codelab-agent: config needs the subcommand: check'
          // Токены не цитируются: среди них может быть значение секрета
          // (agent-secrets: ошибка разбора не печатает argv; D8).
          : 'codelab-agent: unknown config arguments (${rest.length})',
    );
    err
      ..writeln()
      ..writeln(configUsage());
    return usageExit;
  }
  final result = await ConfigCommands().check(
    CheckOptions(cwd: check.option('cwd') ?? cwd, environment: environment),
  );
  result.stdout.forEach(out.writeln);
  result.stderr.forEach(err.writeln);
  return result.exitCode;
}
