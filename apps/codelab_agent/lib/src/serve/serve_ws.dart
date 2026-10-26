import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/io.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../cli/serve_args.dart';
import '../host/agent_host.dart';
import 'exit_codes.dart';
import 'signals.dart';

/// `codelab-agent serve --ws`: ACP-клиенты по WebSocket с Bearer-токеном.
///
/// Почему токен при upgrade: WebSocket на loopback доступен любому
/// локальному процессу, а агент исполняет команды от имени пользователя
/// (R-12, документ ядра §13.3). Отказ — до обмена ACP: `426` без upgrade,
/// `401` без верного `Authorization: Bearer <token>`. Путь не проверяется —
/// один процесс, один endpoint (DF-07; design.md change
/// `add-codelab-agent-binary`, D6).
///
/// Как использовать: из [runCodelabAgent]; токен — значение переменной
/// `options.tokenEnv` в [environment], пустая переменная — [usageExit].
/// Каждое подключение — отдельное соединение одного сервера; процесс живёт
/// до сигнала.
Future<int> serveWs(
  AgentHost host,
  ServeOptions options,
  Map<String, String> environment,
  Logger logger,
) async {
  final token = environment[options.tokenEnv] ?? '';
  if (token.isEmpty) {
    logger.log(
      LogLevel.error,
      'serve.usage',
      fields: {
        'message':
            '--ws needs a Bearer token in ${options.tokenEnv}; '
            'the server does not start without it',
      },
    );
    await host.shutdown(grace: Duration.zero);
    return usageExit;
  }
  final HttpServer http;
  try {
    http = await HttpServer.bind(options.host, options.port);
  } on SocketException catch (error) {
    logger.log(
      LogLevel.error,
      'serve.ws.bind_failed',
      fields: {'host': options.host, 'port': options.port},
      error: error,
    );
    await host.shutdown(grace: Duration.zero);
    return failureExit;
  }
  if (!_isLoopback(options.host)) {
    logger.log(
      LogLevel.warning,
      'serve.ws.non_loopback',
      fields: {'host': options.host},
    );
  }
  logger.log(
    LogLevel.info,
    'serve.ws.listening',
    fields: {'host': options.host, 'port': http.port},
  );

  final server = host.createServer();
  final expected = utf8.encode('Bearer $token');
  final stop = Completer<int>();
  final signals = watchStopSignals((code) {
    if (!stop.isCompleted) {
      stop.complete(code);
    }
  });
  final requests = http.listen((request) async {
    final remote = request.connectionInfo?.remoteAddress.address;
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await request.response.close();
      return;
    }
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!_sameBytes(utf8.encode(authorization), expected)) {
      // Ни присланный, ни верный токен в лог не пишутся.
      logger.log(
        LogLevel.warning,
        'serve.ws.unauthorized',
        fields: {'remote': remote},
      );
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer realm="codelab-agent"',
        );
      await request.response.close();
      return;
    }
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object catch (error) {
      logger.log(
        LogLevel.warning,
        'serve.ws.upgrade_failed',
        fields: {'remote': remote},
        error: error,
      );
      return;
    }
    logger.log(LogLevel.info, 'serve.ws.connected', fields: {'remote': remote});
    unawaited(
      server
          .serve(WebSocketServerAcpTransport(socket))
          .then(
            (_) => logger.log(
              LogLevel.info,
              'serve.ws.disconnected',
              fields: {'remote': remote},
            ),
            onError: (Object error, StackTrace stack) => logger.log(
              LogLevel.error,
              'serve.ws.connection_failed',
              fields: {'remote': remote},
              error: error,
              stack: stack,
            ),
          ),
    );
  });

  final code = await stop.future;
  logger.log(LogLevel.info, 'serve.stop', fields: {'exit_code': code});
  await requests.cancel();
  await http.close(force: true);
  await host.shutdown();
  await signals.cancel();
  return code;
}

bool _isLoopback(String host) =>
    host == 'localhost' ||
    (InternetAddress.tryParse(host)?.isLoopback ?? false);

/// Сравнение за постоянное время: длина и место первого расхождения не
/// должны угадываться по времени ответа.
bool _sameBytes(List<int> actual, List<int> expected) {
  var difference = actual.length ^ expected.length;
  for (var i = 0; i < expected.length; i++) {
    difference |= (i < actual.length ? actual[i] : 0) ^ expected[i];
  }
  return difference == 0;
}
