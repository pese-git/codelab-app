import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Живая проекция итога субагента, оборванного лимитом ответа (agent-acp-server
/// «Проекция субагентов и списка задач», agent-subagents «Пустой отчёт по
/// лимиту ответа» и «Оборванный отчёт по лимиту ответа»; design.md change
/// `add-subagents-and-tasks` D41 п. 6, задача 2.20).
///
/// Почему отдельный файл: значение `failure: "max_tokens"` рождается в ядре
/// (`SubagentFailure.maxTokens`, `failureWire`), которого ещё нет; пока ядро не
/// готово, тесты красные, а остальные файлы пакета не затронуты. Проекция
/// `subagentSummaryMeta` отдаёт `failureWire` как есть, поэтому после правки
/// ядра адаптер, скорее всего, менять не придётся.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  const exploreArgs = {
    'type': 'explore',
    'description': 'Find auth code',
    'prompt': 'Find where authentication is implemented.',
  };

  Map<String, Object?> agentCall() => {
    'reply': [
      {
        'toolCall': {'id': 'call_1', 'name': 'agent', 'arguments': exploreArgs},
      },
    ],
  };

  /// Корень, ребёнок с ответом [childStep] (в нём `stopReason: length`) и
  /// финальный ответ корня.
  Future<String> ready(Map<String, Object?> childStep) async {
    // D40: окно модели не меньше порога видимости `agent`.
    h = await ServerHarness.start(
      steps: [
        agentCall(),
        childStep,
        {
          'reply': [
            {'text': 'Done.'},
          ],
        },
      ],
      configSource: LayeredConfigSource(
        extra: {
          'providers': {
            'a': {
              'kind': 'openai-compatible',
              'base_url': 'https://a.test/v1',
              'models': {
                'm1': {'context_window': 65536},
              },
            },
          },
        },
      ),
    );
    await h.initialize();
    return h.newSession();
  }

  Map<String, Object?> finalUpdate(Iterable<Map<String, Object?>> updates) =>
      updates.lastWhere(
        (u) =>
            u['toolCallId'] == 'call_1' &&
            (u['status'] == 'completed' || u['status'] == 'failed'),
      );

  Map<String, Object?> subagentMeta(Map<String, Object?> update) =>
      ((((update['_meta']! as Map)['codelab']! as Map)['subagent']!) as Map)
          .cast<String, Object?>();

  String bodyText(Map<String, Object?> update) =>
      (((update['content']! as List).single as Map)['content']! as Map)['text']!
          as String;

  test('an empty report cut by the output limit: failed with '
      'failure max_tokens', () async {
    final sessionId = await ready({
      'reply': <Object?>[],
      'stopReason': 'length',
    });

    final response = await h.prompt(sessionId, 'Where is auth?');

    final updates = TestClient.updates(
      h.client.received.take(h.client.received.indexOf(response)),
    );
    final done = finalUpdate(updates);
    expect(done['status'], 'failed');
    expect(subagentMeta(done)['failure'], 'max_tokens');
    expect(
      bodyText(done),
      contains('hit the output token limit before writing a report'),
    );
  });

  test('a truncated non-empty report: completed, no failure, the marker '
      'is in the text', () async {
    final sessionId = await ready({
      'reply': [
        {'text': 'Found three callers: a.dart, b.dart'},
      ],
      'stopReason': 'length',
    });

    final response = await h.prompt(sessionId, 'Where is auth?');

    final updates = TestClient.updates(
      h.client.received.take(h.client.received.indexOf(response)),
    );
    final done = finalUpdate(updates);
    expect(done['status'], 'completed');
    expect(subagentMeta(done), isNot(contains('failure')));
    expect(
      bodyText(done),
      allOf(
        contains('Found three callers: a.dart, b.dart'),
        contains('[report truncated: the subagent hit the output token limit]'),
      ),
    );
  });
}
