import 'dart:async';
import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' show ioProviderCheck;
import 'package:test/test.dart';

/// Редирект не выполняется на настоящем `ioProviderCheck` (client-agent-setup
/// «Проверка списка моделей», сценарий «Редирект не выполняется»; SETUP-23):
/// ключ не должен уйти на адрес из `Location`.
void main() {
  const leak = 'sk-test-leak-0123456789';
  final key = SecretValue(leak);
  const timeout = Duration(seconds: 5);
  late List<HttpServer> servers;

  setUp(() => servers = []);
  tearDown(() async {
    for (final server in servers) {
      await server.close(force: true);
    }
  });

  Future<HttpServer> serve(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    server.listen(handler);
    return server;
  }

  Uri base(HttpServer server) =>
      Uri.parse('http://127.0.0.1:${server.port}/v1');

  test('редирект не выполняется: ключ не уходит на другой хост', () async {
    final second = <String>[];
    final target = await serve((request) async {
      second.add('${request.uri} ${request.headers.value('authorization')}');
      await request.response.close();
    });
    final first = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set('location', 'http://127.0.0.1:${target.port}/steal');
      await request.response.close();
    });

    final result = await ioProviderCheck().listModels(
      'openai-compatible',
      base(first),
      key,
      timeout: timeout,
    );

    final failure = (result as CheckFailure).failure;
    expect(failure.kind, ProviderCheckFailureKind.badResponse);
    expect(failure.statusCode, 302);
    expect(second, isEmpty, reason: 'второй сервер не должен получить запрос');
  });
}
