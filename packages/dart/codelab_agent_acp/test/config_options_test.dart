import 'package:acp_protocol/acp_protocol.dart' show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «Режимы и опции сессии» (задача 7.3; §13.6, §2.12.3;
/// ACP-10, ACP-11).
void main() {
  late ServerHarness h;
  ServerHarness? second;

  final thinker = ModelRef(
    provider: 'scripted',
    id: 'thinker',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 64000,
    maxOutputTokens: 8192,
    supportsReasoning: true,
  );

  tearDown(() async {
    await second?.dispose();
    second = null;
    await h.dispose();
  });

  Future<String> ready({List<Map<String, Object?>> steps = const []}) async {
    h = await ServerHarness.start(
      steps: steps,
      models: FixedModelCatalog([scriptedModel, thinker]),
    );
    await h.initialize();
    return h.newSession();
  }

  Future<JsonRpcResponse> set(
    String sessionId,
    String configId,
    String value,
  ) => h.client.request('session/set_config_option', {
    'sessionId': sessionId,
    'configId': configId,
    'value': value,
  });

  List<Object?> idsOf(Object? options) => [
    for (final o in options! as List) (o! as Map)['id'],
  ];

  Map<String, Object?> optionOf(Object? options, String id) =>
      (options! as List).cast<Map<String, Object?>>().singleWhere(
        (o) => o['id'] == id,
      );

  List<Map<String, Object?>> updatesBefore(JsonRpcResponse response) =>
      TestClient.updates(
        h.client.received.take(h.client.received.indexOf(response)),
      );

  test('model lists the catalog; effort appears with reasoning', () async {
    final sessionId = await ready();

    final response = await set(sessionId, 'model', 'scripted/thinker');

    final options = response.resultMap['configOptions'];
    expect(idsOf(options), ['mode', 'model', 'effort']);
    expect(optionOf(options, 'model')['currentValue'], 'scripted/thinker');
    expect(optionOf(options, 'model')['options'], [
      {'value': 'scripted/scripted-1', 'name': 'scripted-1'},
      {'value': 'scripted/thinker', 'name': 'thinker'},
    ]);
    expect(optionOf(options, 'effort'), {
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
    // Ответ на запрос клиента не дублируется уведомлением (ACP-11).
    expect(
      updatesBefore(
        response,
      ).where((u) => u['sessionUpdate'] == 'config_option_update'),
      isEmpty,
    );
  });

  test('mode: current_mode_update first, then the full list', () async {
    final sessionId = await ready();
    await h.client.drain();
    final mark = h.client.received.length;

    final response = await set(sessionId, 'mode', 'plan');

    final updates = TestClient.updates(
      h.client.received.sublist(mark, h.client.received.indexOf(response)),
    );
    expect(updates, [
      {'sessionUpdate': 'current_mode_update', 'currentModeId': 'plan'},
    ]);
    expect(
      optionOf(response.resultMap['configOptions'], 'mode')['currentValue'],
      'plan',
    );
  });

  test('legacy synonyms are accepted and never sent out', () async {
    final sessionId = await ready();

    final response = await set(sessionId, 'mode', 'architect');

    expect(
      optionOf(response.resultMap['configOptions'], 'mode')['currentValue'],
      'plan',
    );
  });

  test('unknown option, value, session and effort without reasoning', () async {
    final sessionId = await ready();

    expect((await set(sessionId, 'colour', 'red')).errorCode, -32602);
    expect((await set(sessionId, 'mode', 'yolo')).errorCode, -32602);
    expect((await set(sessionId, 'model', 'scripted/none')).errorCode, -32602);
    expect((await set(sessionId, 'effort', 'high')).errorCode, -32602);
    expect(
      (await set('01JB8Q2W6R9T3M5K7N1P4X8Z0C', 'mode', 'plan')).errorCode,
      -32002,
    );
  });

  test('effort is kept across model switches (ACP-10)', () async {
    final sessionId = await ready();
    await set(sessionId, 'model', 'scripted/thinker');
    await set(sessionId, 'effort', 'high');

    final plain = await set(sessionId, 'model', 'scripted/scripted-1');
    final back = await set(sessionId, 'model', 'scripted/thinker');

    expect(idsOf(plain.resultMap['configOptions']), ['mode', 'model']);
    expect(
      optionOf(back.resultMap['configOptions'], 'effort')['currentValue'],
      'high',
    );
  });

  test('effort and model survive session/load', () async {
    final sessionId = await ready();
    await set(sessionId, 'model', 'scripted/thinker');
    await set(sessionId, 'effort', 'low');
    second = await ServerHarness.start(
      sessions: h.store,
      models: FixedModelCatalog([scriptedModel, thinker]),
    );
    await second!.initialize();

    final response = await second!.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });

    final options = response.resultMap['configOptions'];
    expect(optionOf(options, 'model')['currentValue'], 'scripted/thinker');
    expect(optionOf(options, 'effort')['currentValue'], 'low');
  });

  test('session/set_mode answers {} after current_mode_update', () async {
    final sessionId = await ready();
    await h.client.drain();
    final mark = h.client.received.length;

    final response = await h.client.request('session/set_mode', {
      'sessionId': sessionId,
      'modeId': 'code',
    });

    expect(response.resultMap, isEmpty);
    expect(
      TestClient.updates(
        h.client.received.sublist(mark, h.client.received.indexOf(response)),
      ),
      [
        {'sessionUpdate': 'current_mode_update', 'currentModeId': 'bypass'},
      ],
    );
  });

  test('switching to a model without reasoning: one note next turn', () async {
    final sessionId = await ready(
      steps: [
        {
          'reply': [
            {'text': 'Answer one.'},
          ],
        },
        {
          'reply': [
            {'text': 'Answer two.'},
          ],
        },
      ],
    );
    await set(sessionId, 'model', 'scripted/thinker');
    await set(sessionId, 'model', 'scripted/scripted-1');
    await h.client.drain();

    final first = await h.prompt(sessionId, 'One');
    final chunks = [
      for (final u in updatesBefore(first))
        if (u['sessionUpdate'] == 'agent_message_chunk')
          (u['content']! as Map)['text'],
    ];
    await h.client.drain();
    final secondTurn = await h.prompt(sessionId, 'Two');

    expect(
      chunks.first,
      'Reasoning effort is not supported by scripted/scripted-1; the '
      'setting is kept and applies again after switching to a model with '
      'reasoning.',
    );
    expect(chunks.skip(1).join(), 'Answer one.');
    final received = h.client.received;
    expect(
      [
        for (final u in TestClient.updates(
          received.sublist(
            received.indexOf(first) + 1,
            received.indexOf(secondTurn),
          ),
        ))
          if (u['sessionUpdate'] == 'agent_message_chunk')
            (u['content']! as Map)['text'],
      ].join(),
      'Answer two.',
    );
    // Заметка не уходит модели и не пишется в журнал (§2.12.3).
    for (final request in h.model.requests) {
      for (final message in request.messages) {
        for (final block in message.content.whereType<TextContent>()) {
          expect(block.text, isNot(contains('Reasoning effort')));
        }
      }
    }
  });
}
