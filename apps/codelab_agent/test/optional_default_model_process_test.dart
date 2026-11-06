import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Модель по умолчанию без `agent.default_model` как процесс бинаря
/// (agent-binary «Конфиг бинаря из файлов, окружения и флагов», сценарии
/// «Нет ни одной модели» и «Провайдер без модели по умолчанию»; agent-runtime
/// «Модель новой сессии», «Последняя выбранная модель», сценарий «Пустой
/// CODELAB_HOME и provider add»; design.md change `optional-default-model`,
/// D5–D8; задача 4.1). Интеграционный тест на Dart VM: временные
/// `CODELAB_HOME` и каталог проекта, настоящий `~/.codelab` не читается,
/// ключи только `sk-test-leak-…`.
void main() {
  late Directory temp;
  late String home;
  late String project;

  setUp(() {
    temp = Directory(
      Directory.systemTemp
          .createTempSync('codelab_agent_dm_')
          .resolveSymbolicLinksSync(),
    );
    home = '${temp.path}/home';
    project = '${temp.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Провайдер `gw` с моделями [models], без ключа модели и без ключа API.
  String gwConfig([List<String> models = const ['m']]) =>
      'providers:\n'
      '  gw:\n'
      '    kind: openai-compatible\n'
      '    base_url: https://x/v1\n'
      '    models:\n'
      '${[for (final m in models) '      $m: {}\n'].join()}';

  Future<AgentProcess> start(
    List<String> args, {
    Map<String, String> environment = const {},
  }) async {
    final agent = await AgentProcess.start(
      args,
      environment: {'CODELAB_HOME': home, ...environment},
      workingDirectory: project,
    );
    addTearDown(() async {
      agent.kill(ProcessSignal.sigkill);
      await agent.exitCode;
    });
    return agent;
  }

  Map<String, Object?> request(int id, String method, Object? params) => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };

  /// `initialize` и `session/new`; возвращает результат `session/new`.
  Future<Map<String, Object?>> newSession(AgentProcess agent) async {
    agent.sendJson(request(1, 'initialize', {'protocolVersion': 1}));
    await agent.responseTo(1);
    agent.sendJson(
      request(2, 'session/new', {'cwd': project, 'mcpServers': <Object?>[]}),
    );
    final created = await agent.responseTo(2);
    return created['result']! as Map<String, Object?>;
  }

  Object? currentModel(Map<String, Object?> result) =>
      (result['configOptions']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((o) => o['id'] == 'model')['currentValue'];

  test('no model anywhere: agent.default_model with the new text, code 64 '
      '(scenario "Нет ни одной модели")', () async {
    final agent = await start(['serve', '--stdio']);

    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 64);
    expect(
      agent.stderrText,
      contains(
        'agent.default_model: no model is configured; add a provider with at '
        'least one model',
      ),
    );
    expect(agent.stderrText, isNot(contains('required')));
    expect(await agent.nextStdoutLine(), isNull, reason: 'stdout stays empty');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a provider without agent.default_model: the transport starts and '
      'session/new has currentValue gw/m (scenario "Провайдер без модели по '
      'умолчанию")', () async {
    File('$home/config.yaml').writeAsStringSync(gwConfig());

    final agent = await start(['serve', '--stdio']);
    final result = await newSession(agent);

    expect(currentModel(result), 'gw/m');
    await agent.stderrContains('session.model.selected');
    expect(agent.stderrText, contains('first-provider'));
    // Автоматический выбор файл состояния не создаёт (D6).
    expect(Directory('$home/state').existsSync(), isFalse);
    await agent.closeStdin();
    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an empty CODELAB_HOME: provider add without --default, then serve '
      '(scenario "Пустой CODELAB_HOME и provider add")', () async {
    final add = await start([
      'provider',
      'add',
      'gw',
      '--kind',
      'openai-compatible',
      '--base-url',
      'https://x/v1',
      '--model',
      'm',
      '--context-window',
      '8192',
      '--api-key-env',
      'GW_KEY',
    ]);
    expect(await add.exitCode.timeout(const Duration(seconds: 60)), 0);
    final out = StringBuffer();
    String? line;
    while ((line = await add.nextStdoutLine()) != null) {
      out.writeln(line);
    }
    expect(out.toString(), contains('Updated providers.gw in $home'));
    expect(out.toString(), isNot(contains('agent.default_model')));
    expect(add.stderrText, isNot(contains('agent.default_model')));
    expect(
      File('$home/config.yaml').readAsStringSync(),
      isNot(contains('default_model')),
    );

    final agent = await start(
      ['serve', '--stdio'],
      environment: {'GW_KEY': 'sk-test-leak-0123456789'},
    );
    final result = await newSession(agent);

    expect(currentModel(result), 'gw/m');
    await agent.stderrContains('session.model.selected');
    expect(agent.stderrText, contains('first-provider'));
    expect(agent.stderrText, isNot(contains('sk-test-leak')));
    expect(agent.stdoutText, isNot(contains('sk-test-leak')));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('set_config_option model writes state/last-model.json; the next '
      'process starts a session on it (D6-D8)', () async {
    File('$home/config.yaml').writeAsStringSync(gwConfig(['m', 'm2']));
    final first = await start(['serve', '--stdio']);
    final created = await newSession(first);
    expect(currentModel(created), 'gw/m');

    first.sendJson(
      request(3, 'session/set_config_option', {
        'sessionId': created['sessionId'],
        'configId': 'model',
        'value': 'gw/m2',
      }),
    );
    final changed = await first.responseTo(3);
    expect(changed['error'], isNull);
    await first.closeStdin();
    expect(await first.exitCode.timeout(const Duration(seconds: 20)), 0);

    final file = File('$home/state/last-model.json');
    expect(jsonDecode(file.readAsStringSync()), {'v': 1, 'model': 'gw/m2'});

    final second = await start(['serve', '--stdio']);
    final result = await newSession(second);

    expect(currentModel(result), 'gw/m2');
    await second.stderrContains('session.model.selected');
    expect(second.stderrText, contains('last-used'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('--llm-script has no memory of the last model: state/ is not created '
      'even after a model change (D8)', () async {
    final agent = await start([
      'serve',
      '--stdio',
      '--llm-script',
      '$appDirectory/test/llm_scripts/hello.json',
      '--model',
      'a',
      '--model',
      'b',
    ]);
    final created = await newSession(agent);

    agent.sendJson(
      request(3, 'session/set_config_option', {
        'sessionId': created['sessionId'],
        'configId': 'model',
        'value': 'scripted/b',
      }),
    );
    final changed = await agent.responseTo(3);
    expect(changed['error'], isNull, reason: agent.stderrText);
    await agent.closeStdin();
    expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 0);

    expect(Directory('$home/state').existsSync(), isFalse);
    expect(Directory(home).listSync(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
