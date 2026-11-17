import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        SecretCommandResult,
        SecretCommands,
        SecretDeleteOptions,
        SecretInput,
        SecretListOptions,
        SecretMigrateOptions,
        SecretSetOptions,
        StdinSecretInput,
        before1Note;

import '../serve/exit_codes.dart';

/// Парсер команды `secret` (design.md change `add-agent-secret-store`, D8).
///
/// Почему отдельный файл: как `config_cli.dart`, команда регистрируется рядом
/// с `serve` в одном верхнем парсере (`addCommand`) и не добавляет условий в
/// разбор `serve`. Три подкоманды без флагов: значение секрета читается
/// только из stdin, поэтому флага `--value` нет (argv виден через `ps` и
/// попадает в историю оболочки). Флаг `serve --config` подкоманды не видят:
/// бэкенд берётся из `$CODELAB_HOME/config.yaml` и `CODELAB_CONFIG`.
final ArgParser secretParser = ArgParser()
  ..addCommand('set', ArgParser())
  ..addCommand('delete', ArgParser())
  ..addCommand('list', ArgParser())
  // `migrate` (design.md change `add-config-literal-secrets-and-migrate`, D7):
  // слои и режим — флагами, значений в argv нет; stdin не читается.
  ..addCommand(
    'migrate',
    ArgParser()
      ..addFlag('project', negatable: false)
      ..addFlag('local', negatable: false)
      ..addFlag('all', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('force', negatable: false)
      ..addOption('cwd'),
  );

/// Справка команды `secret` (в stderr при коде `64`).
String secretUsage() =>
    'Usage: codelab-agent secret set|delete|list|migrate\n\n'
    '  codelab-agent secret set <name>     '
    'read the value from stdin (hidden on a terminal)\n'
    '  codelab-agent secret delete <name>\n'
    '  codelab-agent secret list\n'
    '  codelab-agent secret migrate [--all | [--project] [--local]] '
    '[--cwd <dir>] [--dry-run] [--force]\n'
    '      move secrets written in config files to the store '
    '(--force replaces a stored secret for good)\n\n'
    'Works on the backend chosen by secrets.backend in '
    r'$CODELAB_HOME/config.yaml or in the file named by CODELAB_CONFIG '
    '(serve --config is not seen). The value is never passed as an '
    'argument and never printed.\n\n'
    '$before1Note';

/// Выполняет `codelab-agent secret …` и возвращает код выхода.
///
/// Как использовать: [secret] — результат разбора команды `secret` верхним
/// парсером. Без подкоманды, с неизвестной подкомандой или лишними
/// аргументами — справка в stderr и [usageExit]. Тексты и коды даёт общий
/// `SecretCommands` (D8): `codelab secret` печатает то же. Сообщения об
/// ошибке разбора не называют присланные слова: среди них может оказаться
/// значение секрета, переданное аргументом по ошибке. [input] — шов тестов,
/// по умолчанию stdin процесса; читается только `set`.
Future<int> runSecretCommand(
  ArgResults secret, {
  required Map<String, String> environment,
  required IOSink out,
  required IOSink err,
  SecretInput? input,
  SecretCommands? commands,
}) async {
  final sub = secret.command;
  if (sub == null) {
    err
      ..writeln(
        'codelab-agent: secret needs a subcommand: set, delete, list or migrate',
      )
      ..writeln()
      ..writeln(secretUsage());
    return usageExit;
  }
  final service = commands ?? SecretCommands();
  final SecretCommandResult result;
  switch (sub.name) {
    case 'set':
      // Позиционных аргументов два и больше — значение передано аргументом
      // (D8, шаг 2): сам аргумент дальше не передаётся.
      if (sub.rest.isEmpty) {
        err
          ..writeln('codelab-agent: secret set needs the secret name')
          ..writeln()
          ..writeln(secretUsage());
        return usageExit;
      }
      result = await service.set(
        SecretSetOptions(
          name: sub.rest.first,
          environment: environment,
          hasValueArgument: sub.rest.length > 1,
        ),
        input ?? StdinSecretInput(),
      );
    case 'delete':
      if (sub.rest.length != 1) {
        err
          ..writeln('codelab-agent: secret delete needs exactly one name')
          ..writeln()
          ..writeln(secretUsage());
        return usageExit;
      }
      result = await service.delete(
        SecretDeleteOptions(name: sub.rest.single, environment: environment),
      );
    case 'migrate':
      if (sub.rest.isNotEmpty) {
        err
          ..writeln('codelab-agent: secret migrate takes no arguments')
          ..writeln()
          ..writeln(secretUsage());
        return usageExit;
      }
      result = await service.migrate(
        SecretMigrateOptions(
          environment: environment,
          cwd: sub.option('cwd') ?? Directory.current.path,
          project: sub.flag('project'),
          local: sub.flag('local'),
          all: sub.flag('all'),
          dryRun: sub.flag('dry-run'),
          force: sub.flag('force'),
        ),
      );
    default:
      if (sub.rest.isNotEmpty) {
        err
          ..writeln('codelab-agent: secret list takes no arguments')
          ..writeln()
          ..writeln(secretUsage());
        return usageExit;
      }
      result = await service.list(SecretListOptions(environment: environment));
  }
  result.stdout.forEach(out.writeln);
  result.stderr.forEach(err.writeln);
  if (result.showUsage) {
    err
      ..writeln()
      ..writeln(secretUsage());
  }
  return result.exitCode;
}
