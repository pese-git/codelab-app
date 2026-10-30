import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent serve --stdio` с MCP-сервером из `mcp.servers` конфигурации
/// (задача 9.4; agent-binary «MCP-серверы в бинаре», сценарий «Сервер из
/// конфигурации»; agent-configuration «Сервер конфига в сессии»; design.md
/// change `add-agent-configuration`, D10, D17; E-02, часть конфигурации).
/// Интеграционный тест на Dart VM (`AGENTS.md` §21).
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_cfg_mcp_');
    // Регистрируется первым, поэтому выполняется последним: каталог нужен
    // уборке процессов теста (файл с pid сервера).
    addTearDown(() => temp.delete(recursive: true));
  });

  Map<String, Object?> request(int id, String method, Object? params) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  Future<bool> alive(int pid) async =>
      (await Process.run('ps', ['-p', '$pid'])).exitCode == 0;

  test(
    'a server of mcp.servers is in the session without mcpServers: '
    'mcp__fake__echo completes with hi, the process ends after EOF',
    () async {
      final pidFile = File('${temp.path}/server.pid');
      // JSON — подмножество YAML: пути в кавычках не ломают файл.
      final config = File('${temp.path}/c.yaml')
        ..writeAsStringSync('''
mcp:
  servers:
    - name: fake
      type: stdio
      command: ${jsonEncode(dartExecutable())}
      args:
        - ${jsonEncode('$appDirectory/test/support/fake_mcp_stdio_server.dart')}
        - ${jsonEncode('$appDirectory/test/llm_scripts/fake_mcp_echo_server.json')}
        - ${jsonEncode(pidFile.path)}
''');
      final agent = await AgentProcess.start(
        [
          'serve',
          '--stdio',
          '--llm-script',
          'test/llm_scripts/mcp_echo.json',
          '--config',
          config.path,
        ],
        environment: {'CODELAB_HOME': '${temp.path}/home'},
      );
      // При падении теста ни агент, ни процесс сервера не должны остаться.
      addTearDown(() async {
        agent.kill(ProcessSignal.sigkill);
        if (pidFile.existsSync()) {
          final pid = int.tryParse(pidFile.readAsStringSync());
          if (pid != null) {
            Process.killPid(pid, ProcessSignal.sigkill);
          }
        }
      });
      agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
      await agent.responseTo(1);

      agent.sendJson(
        request(2, 'session/new', {
          'cwd': temp.path,
          'mcpServers': <Object?>[],
        }),
      );
      final created = await agent.responseTo(2);
      final sessionId = (created['result']! as Map)['sessionId'];
      final serverPid = int.parse(pidFile.readAsStringSync());
      expect(await alive(serverPid), isTrue, reason: 'the server is running');

      agent.sendJson(
        request(3, 'session/prompt', {
          'sessionId': sessionId,
          'prompt': [
            {'type': 'text', 'text': 'Повтори hi'},
          ],
        }),
      );
      final updates = <Map<String, Object?>>[];
      Map<String, Object?>? answer;
      while (answer == null) {
        final line = await agent.nextStdoutLine();
        expect(line, isNotNull, reason: 'stderr:\n${agent.stderrText}');
        final message = jsonDecode(line!) as Map<String, Object?>;
        if (message['method'] == 'session/request_permission') {
          final options = (message['params']! as Map)['options']! as List;
          final allow = options.cast<Map>().firstWhere(
            (o) => o['kind'] == 'allow_once',
          );
          agent.sendJson({
            'jsonrpc': '2.0',
            'id': message['id'],
            'result': {
              'outcome': {'outcome': 'selected', 'optionId': allow['optionId']},
            },
          });
        } else if (message['id'] == 3 && message.containsKey('result')) {
          answer = message;
        } else {
          updates.add(message);
        }
      }

      expect((answer['result']! as Map)['stopReason'], 'end_turn');
      final completed = [
        for (final m in updates)
          if (m case {
            'params': {
              'update':
                  {
                    'sessionUpdate': 'tool_call_update',
                    'status': 'completed',
                  } &&
                  final Map update,
            },
          })
            jsonEncode(update),
      ];
      expect(completed, hasLength(1));
      expect(completed.single, contains('hi'));

      await agent.closeStdin();
      expect(await agent.exitCode, 0);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await alive(serverPid) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        await alive(serverPid),
        isFalse,
        reason: 'the server must be dead',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
