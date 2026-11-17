import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Предконфигурация провайдера в процессе `codelab-agent` (agent-binary
/// «Флаги предконфигурации провайдера»; agent-configuration «Предконфигурация
/// провайдера из окружения»; design.md change `add-config-writer-and-reload`,
/// D3, OQ6; задача 1.3). Интеграционный тест на Dart VM: процесс бинаря в
/// временном каталоге, `CODELAB_HOME` и `HOME` изолированы, настоящий
/// `~/.codelab` не читается. Значения выдуманные: ни stderr, ни файл лога их
/// содержать не должны (CFG-12).
void main() {
  late Directory temp;
  late String project;
  late String home;

  // Пара переменных провайдера `env` и флаги провайдера `a`: флаги затеняют.
  const envPair = {
    'CODELAB_PROVIDER_TYPE': 'openai-compatible',
    'CODELAB_PROVIDER_CONFIG':
        '{"id":"env","base_url":"https://env.internal/v1","model":"e1",'
        '"context_window":1000}',
  };
  const flagJson =
      '{"id":"a","base_url":"https://a.internal/v1","model":"m1",'
      '"context_window":1000,"headers":{"X-Team":"not-a-real-team-7"}}';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_preconfig_');
    project = '${temp.path}/project';
    home = '${temp.path}/home';
    Directory(project).createSync();
    Directory(home).createSync();
  });

  tearDown(() => temp.delete(recursive: true));

  Future<AgentProcess> start(
    List<String> args, {
    Map<String, String> environment = const {},
  }) async {
    final agent = await AgentProcess.start(
      args,
      environment: {
        'CODELAB_HOME': home,
        // Домашний каталог пользователя не читается: тильду и настоящий
        // `~/.codelab` процесс не видит.
        'HOME': temp.path,
        ...environment,
      },
      workingDirectory: project,
    );
    addTearDown(agent.kill9);
    return agent;
  }

  /// `initialize` + `session/new`; опция `model` как (текущая, список).
  Future<(String, List<String>)> modelOption(AgentProcess agent) async {
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
    final model = ((created['result']! as Map)['configOptions']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((o) => o['id'] == 'model');
    return (
      model['currentValue']! as String,
      [
        for (final o in model['options']! as List)
          (o as Map)['value']! as String,
      ],
    );
  }

  Future<int> exitOf(AgentProcess agent) =>
      agent.exitCode.timeout(const Duration(seconds: 30));

  const slow = Timeout(Duration(seconds: 90));

  group('variables', () {
    test('serve builds the catalog from CODELAB_PROVIDER_*', () async {
      final agent = await start(const [
        'serve',
        '--stdio',
      ], environment: envPair);

      final (current, models) = await modelOption(agent);

      expect(current, 'env/e1');
      expect(models, ['env/e1']);
      expect(agent.stderrText, isNot(contains('config.preconfig.shadowed')));
    }, timeout: slow);

    test('a literal token in a header of the variable: code 64, the value '
        'is nowhere', () async {
      final agent = await start(
        const ['serve', '--stdio'],
        environment: {
          'CODELAB_PROVIDER_TYPE': 'openai-compatible',
          'CODELAB_PROVIDER_CONFIG':
              '{"id":"gw","base_url":"https://gw.internal/v1","model":"m",'
              '"context_window":1000,'
              '"headers":{"Authorization":"Bearer not-a-real-key-env1"}}',
        },
      );

      expect(await exitOf(agent), 64);
      expect(agent.stderrText, contains('CODELAB_PROVIDER_CONFIG'));
      expect(agent.stderrText, contains('codelab secret set codelab/gw'));
      expect(agent.stderrText, isNot(contains('not-a-real-key-env1')));
      expect(agent.stdoutText, isEmpty);
    }, timeout: slow);

    test('codelab-agent config check sees the preconfiguration', () async {
      final agent = await start(const [
        'config',
        'check',
      ], environment: envPair);

      expect(await exitOf(agent), 0, reason: agent.stderrText);
      final out = StringBuffer();
      String? line;
      while ((line = await agent.nextStdoutLine()) != null) {
        out.writeln(line);
      }
      expect(out.toString(), contains('env:CODELAB_PROVIDER_CONFIG'));
      expect(out.toString().trimRight(), endsWith('Config: valid'));
    }, timeout: slow);

    test('config check reports a key written as a value, without it', () async {
      final agent = await start(
        const ['config', 'check'],
        environment: {
          'CODELAB_PROVIDER_TYPE': 'anthropic',
          'CODELAB_PROVIDER_CONFIG':
              '{"id":"gw","model":"m","context_window":1000,'
              '"api_key":"not-a-real-key-chk"}',
        },
      );

      expect(await exitOf(agent), 1);
      final out = StringBuffer();
      String? line;
      while ((line = await agent.nextStdoutLine()) != null) {
        out.writeln(line);
      }
      expect(out.toString(), contains('codelab secret set codelab/gw'));
      expect(out.toString(), isNot(contains('not-a-real-key-chk')));
      expect(agent.stderrText, isNot(contains('not-a-real-key-chk')));
    }, timeout: slow);
  });

  group('flags', () {
    test('flags shadow the variables; the log has config.preconfig.shadowed '
        'and no flag value', () async {
      final logFile = '${temp.path}/logs/agent.log';
      final agent = await start([
        'serve',
        '--stdio',
        '--provider-type',
        'openai-compatible',
        '--provider-config',
        flagJson,
        '--log-file',
        logFile,
        '--log-level',
        'trace',
      ], environment: envPair);

      final (current, models) = await modelOption(agent);

      expect(current, 'a/m1');
      expect(models, ['a/m1']);
      await agent.closeStdin();
      expect(await exitOf(agent), 0);
      expect(agent.stderrText, contains('config.preconfig.shadowed'));
      final logged = File(logFile).readAsStringSync();
      expect(logged, contains('config.preconfig.shadowed'));
      expect(logged, contains('"by":"flags"'));
      for (final text in [agent.stderrText, logged, agent.stdoutText]) {
        expect(text, isNot(contains('not-a-real-team-7')));
        expect(text, isNot(contains('a.internal')));
      }
    }, timeout: slow);

    test('--provider-config @path is relative to the working directory of the '
        'process', () async {
      File('$project/p.json').writeAsStringSync(flagJson);
      final agent = await start(const [
        'serve',
        '--stdio',
        '--provider-type',
        'openai-compatible',
        '--provider-config',
        '@p.json',
      ]);

      final (current, _) = await modelOption(agent);

      expect(current, 'a/m1');
    }, timeout: slow);

    test('--provider-config @path with api_key stays an error: the file is a '
        'flag value, not a config layer (R8-4 does not apply)', () async {
      File('$project/p.json').writeAsStringSync(
        '{"id":"a","model":"m1","context_window":1000,'
        '"api_key":"not-a-real-key-at-path"}',
      );
      final agent = await start(const [
        'serve',
        '--stdio',
        '--provider-type',
        'openai-compatible',
        '--provider-config',
        '@p.json',
      ]);

      expect(await exitOf(agent), 64);
      expect(agent.stderrText, contains('codelab secret set codelab/a'));
      expect(agent.stderrText, isNot(contains('not-a-real-key-at-path')));
    }, timeout: slow);

    test('--model beats the flags preconfiguration, CODELAB_MODEL loses to '
        'it', () async {
      File('$home/config.yaml').writeAsStringSync('''
providers:
  openai:
    kind: openai-compatible
    base_url: https://api.openai.test/v1
    models:
      gpt-4o: {}
''');
      const flags = [
        'serve',
        '--stdio',
        '--provider-type',
        'openai-compatible',
        '--provider-config',
        flagJson,
      ];
      const env = {'CODELAB_MODEL': 'openai/gpt-4o'};

      final first = await start(flags, environment: env);
      final (firstCurrent, firstModels) = await modelOption(first);
      final second = await start([
        ...flags,
        '--model',
        'openai/gpt-4o',
      ], environment: env);
      final (secondCurrent, _) = await modelOption(second);

      expect(firstCurrent, 'a/m1');
      expect(firstModels, containsAll(['a/m1', 'openai/gpt-4o']));
      expect(secondCurrent, 'openai/gpt-4o');
    }, timeout: slow);

    test('one flag of the two: code 64 before stdin', () async {
      final agent = await start(const [
        'serve',
        '--stdio',
        '--provider-type',
        'anthropic',
      ]);

      expect(await exitOf(agent), 64);
      expect(agent.stderrText, contains('--provider-config'));
      expect(agent.stdoutText, isEmpty);
    }, timeout: slow);

    test('together with --provider: code 64 before stdin and the text '
        'of the rule', () async {
      final agent = await start([
        'serve',
        '--stdio',
        '--provider',
        'openai-compatible',
        '--base-url',
        'http://x',
        '--model',
        'm',
        '--provider-type',
        'anthropic',
        '--provider-config',
        flagJson,
      ]);

      expect(await exitOf(agent), 64);
      expect(
        agent.stderrText,
        contains('--provider-type cannot be combined with --provider'),
      );
      expect(agent.stderrText, isNot(contains('not-a-real-team-7')));
      expect(agent.stdoutText, isEmpty);
    }, timeout: slow);

    test('@path that cannot be read: code 64', () async {
      final agent = await start(const [
        'serve',
        '--stdio',
        '--provider-type',
        'anthropic',
        '--provider-config',
        '@nope.json',
      ]);

      expect(await exitOf(agent), 64);
      expect(agent.stderrText, contains('--provider-config'));
      expect(agent.stdoutText, isEmpty);
    }, timeout: slow);

    test('a literal token in the JSON of the flag: code 64, the value is '
        'neither in stderr nor in stdout', () async {
      final agent = await start([
        'serve',
        '--stdio',
        '--provider-type',
        'openai-compatible',
        '--provider-config',
        jsonEncode({
          'id': 'gw',
          'base_url': 'https://gw.internal/v1',
          'model': 'm',
          'context_window': 1000,
          'headers': {'Authorization': 'Bearer not-a-real-key-flag1'},
        }),
      ]);

      expect(await exitOf(agent), 64);
      expect(agent.stderrText, contains('codelab secret set codelab/gw'));
      expect(agent.stderrText, isNot(contains('not-a-real-key-flag1')));
      expect(agent.stdoutText, isEmpty);
    }, timeout: slow);
  });
}
