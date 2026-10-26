import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

import 'agent_process.dart';

const _token = 'fixture-token';

/// Подключение транспортного драйвера к процессу бинаря (design.md change
/// `add-codelab-agent-binary`, D8).
///
/// Почему процесс: транспортная фикстура проверяет кадрирование stdio и
/// аутентификацию WebSocket — их нет у транспорта в памяти.
///
/// Как использовать: `runAgentFixtureOver(fixture, connectAgentProcess)`.
/// Сценарий модели — блок `llm` фикстуры с развёрнутыми `$repeat`, файлом
/// для `--llm-script`. Для `ws` попытки `attempts` проверяются до основного
/// подключения: статус отказа обязан совпасть с `expectStatus`.
Future<AgentConnection> connectAgentProcess(AgentFixtureSetup setup) async {
  final transport = setup.fixture.setup.transport!;
  final scriptDir = await Directory.systemTemp.createTemp('fixture_llm_');
  final script = File('${scriptDir.path}/llm.json')
    ..writeAsStringSync(
      jsonEncode({
        'llm': expandRepeat(setup.llm ?? {'steps': <Object?>[]}),
      }),
    );
  final args = [
    '--llm-script',
    script.path,
    if (setup.mode case final mode?) ...['--permission-mode', mode],
  ];
  final environment = {
    'CODELAB_HOME': '${scriptDir.path}/home',
    'CODELAB_AGENT_TOKEN': _token,
  };
  switch (transport.kind) {
    case FixtureTransportKind.stdio:
      final client = StdioAcpTransport(
        StdioAcpTransportConfig(
          command: dartExecutable(),
          args: [await AgentProcess.kernel(), 'serve', '--stdio', ...args],
          cwd: appDirectory,
          env: environment,
        ),
      );
      return AgentConnection(
        client: client,
        agent: _ProcessAgent(stop: () => scriptDir.delete(recursive: true)),
      );
    case FixtureTransportKind.ws:
      final process = await AgentProcess.start([
        'serve',
        '--ws',
        '--port',
        '0',
        ...args,
      ], environment: environment);
      await process.stderrContains('serve.ws.listening');
      final port = int.parse(
        RegExp(
          r'serve\.ws\.listening .*port: (\d+)',
        ).firstMatch(process.stderrText)!.group(1)!,
      );
      for (final (i, attempt) in transport.attempts.indexed) {
        final status = await _upgradeStatus(port, attempt.authorization);
        expect(
          status,
          attempt.expectStatus,
          reason: '${setup.fixture.id}: setup.transport.attempts[$i]',
        );
      }
      final client = WebSocketAcpTransport(
        WebSocketAcpTransportConfig(
          uri: Uri.parse('ws://127.0.0.1:$port/acp'),
          token: _token,
        ),
      );
      return AgentConnection(
        client: client,
        agent: _ProcessAgent(
          stop: () async {
            process.kill(ProcessSignal.sigterm);
            await process.exitCode;
            await scriptDir.delete(recursive: true);
          },
        ),
      );
  }
}

Future<int> _upgradeStatus(int port, FixtureAuthorization authorization) async {
  final client = HttpClient();
  try {
    final request = await client.get('127.0.0.1', port, '/acp');
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
    switch (authorization) {
      case FixtureAuthorization.none:
        break;
      case FixtureAuthorization.wrong:
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer wrong');
      case FixtureAuthorization.valid:
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    }
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Агент-процесс: сценарий проверяет сам бинарь (несовпадение шага —
/// ошибка хода, её ловит сравнение кадров), поэтому [verify] пуст.
final class _ProcessAgent implements AgentUnderTest {
  _ProcessAgent({required Future<void> Function() stop}) : _stop = stop;

  final Future<void> Function() _stop;

  @override
  void verify() {}

  @override
  Future<void> stop() => _stop();
}
