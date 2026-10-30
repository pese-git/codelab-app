import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Сервер из `.codelab/config.yaml` недоверенного проекта не запускается
/// (agent-configuration «Доверие к проектному конфигу»; `agent-core-
/// architecture` §15.3; design.md change `add-agent-configuration`, D7).
/// Процессный тест на Dart VM: репозиторий не должен получать запуск
/// процессов на машине пользователя только потому, что агент открыт в нём.
void main() {
  late Directory temp;
  late String project;
  late File pidFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_untrusted_');
    addTearDown(() => temp.delete(recursive: true));
    project = '${temp.path}/project';
    Directory('$project/.codelab').createSync(recursive: true);
    Directory('${temp.path}/home').createSync();
    pidFile = File('${temp.path}/server.pid');
    File('$project/.codelab/config.yaml').writeAsStringSync('''
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
  });

  /// Открывает сессию в [project] и возвращает, запущен ли сервер проекта.
  Future<bool> serverStarted({required bool trusted}) async {
    File('${temp.path}/home/config.yaml').writeAsStringSync(
      trusted ? 'trusted_projects: [${jsonEncode(project)}]\n' : '',
    );
    final agent = await AgentProcess.start(
      [
        'serve',
        '--stdio',
        '--provider',
        'openai-compatible',
        '--base-url',
        'http://127.0.0.1:9/v1',
        '--model',
        'm',
      ],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      if (pidFile.existsSync()) {
        final pid = int.tryParse(pidFile.readAsStringSync());
        if (pid != null) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
      }
    });
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': 1},
    });
    await agent.responseTo(1);
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'session/new',
      'params': {'cwd': project, 'mcpServers': <Object?>[]},
    });
    final created = await agent.responseTo(2);
    expect(created['result'], isNotNull, reason: agent.stderrText);
    final started = pidFile.existsSync();
    await agent.closeStdin();
    await agent.exitCode;
    return started;
  }

  test('the server of an untrusted project is not started', () async {
    expect(await serverStarted(trusted: false), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'the same server is started when trusted_projects lists the project',
    () async {
      expect(await serverStarted(trusted: true), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
