import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Проекция встроенных команд `/mode` и `/model` в ACP (agent-acp-server
/// «session/new» и «session/prompt, проекция и итог хода»; design.md change
/// `add-agent-builtin-slash-commands`, D6, Q3; agent-core-architecture §13.6
/// п. 4, §13.7; ACP-3).
///
/// Почему: команду исполняет ядро без модели, смену режима или модели
/// делает агент, а не клиент, поэтому клиент узнаёт о ней только из
/// уведомлений. Порядок кадров фиксирует это требование: смена, затем текст,
/// все уведомления — до ответа на `session/prompt`. Фикстура
/// `acp/slash-mode-plan` проверяет тот же порядок по проводу, здесь — края,
/// которые фикстурой не выразить (снимок `/model`, отсутствие лишних кадров).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  Future<String> ready({List<Map<String, Object?>> steps = const []}) async {
    h = await ServerHarness.start(
      steps: steps,
      models: FixedModelCatalog([scriptedModel, _thinker]),
    );
    await h.initialize();
    final sessionId = await h.newSession();
    await h.client.drain();
    return sessionId;
  }

  /// Уведомления, пришедшие после [mark] и до ответа [response] (ACP-3).
  List<Map<String, Object?>> updatesBefore(
    JsonRpcResponse response,
    int mark,
  ) => TestClient.updates(
    h.client.received.sublist(mark, h.client.received.indexOf(response)),
  );

  List<Map<String, Object?>> optionsOf(Map<String, Object?> update) =>
      (update['configOptions']! as List).cast<Map<String, Object?>>();

  test('/mode plan: current_mode_update and config_option_update come '
      'before the text, all before the response', () async {
    final sessionId = await ready();
    final mark = h.client.received.length;

    final response = await h.prompt(sessionId, '/mode plan');
    await h.client.drain();

    expect(response.error, isNull);
    expect(response.resultMap, {'stopReason': 'end_turn'});
    final updates = updatesBefore(response, mark);
    expect(
      [for (final u in updates) u['sessionUpdate']],
      ['current_mode_update', 'config_option_update', 'agent_message_chunk'],
    );
    expect(updates[0]['currentModeId'], 'plan');
    final options = optionsOf(updates[1]);
    expect([for (final o in options) o['id']], ['mode', 'model']);
    expect(options.first['currentValue'], 'plan');
    expect((updates[2]['content']! as Map)['text'], 'Mode: plan.');
    expect(
      TestClient.updates(h.client.received.sublist(mark)).length,
      updates.length,
      reason: 'после ответа на session/prompt уведомлений хода нет',
    );
  });

  test('/model: config_option_update with the full snapshot, no '
      'current_mode_update', () async {
    final sessionId = await ready();
    final mark = h.client.received.length;

    final response = await h.prompt(sessionId, '/model scripted/thinker');
    await h.client.drain();

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final updates = updatesBefore(response, mark);
    expect(
      [for (final u in updates) u['sessionUpdate']],
      ['config_option_update', 'agent_message_chunk'],
    );
    final options = optionsOf(updates[0]);
    // У scripted/thinker `supportsReasoning`: опция `effort` обязательна
    // (ACP-10), значение по умолчанию — medium.
    expect([for (final o in options) o['id']], ['mode', 'model', 'effort']);
    expect(options.first['currentValue'], 'standard');
    expect(options.last, {
      'id': 'effort',
      'name': 'Reasoning effort',
      'category': 'thought_level',
      'type': 'select',
      'currentValue': 'medium',
      'options': [
        {'value': 'low', 'name': 'Low'},
        {'value': 'medium', 'name': 'Medium'},
        {'value': 'high', 'name': 'High'},
      ],
    });
    final model = options.singleWhere((o) => o['id'] == 'model');
    expect(model['currentValue'], 'scripted/thinker');
    expect(
      [for (final o in model['options']! as List) (o as Map)['value']],
      ['scripted/scripted-1', 'scripted/thinker'],
    );
    expect((updates[1]['content']! as Map)['text'], 'Model: scripted/thinker.');
  });

  test('/model to a model without reasoning leaves the §2.12.3 note for '
      'the next turn (effort rules §13.6, item 1)', () async {
    final sessionId = await ready(
      steps: [
        {
          'reply': [
            {'text': 'Answer.'},
          ],
        },
      ],
    );
    await h.prompt(sessionId, '/model scripted/thinker');
    await h.prompt(sessionId, '/model scripted/scripted-1');
    await h.client.drain();
    final mark = h.client.received.length;

    final response = await h.prompt(sessionId, 'Hi');

    final chunks = [
      for (final u in updatesBefore(response, mark))
        if (u['sessionUpdate'] == 'agent_message_chunk')
          (u['content']! as Map)['text'],
    ];
    expect(
      chunks.first,
      'Reasoning effort is not supported by scripted/scripted-1; the '
      'setting is kept and applies again after switching to a model with '
      'reasoning.',
    );
    expect(chunks.skip(1).join(), 'Answer.');
  });

  // Сквозной тест в настоящем ядре: смены конфигурации в нём идут по одной,
  // поэтому чужое `ModeChanged` почти всегда приходит уже после возврата
  // клиентского вызова, и путь удержания кадров не затрагивается. Он
  // проверяет итог (одно `config_option_update`, до ответа, ACP-3, ACP-11);
  // сам путь удержания проверяет `session_bridge_echo_test.dart` на
  // фальшивой сессии с явным порядком событий.
  test('/mode during a client model change: the command keeps its '
      'config_option_update before its response', () async {
    final sessionId = await ready();
    final mark = h.client.received.length;

    final client = h.client.request('session/set_config_option', {
      'sessionId': sessionId,
      'configId': 'model',
      'value': 'scripted/thinker',
    });
    final command = h.prompt(sessionId, '/mode plan');
    final responses = await Future.wait([client, command]);
    await h.client.drain();

    expect(responses[0].error, isNull);
    expect(responses[1].resultMap, {'stopReason': 'end_turn'});
    final received = h.client.received.sublist(mark);
    final configUpdates = [
      for (final f in received)
        for (final u in TestClient.updates([f]))
          if (u['sessionUpdate'] == 'config_option_update') f,
    ];
    // Клиентский запрос меняет модель, эхо `config_option_update` ему не
    // нужно; единственное уведомление принадлежит команде `/mode plan`.
    expect(configUpdates, hasLength(1));
    final commandSnapshot = TestClient.updates([configUpdates.single]).single;
    expect(optionsOf(commandSnapshot).first['currentValue'], 'plan');
    expect(
      received.indexOf(configUpdates.single),
      lessThan(received.indexOf(responses[1])),
      reason: 'кадр команды — до ответа на session/prompt (ACP-3)',
    );
  });
}

final _thinker = ModelRef(
  provider: 'scripted',
  id: 'thinker',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 64000,
  maxOutputTokens: 8192,
  supportsReasoning: true,
);
