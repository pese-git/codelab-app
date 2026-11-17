import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        ProviderAddOptions,
        ProviderCommands,
        ProviderListOptions,
        ProviderRemoveOptions,
        SecretInput,
        StdinSecretInput;

import 'write_cli_support.dart';

/// Парсер команды `provider` (design.md change `add-config-writer-and-reload`,
/// D6).
///
/// Почему отдельный файл: как `config_cli.dart` и `secret_cli.dart`, команда
/// регистрируется рядом с `serve` в верхнем парсере и не добавляет условий в
/// разбор `serve`. Флага со значением ключа нет намеренно: argv виден через
/// `ps` и попадает в историю оболочки, поэтому ключ читается только из stdin
/// (`--api-key-stdin`) либо задаётся ссылкой (`--api-key-secret`,
/// `--api-key-env`).
final ArgParser providerParser = ArgParser()
  ..addCommand(
    'add',
    withLayerFlags(
      ArgParser()
        ..addOption('kind', help: 'openai-compatible, anthropic or gemini.')
        ..addOption('base-url', help: 'Provider endpoint.')
        ..addOption('model', help: 'Model id of the provider.')
        ..addOption('context-window', help: 'Model context window in tokens.')
        ..addOption('api-key-secret', help: 'Name of a stored secret.')
        ..addOption('api-key-env', help: 'Name of an environment variable.')
        ..addFlag(
          'api-key-stdin',
          negatable: false,
          help: 'Read the API key from stdin and store it as codelab/<id>.',
        )
        ..addFlag(
          'default',
          negatable: false,
          help: 'Make <id>/<model> the default model.',
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

/// Справка команды `provider` (в stderr при коде `64`).
String providerUsage() =>
    'Usage: codelab-agent provider add <id> --kind <kind> --model <model> '
    '--context-window <tokens>\n'
    '           [--base-url <url>] [--api-key-secret <name> | '
    '--api-key-env <var> | --api-key-stdin]\n'
    '           [--default] [--project | --local]\n'
    '       codelab-agent provider list [--cwd <dir>]\n'
    '       codelab-agent provider remove <id> [--project | --local]\n\n'
    'Edits the config file in place. The API key is never passed as an '
    'argument: use --api-key-stdin (needs secrets.backend: file), a secret '
    'name or an environment variable name.';

/// Выполняет `codelab-agent provider …` и возвращает код выхода.
///
/// Как использовать: [provider] — результат разбора команды `provider`
/// верхним парсером. Без подкоманды, с неизвестной подкомандой или неверным
/// числом аргументов — справка в stderr и код `64`; тексты и коды остальных
/// случаев даёт общий `ProviderCommands`. [input] читается только с
/// `--api-key-stdin`; по умолчанию — stdin процесса.
Future<int> runProviderCommand(
  ArgResults provider, {
  required Map<String, String> environment,
  required String cwd,
  required IOSink out,
  required IOSink err,
  SecretInput? input,
  ProviderCommands? commands,
}) async {
  final sub = provider.command;
  if (sub == null) {
    return usageFailure(
      err,
      provider.rest.isEmpty
          ? 'provider needs a subcommand: add, list or remove'
          : 'unknown provider arguments (${provider.rest.length})',
      providerUsage(),
    );
  }
  final wanted = sub.name == 'list' ? 0 : 1;
  if (sub.rest.length != wanted) {
    return usageFailure(
      err,
      sub.rest.length > wanted
          ? 'unknown provider arguments (${sub.rest.length - wanted})'
          : 'provider ${sub.name} needs the provider id',
      providerUsage(),
    );
  }
  final service = commands ?? ProviderCommands();
  if (sub.name == 'list') {
    return printResult(
      await service.list(
        ProviderListOptions(
          cwd: sub.option('cwd') ?? cwd,
          environment: environment,
        ),
      ),
      out,
      err,
    );
  }
  if (sub.name == 'remove') {
    return printResult(
      await service.remove(
        ProviderRemoveOptions(
          id: sub.rest.single,
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
      ProviderAddOptions(
        id: sub.rest.single,
        cwd: cwd,
        environment: environment,
        kind: sub.option('kind'),
        baseUrl: sub.option('base-url'),
        model: sub.option('model'),
        contextWindow: sub.option('context-window'),
        apiKeySecret: sub.option('api-key-secret'),
        apiKeyEnv: sub.option('api-key-env'),
        apiKeyStdin: sub.flag('api-key-stdin'),
        makeDefault: sub.flag('default'),
        project: sub.flag('project'),
        local: sub.flag('local'),
      ),
      input ?? StdinSecretInput(),
    ),
    out,
    err,
  );
}
