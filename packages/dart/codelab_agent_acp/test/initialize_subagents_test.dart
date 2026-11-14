import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Блок `subagents` в `initialize` при выключенных субагентах и после живой
/// перезагрузки конфига (agent-acp-server «Субагенты выключены»,
/// «Субагенты выключены перезагрузкой конфига»; design.md change
/// `add-subagents-and-tasks` D9, D37; задачи 2.1, 2.8a).
///
/// Почему отдельный файл от `initialize_test.dart`: сценарии нуждаются в
/// источнике конфигурации с правкой слоёв и новом соединении после
/// перезагрузки, а `initialize_test.dart` проверяет поля §13.2.
void main() {
  ServerHarness? h;

  tearDown(() async => h?.dispose());

  const codelabClient = {
    'terminal': true,
    '_meta': {'codelab': <String, Object?>{}},
  };

  Map<String, Object?>? codelabBlock(Map<String, Object?> result) {
    final caps = result['agentCapabilities']! as Map<String, Object?>;
    final meta = caps['_meta'] as Map<String, Object?>?;
    return meta?['codelab'] as Map<String, Object?>?;
  }

  /// Новое соединение к тому же серверу: `initialize` с объявлением CodeLab.
  Future<Map<String, Object?>> initializeOnNewConnection() async {
    final link = InProcessAcpLink();
    unawaited(h!.server.serve(link.agent));
    final client = TestClient(link.client);
    await client.start();
    final response = await client.request(
      'initialize',
      ServerHarness.initializeParams(clientCapabilities: codelabClient),
    );
    return response.resultMap;
  }

  // «Субагенты выключены»: `subagents.enabled: false` — блок без ключа
  // `subagents`; `tasks` есть всегда (D9).
  test('subagents.enabled false: the block has only tasks', () async {
    final source = LayeredConfigSource(
      extra: {
        'subagents': {'enabled': false},
      },
    );
    h = await ServerHarness.start(configSource: source);

    final response = await h!.initialize(clientCapabilities: codelabClient);

    expect(codelabBlock(response.resultMap), {
      'tasks': {'version': 1},
    });
  });

  // «Субагенты выключены перезагрузкой конфига» (D37): признак читается в
  // момент `initialize` по применённому конфигу, а не по сборке ядра.
  // Ответ, уже полученный первым соединением, не меняется.
  test('a reload that turns subagents off changes the next initialize '
      'only', () async {
    final source = LayeredConfigSource();
    h = await ServerHarness.start(configSource: source);
    final before = await h!.initialize(clientCapabilities: codelabClient);
    expect(codelabBlock(before.resultMap), {
      'subagents': {'version': 1, 'maxDepth': 1},
      'tasks': {'version': 1},
    });

    source.put('subagents.enabled', false);
    final report = await h!.core.runtime.reloadConfig();
    expect(report.outcome, ConfigReloadOutcome.applied);
    final after = await initializeOnNewConnection();

    expect(codelabBlock(after), {
      'tasks': {'version': 1},
    });
    // Ответ первого соединения — значение, а не живая ссылка.
    expect(codelabBlock(before.resultMap), {
      'subagents': {'version': 1, 'maxDepth': 1},
      'tasks': {'version': 1},
    });
  });

  // Т16: `maxDepth` объявления — эффективная глубина: пока ребёнку `agent` не
  // даётся (до итерации 4), она 1 даже при `subagents.max_depth: 3`.
  test('maxDepth is the effective depth, not the configured one', () async {
    final source = LayeredConfigSource(
      extra: {
        'subagents': {'max_depth': 3},
      },
    );
    h = await ServerHarness.start(configSource: source);

    final response = await h!.initialize(clientCapabilities: codelabClient);

    expect(codelabBlock(response.resultMap), {
      'subagents': {'version': 1, 'maxDepth': 1},
      'tasks': {'version': 1},
    });
  });
}
