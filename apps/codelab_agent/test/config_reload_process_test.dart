import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';
import 'package:codelab_agent_io/testing.dart' show rewriteUntil;

/// Перезагрузка конфига в процессе `codelab-agent serve --stdio` (agent-binary
/// «Перезагрузка конфига в serve», сценарии «Правка конфига работающего
/// агента» и «Битая правка»; задача 5.11, design.md change
/// `add-config-writer-and-reload`, D7, D8, D13). Интеграционный тест на Dart VM
/// (`AGENTS.md` §21): процесс бинаря, правка файла «рукой» снаружи. Сети нет:
/// ходов не делается, ключ и адрес провайдера вымышлены.
void main() {
  late Directory temp;
  late String home;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_agent_reload_');
    home = '${temp.path}/home';
    Directory(home).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String config(List<String> models, {String extra = ''}) =>
      '''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
${models.map((m) => '      $m: {}').join('\n')}
agent:
  default_model: p/${models.first}
$extra''';

  /// Процесс с открытой сессией; ответ `session/new` и
  /// `available_commands_update` уже прочитаны.
  Future<AgentProcess> start(String yaml) async {
    File('$home/config.yaml').writeAsStringSync(yaml);
    final agent = await AgentProcess.start(
      ['serve', '--stdio'],
      environment: {
        'CODELAB_HOME': home,
        'CODELAB_SECRET_CODELAB_P': 'test-key-0001',
      },
      workingDirectory: temp.path,
    );
    addTearDown(agent.kill9);
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
      'params': {'cwd': temp.path, 'mcpServers': <Object?>[]},
    });
    await agent.responseTo(2);
    await _nextUpdate(agent, 'available_commands_update');
    return agent;
  }

  test('a manual edit of config.yaml gives config_option_update with the new '
      'model after the edit; the process is not restarted', () async {
    final agent = await start(config(['m1']));
    final pid = agent.pid;

    // Подписка `watch` у процесса начинается с задержкой: запись повторяется
    // (с разным хвостом), пока не придёт кадр. Правка одна по смыслу.
    final updated = _nextUpdate(agent, 'config_option_update')..ignore();
    await rewriteUntil(
      updated,
      (n) => File(
        '$home/config.yaml',
      ).writeAsStringSync(config(['m1', 'm2'], extra: '# edit $n\n')),
    );
    final update = await updated;
    final model = (update['configOptions']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((o) => o['id'] == 'model');
    expect((model['options']! as List).map((o) => (o as Map)['value']), [
      'p/m1',
      'p/m2',
    ]);
    expect(model['currentValue'], 'p/m1');
    expect(agent.pid, pid);
    expect(agent.stderrText, contains('config.reload.applied'));
    expect(agent.stderrText, isNot(contains('test-key-0001')));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a broken edit (budget.max_steps: 0) gives no frame and '
      'config.reload.failed with the file and the key; the next valid edit '
      'still reloads', () async {
    final agent = await start(config(['m1']));

    await rewriteUntil(
      agent.stderrContains('config.reload.failed')..ignore(),
      (n) => File('$home/config.yaml').writeAsStringSync(
        config(['m1', 'm2'], extra: 'budget:\n  max_steps: 0\n# edit $n\n'),
      ),
    );
    expect(agent.stderrText, contains('budget.max_steps'));
    expect(agent.stderrText, contains('config.yaml'));
    // Ни одного кадра на битую правку: если бы он пришёл, `_nextUpdate`
    // ниже прочитал бы его первым, и в нём была бы модель `p/m2`.

    final updated = _nextUpdate(agent, 'config_option_update')..ignore();
    await rewriteUntil(
      updated,
      (n) => File(
        '$home/config.yaml',
      ).writeAsStringSync(config(['m1', 'm3'], extra: '# fix $n\n')),
    );
    final update = await updated;
    expect(jsonEncode(update), contains('p/m3'));
    expect(jsonEncode(update), isNot(contains('p/m2')));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'closing stdin exits 0: the watcher does not keep the process alive',
    () async {
      final agent = await start(config(['m1']));

      await agent.closeStdin();

      expect(await agent.exitCode.timeout(const Duration(seconds: 20)), 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// Читает stdout до уведомления `session/update` с [kind]; кадры по дороге
/// пропускаются.
Future<Map<String, Object?>> _nextUpdate(
  AgentProcess agent,
  String kind, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final left = deadline.difference(DateTime.now());
    final line = await agent.nextStdoutLine(
      timeout: left.isNegative ? Duration.zero : left,
    );
    if (line == null) {
      throw StateError(
        'stdout closed before $kind; stderr:\n${agent.stderrText}',
      );
    }
    final message = jsonDecode(line) as Map<String, Object?>;
    if (message case {
      'params': {'update': final Map<String, Object?> update},
    } when update['sessionUpdate'] == kind) {
      return update;
    }
  }
}
