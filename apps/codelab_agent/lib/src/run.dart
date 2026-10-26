import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'cli/serve_args.dart';
import 'host/agent_host.dart';
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
  final ServeOptions options;
  try {
    options = parseServeArgs(args, environment: environment);
  } on UsageError catch (error) {
    stderr
      ..writeln('codelab-agent: ${error.message}')
      ..writeln()
      ..writeln(serveUsage());
    return usageExit;
  }

  final sinks = <LogSink>[StderrLogSink(stderr)];
  if (options.logFile case final path?) {
    try {
      sinks.add(FileLogSink.open(path));
    } on UsageError catch (error) {
      stderr.writeln('codelab-agent: ${error.message}');
      return usageExit;
    }
  }
  final logger = HostLogger(level: options.logLevel, sinks: sinks);
  try {
    final AgentHost host;
    try {
      host = await AgentHost.build(options, logger: logger);
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
