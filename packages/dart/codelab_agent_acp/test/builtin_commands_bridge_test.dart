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

  Future<String> ready() async {
    h = await ServerHarness.start(
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
    expect([for (final o in options) o['id']], ['mode', 'model']);
    expect(options.first['currentValue'], 'standard');
    final model = options.last;
    expect(model['currentValue'], 'scripted/thinker');
    expect(
      [for (final o in model['options']! as List) (o as Map)['value']],
      ['scripted/scripted-1', 'scripted/thinker'],
    );
    expect((updates[1]['content']! as Map)['text'], 'Model: scripted/thinker.');
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
