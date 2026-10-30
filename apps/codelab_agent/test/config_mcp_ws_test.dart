import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/agent_process.dart';

/// `codelab-agent serve --ws` не запускает MCP-серверы ни из конфигурации, ни
/// от клиента (задача 9.5; agent-binary «MCP-серверы в бинаре», сценарий
/// «WS-профиль не запускает MCP-серверы»; design.md change
/// `add-agent-configuration`, D10; `add-agent-mcp-client`, D3). Процесс
/// бинаря и настоящий сокет на Dart VM (`AGENTS.md` §21).
void main() {
  const token = 'secret-token';
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_cfg_ws_');
  });

  tearDown(() => temp.delete(recursive: true));

  Map<String, Object?> stdioServer(String name, File pidFile) => {
    'name': name,
    'command': dartExecutable(),
    'args': [
      '$appDirectory/test/support/fake_mcp_stdio_server.dart',
      '$appDirectory/test/llm_scripts/fake_mcp_echo_server.json',
      pidFile.path,
    ],
    'env': <Object?>[],
  };

  test('no server process starts; both servers are skipped with the profile '
      'reason', () async {
    final configPid = File('${temp.path}/config.pid');
    final clientPid = File('${temp.path}/client.pid');
    final config = File('${temp.path}/c.yaml')
      ..writeAsStringSync('''
mcp:
  servers:
    - name: fromconfig
      type: stdio
      command: ${jsonEncode(dartExecutable())}
      args:
        - ${jsonEncode('$appDirectory/test/support/fake_mcp_stdio_server.dart')}
        - ${jsonEncode('$appDirectory/test/llm_scripts/fake_mcp_echo_server.json')}
        - ${jsonEncode(configPid.path)}
''');
    final agent = await AgentProcess.start(
      [
        'serve',
        '--ws',
        '--port',
        '0',
        '--llm-script',
        'test/llm_scripts/hello.json',
        '--config',
        config.path,
      ],
      environment: {
        'CODELAB_HOME': '${temp.path}/home',
        'CODELAB_AGENT_TOKEN': token,
      },
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
      for (final file in [configPid, clientPid]) {
        if (file.existsSync()) {
          final pid = int.tryParse(file.readAsStringSync());
          if (pid != null) {
            Process.killPid(pid, ProcessSignal.sigkill);
          }
        }
      }
    });
    await agent.stderrContains('serve.ws.listening');
    final port = int.parse(
      RegExp(
        r'serve\.ws\.listening .*port: (\d+)',
      ).firstMatch(agent.stderrText)!.group(1)!,
    );
    final transport = WebSocketAcpTransport(
      WebSocketAcpTransportConfig(
        uri: Uri.parse('ws://127.0.0.1:$port/acp'),
        token: token,
      ),
    );
    await transport.start();
    addTearDown(transport.close);
    final peer = AcpPeer(transport);
    addTearDown(peer.dispose);

    final init = await peer.call('initialize', {'protocolVersion': 1});
    final capabilities = init['agentCapabilities']! as Map<String, Object?>;
    expect(capabilities['mcpCapabilities'], {'http': false, 'sse': false});

    final created = await peer.call('session/new', {
      'cwd': temp.path,
      'mcpServers': [stdioServer('fromclient', clientPid)],
    });

    expect(created['sessionId'], isNotNull);
    expect(configPid.existsSync(), isFalse);
    expect(clientPid.existsSync(), isFalse);
    await agent.stderrContains('fromconfig');
    await agent.stderrContains('fromclient');
    // Причина профиля встречается и в `host.plan`, поэтому считаются только
    // строки пропусков.
    final skipped = [
      for (final line in agent.stderrText.split('\n'))
        if (line.contains('mcp.server.skipped')) line,
    ];
    expect(skipped, hasLength(2), reason: agent.stderrText);
    expect(
      skipped,
      everyElement(contains('stdio MCP servers are disabled over WebSocket')),
    );
    expect(
      skipped.join('\n'),
      allOf(contains('fromconfig'), contains('fromclient')),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
