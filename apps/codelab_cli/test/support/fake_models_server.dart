import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Запрос `GET .../models`, который принял [FakeModelsServer].
final class ModelsRequest {
  ModelsRequest(this.path, this.authorization, this.apiKey);

  final String path;

  /// Заголовок `Authorization` (OpenAI-совместимый ключ) или `null`.
  final String? authorization;

  /// Заголовок `x-api-key` (Anthropic) или `null`.
  final String? apiKey;
}

/// Фиктивный сервер списка моделей на `127.0.0.1` для проверки `/models`
/// мастера провайдера (change `add-provider-setup-ui`, D8, D15).
///
/// Почему настоящий сокет: флаговая форма `codelab provider add` и PTY-e2e
/// гоняют настоящий `ioProviderCheck()`; сеть наружу не нужна, достаточно
/// петли. Адрес `127.0.0.1` ещё и `isLocalHost`, поэтому `http://` без
/// подтверждения (задача 4.0).
///
/// Для чего: [status] — код ответа (`401` — отказ ключа), [models] — id в
/// `data[].id`, [contextLength] — окно контекста у каждой модели (`null` —
/// нет, тогда мастер спросит окно), [requests] — что сервер принял.
///
/// Как использовать: `final server = await FakeModelsServer.start()`;
/// [baseUrl] — адрес для `--base-url`; закрытие — `addTearDown(server.close)`
/// (регистрирует сам [start]). Закрытый порт для сценария `unreachable` —
/// [closedPort].
final class FakeModelsServer {
  FakeModelsServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;

  int status = 200;
  List<String> models = ['m1', 'm2'];
  int? contextLength = 8000;
  final requests = <ModelsRequest>[];

  static Future<FakeModelsServer> start() async {
    final server = FakeModelsServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(server.close);
    return server;
  }

  int get port => _server.port;

  /// Адрес OpenAI-совместимого API: `http://127.0.0.1:<порт>/v1`.
  String get baseUrl => 'http://127.0.0.1:$port/v1';

  /// Адрес без пути: `http://127.0.0.1:<порт>` (`scheme://host:port`).
  String get origin => 'http://127.0.0.1:$port';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests.add(
      ModelsRequest(
        request.uri.path,
        request.headers.value('authorization'),
        request.headers.value('x-api-key'),
      ),
    );
    final response = request.response..statusCode = status;
    if (status == 200 && request.uri.path.endsWith('/models')) {
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'object': 'list',
          'data': [
            for (final id in models)
              {'id': id, 'context_length': ?contextLength},
          ],
        }),
      );
    }
    await response.close();
  }
}

/// Порт, на котором никто не слушает: проверка получит `unreachable`.
Future<int> closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
