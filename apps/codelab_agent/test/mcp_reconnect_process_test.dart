import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// `codelab-agent serve --stdio`: переподключение MCP после падения сервера
/// (задача 6.5 change `add-config-writer-and-reload`; design.md D10, D11;
/// agent-mcp-client «Переподключение и состояние серверов сессии»; E-04).
/// Интеграционный тест на Dart VM (`AGENTS.md` §21).
///
/// Сценарий: сервер завершается сразу после первого `tools/call`; автомат
/// ждёт первую задержку (1 с плюс джиттер до 20 %, реальные часы хоста),
/// запускает процесс заново, и второй вызов даёт `completed`. После закрытия
/// stdin агента ни один процесс сервера не остаётся.
void main() {
  late Directory temp;
  late File pidFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_mcp_rc_');
    pidFile = File('${temp.path}/server.pid');
    // Регистрируется первым, поэтому выполняется последним: уборка процессов
    // ниже читает файл pid.
    addTearDown(() => temp.delete(recursive: true));
  });

  List<int> serverPids() => pidFile.existsSync()
      ? [
          for (final line in pidFile.readAsLinesSync())
            if (int.tryParse(line) case final int pid) pid,
        ]
      : const [];

  Future<bool> alive(int pid) async =>
      (await Process.run('ps', ['-p', '$pid'])).exitCode == 0;

  Map<String, Object?> request(int id, String method, Object? params) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  /// Один ход: отвечает allow_once на запрос разрешения и возвращает статусы
  /// `tool_call_update` до ответа на `session/prompt` с [id].
  Future<List<String>> runTurn(
    AgentProcess agent,
    int id,
    Object sessionId,
  ) async {
    agent.sendJson(
      request(id, 'session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'Повтори hi'},
        ],
      }),
    );
    final statuses = <String>[];
    while (true) {
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
      } else if (message['id'] == id && message.containsKey('result')) {
        expect((message['result']! as Map)['stopReason'], 'end_turn');
        return statuses;
      } else if (message case {
        'params': {
          'update': {
            'sessionUpdate': 'tool_call_update',
            'status': final String status,
          },
        },
      }) {
        statuses.add(status);
      }
    }
  }

  test('a call after the server crash completes after the reconnect; no server '
      'process is left after the agent stdin closes', () async {
    final agent = await AgentProcess.start(
      [
        'serve',
        '--stdio',
        '--llm-script',
        'test/llm_scripts/mcp_reconnect_twice.json',
      ],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
    // При падении теста ни агент, ни процессы сервера не должны остаться.
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      for (final pid in serverPids()) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    });
    agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
    await agent.responseTo(1);
    agent.sendJson(
      request(2, 'session/new', {
        'cwd': temp.path,
        'mcpServers': [
          {
            'name': 'fake',
            'command': dartExecutable(),
            'args': [
              '$appDirectory/test/support/fake_mcp_crashing_server.dart',
              '$appDirectory/test/llm_scripts/fake_mcp_echo_server.json',
              pidFile.path,
            ],
            'env': <Object?>[],
          },
        ],
      }),
    );
    final sessionId =
        ((await agent.responseTo(2))['result']! as Map)['sessionId'];
    expect(serverPids(), hasLength(1), reason: 'the first start');

    expect(await runTurn(agent, 3, sessionId!), contains('completed'));

    // Сервер падает по сигналу теста, а не по таймеру. Затем ждём завершённое
    // переподключение: вторую запись лога `mcp.server.connect` (первая — при
    // session/new). Запуск процесса (pid) для этого мал: до
    // initialize/tools/list сервер ещё `connecting`, и вызов упал бы. Сама
    // задержка (≈1 с) идёт на часах хоста, тест её не подменяет.
    Process.killPid(serverPids().single, ProcessSignal.sigusr1);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    int connects() => _loggedEvents(agent.stderrText, 'mcp.server.connect');
    while (connects() < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(
      connects(),
      greaterThanOrEqualTo(2),
      reason: 'the reconnect must finish; stderr:\n${agent.stderrText}',
    );
    expect(serverPids(), hasLength(2));

    expect(await runTurn(agent, 4, sessionId), contains('completed'));

    await agent.closeStdin();
    expect(await agent.exitCode, 0);
    final pids = serverPids();
    expect(pids, hasLength(2));
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(until)) {
      if (!(await Future.wait(pids.map(alive))).contains(true)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (final pid in pids) {
      expect(await alive(pid), isFalse, reason: 'server $pid must be dead');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Сколько записей лога с событием [event] в stderr агента. Формат записи —
/// `<время> <уровень> <событие> {поля}`: сравнивается именно поле события, а
/// не подстрока (имя события может встретиться в значении поля другой
/// записи).
int _loggedEvents(String stderr, String event) {
  final record = RegExp(r'^\S+ \S+ (\S+)');
  return const LineSplitter()
      .convert(stderr)
      .where((line) => record.firstMatch(line)?.group(1) == event)
      .length;
}
