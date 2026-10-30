import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'cli/config_cli.dart';
import 'cli/serve_args.dart';
import 'host/agent_host.dart';
import 'host/serve_config.dart';
import 'log/file_sink.dart';
import 'log/host_logger.dart';
import 'log/stderr_sink.dart';
import 'serve/exit_codes.dart';
import 'serve/serve_stdio.dart';
import 'serve/serve_ws.dart';

/// Запуск `codelab-agent` от аргументов до кода выхода (design.md change
/// `add-codelab-agent-binary`, D7).
///
/// Почему отдельная функция: `bin/` — только точка входа, а порядок
/// «флаги → лог → хост → транспорт → завершение» и коды выхода должны быть
/// одни для процесса и тестов.
///
/// Как использовать: `exit(await runCodelabAgent(args, environment:
/// Platform.environment))`. Ошибка использования — текст в stderr и [usageExit]
/// (`64`); stdout не трогается.
Future<int> runCodelabAgent(
  List<String> args, {
  required Map<String, String> environment,
}) async {
  // Командная строка разбирается один раз. `config` — отдельная команда рядом
  // с `serve` (D13): сервер, транспорт и логи ей не нужны, поэтому она
  // выходит до загрузки конфига `serve`.
  final ArgResults top;
  try {
    top = parseCommandLine(args);
  } on UsageError catch (error) {
    // Справка той команды, которую пользователь начал писать: после
    // `config check --bogus` флаги `serve` только запутали бы.
    stderr
      ..writeln('codelab-agent: ${error.message}')
      ..writeln()
      ..writeln(args.firstOrNull == 'config' ? configUsage() : serveUsage());
    return usageExit;
  }
  if (top.command case final config? when config.name == 'config') {
    try {
      return runConfigCommand(
        config,
        environment: environment,
        cwd: Directory.current.path,
        out: stdout,
        err: stderr,
      );
    } on Object catch (error) {
      // Как у `serve` (`serve.failed`): неожиданное исключение — код `1` и
      // одна строка в stderr, а не код `255` и трасса Dart. Трасса не
      // печатается и в stdout ничего не попадает.
      stderr.writeln('codelab-agent: config failed: $error');
      return failureExit;
    }
  }

  final ServeOptions options;
  try {
    options = parseServeResults(top, environment: environment);
  } on UsageError catch (error) {
    stderr
      ..writeln('codelab-agent: ${error.message}')
      ..writeln()
      ..writeln(serveUsage());
    return usageExit;
  }

  // Конфиг грузится до логов и транспорта: по нему выбираются уровень и файл
  // лога, а невалидный конфиг завершает процесс кодом `64` до первого хода
  // (agent-binary «Конфиг бинаря из файлов, окружения и флагов»).
  final ConfigLoadResult loaded;
  try {
    loaded = loadServeConfig(options, cwd: Directory.current.path);
  } on UsageError catch (error) {
    stderr.writeln('codelab-agent: ${error.message}');
    return usageExit;
  }

  final settings = logSettings(options, loaded);
  final sinks = <LogSink>[StderrLogSink(stderr)];
  if (settings.file case final path?) {
    try {
      sinks.add(FileLogSink.open(path));
    } on UsageError catch (error) {
      stderr.writeln('codelab-agent: ${error.message}');
      return usageExit;
    }
  }
  final logger = HostLogger(level: settings.level, sinks: sinks);
  try {
    if (loaded.config == null) {
      return _reportInvalidConfig(loaded, options, logger);
    }
    final AgentHost host;
    try {
      host = await AgentHost.build(options, logger: logger, loaded: loaded);
    } on UsageError catch (error) {
      logger.log(
        LogLevel.error,
        'serve.usage',
        fields: {'message': error.message},
      );
      return usageExit;
    }
    return switch (options.transport) {
      ServeTransport.stdio => await serveStdio(host, logger),
      ServeTransport.ws => await serveWs(host, options, environment, logger),
    };
  } on Object catch (error, stack) {
    logger.log(LogLevel.error, 'serve.failed', error: error, stack: stack);
    return failureExit;
  } finally {
    await logger.close();
  }
}

/// Проблемы конфига — в stderr по строке на проблему и в лог одним событием
/// `serve.config.invalid` (agent-binary «Логи бинаря»; design.md change
/// `add-agent-configuration`, D16). Код `64`: ошибка конфигурации — ошибка
/// использования (§13.10). Значений ключей в тексте нет: `ConfigIssue.message`
/// строится из пути и типа (CFG-2).
int _reportInvalidConfig(
  ConfigLoadResult loaded,
  ServeOptions options,
  Logger logger,
) {
  logStartupWarnings(logger, loaded);
  for (final issue in loaded.issues) {
    stderr.writeln('codelab-agent: $issue');
  }
  logger.log(
    LogLevel.error,
    'serve.config.invalid',
    fields: {
      'issues': [
        for (final issue in loaded.issues)
          {
            'source': issue.source,
            'line': issue.line,
            'column': issue.column,
            'key': issue.key,
            'kind': issue.kind.name,
          },
      ],
    },
  );
  return usageExit;
}
