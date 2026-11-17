// E2E `config get mcp.servers`: маскирование `args` MCP-серверов (задача 2.3
// change `add-config-literal-secrets-and-migrate`; spec agent-configuration
// «Маскирование args MCP-серверов в выводе», сценарий «Токены в args ручной
// правки»; design.md D5, R4-6).
//
// Почему: файл конфига правят руками, и токен в `args` попадает в argv
// процесса сервера и в вывод `config get`. Вывод общий через
// `codelab_agent_io`, поэтому у `codelab` и `codelab-agent` он обязан
// совпасть байт в байт и не содержать значений.
//
// Значения выдуманные, токен `ghp_…` собран синтетически; настоящий
// `~/.codelab` не читается: `CODELAB_HOME` и `HOME` процессов временные.
//
// Тег `scripted-only`: файл не зависит от агента матрицы (D5 change
// `add-cli-e2e-agent-matrix`).
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

/// Синтетический токен формата GitHub: `ghp_` и 36 символов.
final _ghToken = 'ghp_${'aB3dE5gH7jK9mN1pQ3sT5vX7zC9eF1hJ3kL5'}';

void main() {
  late Directory tmp;
  late String home;
  late String project;
  late Map<String, String> environment;

  setUp(() {
    tmp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_cli_e2e_args_mask_')
          .resolveSymbolicLinksSync(),
    );
    home = '${tmp.path}/home';
    project = '${tmp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    environment = {'CODELAB_HOME': home, 'HOME': '${tmp.path}/no-home'};
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
mcp:
  servers:
    - name: gh
      type: stdio
      command: gh-mcp
      args:
        - "--token"
        - "plain-value-1"
        - "--api-key=plain-value-2"
        - "--verbose"
        - "$_ghToken"
        - "\${TOKEN}"
''');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliResult> runAgent(List<String> args) async {
    final process = await Process.start(
      dartExecutable(),
      [await E2eCliAgent.agentKernel(), ...args],
      environment: {'PATH': Platform.environment['PATH'] ?? '', ...environment},
      workingDirectory: project,
      includeParentEnvironment: false,
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    await process.stdin.close();
    final out = utf8.decodeStream(process.stdout);
    final err = utf8.decodeStream(process.stderr);
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    return CliResult(code, await out, await err);
  }

  test('config get mcp.servers маскирует значения в args и совпадает у '
      'codelab и codelab-agent', () async {
    const args = ['config', 'get', 'mcp.servers'];
    final cli = await CliProcess.run(
      args,
      environment: environment,
      workingDirectory: project,
    );
    final agent = await runAgent(args);

    expect(cli.exitCode, 0, reason: '$cli');
    expect(agent.exitCode, 0, reason: '$agent');
    expect(cli.stdout, agent.stdout);
    expect(cli.stderr, agent.stderr);
    for (final result in [cli, agent]) {
      final text = '${result.stdout}${result.stderr}';
      for (final secret in ['plain-value-1', 'plain-value-2', _ghToken]) {
        expect(text, isNot(contains(secret)), reason: '$result');
      }
      // Не секреты и ссылка на переменную печатаются как есть.
      expect(text, contains('--verbose'), reason: '$result');
      expect(text, contains(r'${TOKEN}'), reason: '$result');
      expect(text, contains('--api-key=<redacted>'), reason: '$result');
      expect(text, contains('"--token"'), reason: '$result');
      // Значение после `--token` и токен `ghp_…` — два `<redacted>`.
      expect('<redacted>'.allMatches(text).length, greaterThanOrEqualTo(2));
      // Последняя строка вывода — `layer: user`, не JSON.
      final json = result.stdout
          .split('\n')
          .takeWhile((line) => !line.startsWith('layer:'));
      final printed = jsonDecode(json.join('\n')) as List<Object?>;
      expect((printed.single as Map)['args'], [
        '--token',
        '<redacted>',
        '--api-key=<redacted>',
        '--verbose',
        '<redacted>',
        r'${TOKEN}',
      ], reason: '$result');
    }
  }, tags: scriptedOnly);
}
