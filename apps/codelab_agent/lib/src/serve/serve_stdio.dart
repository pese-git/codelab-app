import 'dart:async';
import 'dart:io';

import 'package:acp_transports/io.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../host/agent_host.dart';
import 'exit_codes.dart';
import 'signals.dart';

/// `codelab-agent serve --stdio`: одно соединение на stdin/stdout процесса.
///
/// Почему так завершается: EOF stdin — клиент закрыл сеанс; сервер
/// отвечает на уже прочитанные запросы, и процесс выходит с кодом `0`.
/// `SIGINT` и `SIGTERM` — безопасное завершение с кодами `130` и `143`
/// (design.md change `add-codelab-agent-binary`, D7).
///
/// Как использовать: из [runCodelabAgent] после сборки [host]; возвращает
/// код выхода, ресурсы хоста к этому моменту освобождены.
Future<int> serveStdio(AgentHost host, Logger logger) async {
  final transport = StdioServerAcpTransport();
  final server = host.createServer();
  final stop = Completer<int>();
  final signals = watchStopSignals((code) {
    if (!stop.isCompleted) {
      stop.complete(code);
    }
  });
  logger.log(LogLevel.info, 'serve.stdio.start');
  unawaited(
    server
        .serve(transport)
        .then(
          (_) {
            if (!stop.isCompleted) {
              stop.complete(okExit);
            }
          },
          onError: (Object error, StackTrace stack) {
            logger.log(
              LogLevel.error,
              'serve.stdio.failed',
              error: error,
              stack: stack,
            );
            if (!stop.isCompleted) {
              stop.complete(failureExit);
            }
          },
        ),
  );
  final code = await stop.future;
  logger.log(LogLevel.info, 'serve.stop', fields: {'exit_code': code});
  await host.shutdown();
  await transport.close();
  await signals.cancel();
  await stdout.flush();
  return code;
}
