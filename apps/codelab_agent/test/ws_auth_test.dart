import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/agent_process.dart';

/// `codelab-agent serve --ws` и Bearer-аутентификация (задачи 4.5, 4.6;
/// agent-binary «Аутентификация WebSocket», «Жизненный цикл процесса»;
/// design.md change `add-codelab-agent-binary`, D6). Интеграционный тест на
/// Dart VM: процесс бинаря и настоящие сокеты (`AGENTS.md` §21).
void main() {
  const token = 'secret-token';
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_ws_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  /// Процесс `serve --ws --port 0` и фактический порт из лога.
  Future<(AgentProcess, int)> serveWs({
    List<String> extra = const [],
    String tokenValue = token,
  }) async {
    final agent = await AgentProcess.start(
      [
        'serve',
        '--ws',
        '--port',
        '0',
        '--llm-script',
        'test/llm_scripts/hello.json',
        ...extra,
      ],
      environment: {
        'CODELAB_HOME': '${temp.path}/home',
        'CODELAB_AGENT_TOKEN': tokenValue,
      },
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    await agent.stderrContains('serve.ws.listening');
    final port = int.parse(
      RegExp(
        r'serve\.ws\.listening .*port: (\d+)',
      ).firstMatch(agent.stderrText)!.group(1)!,
    );
    return (agent, port);
  }

  /// HTTP-статус запроса upgrade с заголовком [authorization].
  Future<(int, String?)> upgrade(int port, {String? authorization}) async {
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, '/acp');
      request.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      final response = await request.close();
      await response.drain<void>();
      return (
        response.statusCode,
        response.headers.value(HttpHeaders.wwwAuthenticateHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AcpPeer> connect(int port, {String path = '/acp'}) async {
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:$port$path'),
        token: token,
      ),
    );
    await transport.start();
    addTearDown(transport.close);
    final peer = AcpPeer(transport);
    addTearDown(peer.dispose);
    return peer;
  }

  test('a plain HTTP request gets 426', () async {
    final (_, port) = await serveWs();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.get('127.0.0.1', port, '/')).close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.upgradeRequired);
  });

  test('no token or a wrong token gets 401 before ACP', () async {
    final (agent, port) = await serveWs();

    final (missing, challenge) = await upgrade(port);
    expect(missing, HttpStatus.unauthorized);
    expect(challenge, startsWith('Bearer'));

    final (wrong, _) = await upgrade(port, authorization: 'Bearer wrong-token');
    expect(wrong, HttpStatus.unauthorized);

    await agent.stderrContains('serve.ws.unauthorized');
    expect(agent.stderrText, isNot(contains('wrong-token')));
    expect(agent.stderrText, isNot(contains(token)));
  });

  test('the right token on /acp and on / reaches initialize', () async {
    final (_, port) = await serveWs();
    for (final path in ['/acp', '/']) {
      final peer = await connect(port, path: path);
      final init = await peer.call('initialize', {'protocolVersion': 1});
      expect(init['protocolVersion'], 1, reason: path);
    }
  });

  test('two connections are two independent clients', () async {
    final (_, port) = await serveWs();
    final a = await connect(port);
    final b = await connect(port);
    final first = await a.openSession(temp.path);
    final second = await b.openSession(temp.path);
    expect(first, isNot(second));
  });

  test('an empty token variable is a usage error', () async {
    final agent = await AgentProcess.start(
      ['serve', '--ws', '--llm-script', 'test/llm_scripts/hello.json'],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
    expect(await agent.exitCode, 64);
    expect(agent.stderrText, contains('CODELAB_AGENT_TOKEN'));
  });

  test('a non-loopback host gives a warning', () async {
    final (agent, _) = await serveWs(extra: ['--host', '0.0.0.0']);
    expect(agent.stderrText, contains('serve.ws.non_loopback'));
  });

  test('SIGTERM exits 143', () async {
    final (agent, port) = await serveWs();
    await connect(port);
    agent.kill(ProcessSignal.sigterm);
    expect(await agent.exitCode, 143);
  }, skip: Platform.isWindows ? 'POSIX signals' : null);
}
