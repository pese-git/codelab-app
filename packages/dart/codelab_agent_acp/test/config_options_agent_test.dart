import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Опция `agent` (agent-acp-server «Режимы и опции сессии»; design.md change
/// `add-agent-project-files`, D12; CFG-6, CFG-8, ACP-11). Фикстура
/// `acp/set-config-option-agent` покрывает счастливый путь, здесь — края.
void main() {
  ServerHarness? h;

  tearDown(() async => h?.dispose());

  MarkdownFile agentFile(String name, {required String mode, String? model}) =>
      MarkdownFile(
        path: '/home/.codelab/agents/$name.md',
        scope: ExtensionScope.user,
        body: 'Be $name.',
        bodyLine: 6,
        frontmatter: ConfigTree(
          kind: ConfigLayerKind.user,
          source: '/home/.codelab/agents/$name.md',
          values: {
            'name': name,
            'description': 'The $name agent',
            'mode': mode,
            'model': ?model,
          },
        ),
      );

  Future<String> ready(List<MarkdownFile> agents) async {
    final started = h = await ServerHarness.start(
      projectFiles: _FixedFiles(ProjectFiles(agents: agents)),
      models: FixedModelCatalog([scriptedModel, _thinker]),
    );
    await started.initialize();
    return started.newSession();
  }

  Future<JsonRpcResponse> set(String sessionId, String value) =>
      h!.client.request('session/set_config_option', {
        'sessionId': sessionId,
        'configId': 'agent',
        'value': value,
      });

  List<Map<String, Object?>> options(JsonRpcResponse response) =>
      (response.resultMap['configOptions']! as List)
          .cast<Map<String, Object?>>();

  test('without definitions there is no agent option and no value', () async {
    final sessionId = await ready(const []);

    final response = await set(sessionId, 'default');

    expect(response.errorCode, -32602);
  });

  test('agent option comes last, has no category and lists agents', () async {
    final sessionId = await ready([agentFile('reviewer', mode: 'plan')]);

    final response = await set(sessionId, 'default');

    final list = options(response);
    expect([for (final o in list) o['id']], ['mode', 'model', 'agent']);
    final agent = list.last;
    expect(agent.containsKey('category'), isFalse);
    expect(agent['currentValue'], 'default');
    expect(agent['options'], [
      {'value': 'default', 'name': 'Default'},
      {
        'value': 'reviewer',
        'name': 'reviewer',
        'description': 'The reviewer agent',
      },
    ]);
  });

  test('an unknown value is -32602 and nothing changes', () async {
    final sessionId = await ready([agentFile('reviewer', mode: 'plan')]);
    await h!.client.drain();
    final mark = h!.client.received.length;

    final bad = await set(sessionId, 'ghost');
    final after = await set(sessionId, 'default');

    expect(bad.errorCode, -32602);
    final agent = options(after).singleWhere((o) => o['id'] == 'agent');
    expect(agent['currentValue'], 'default');
    expect(
      options(after).singleWhere((o) => o['id'] == 'mode')['currentValue'],
      'standard',
    );
    expect(
      TestClient.updates(h!.client.received.sublist(mark)),
      isEmpty,
      reason: 'ошибка не шлёт ни current_mode_update, ни config_option_update',
    );
  });

  test('a stricter agent mode: current_mode_update before the response, '
      'no config_option_update', () async {
    final sessionId = await ready([agentFile('reviewer', mode: 'plan')]);
    await h!.client.drain();
    final mark = h!.client.received.length;

    final response = await set(sessionId, 'reviewer');

    final updates = TestClient.updates(
      h!.client.received.sublist(mark, h!.client.received.indexOf(response)),
    );
    expect(updates, [
      {'sessionUpdate': 'current_mode_update', 'currentModeId': 'plan'},
    ]);
    expect(
      options(response).singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'reviewer',
    );
  });

  test('a softer agent mode is not applied: no current_mode_update '
      '(OQ3)', () async {
    final sessionId = await ready([agentFile('loose', mode: 'bypass')]);
    await h!.client.drain();
    final mark = h!.client.received.length;

    final response = await set(sessionId, 'loose');

    expect(response.error, isNull);
    expect(
      TestClient.updates(
        h!.client.received.sublist(mark, h!.client.received.indexOf(response)),
      ),
      isEmpty,
    );
    final list = options(response);
    expect(
      list.singleWhere((o) => o['id'] == 'mode')['currentValue'],
      'standard',
    );
    expect(
      list.singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'loose',
    );
  });

  test('parallel agent and set_mode: one response each, no '
      'config_option_update, order as in the spec', () async {
    final sessionId = await ready([agentFile('reviewer', mode: 'plan')]);
    await h!.client.drain();
    final mark = h!.client.received.length;

    final first = h!.client.request('session/set_config_option', {
      'sessionId': sessionId,
      'configId': 'agent',
      'value': 'reviewer',
    });
    final second = h!.client.request('session/set_mode', {
      'sessionId': sessionId,
      'modeId': 'bypass',
    });
    final r1 = await first.timeout(const Duration(seconds: 5));
    final r2 = await second.timeout(const Duration(seconds: 5));
    await h!.client.drain();

    final frames = h!.client.received.sublist(mark);
    expect(
      [
        for (final f in frames)
          if (f == r1)
            'response:agent'
          else if (f == r2)
            'response:mode'
          else
            for (final u in TestClient.updates([f]))
              '${u['sessionUpdate']}:${u['currentModeId']}',
      ],
      [
        'current_mode_update:plan',
        'response:agent',
        'current_mode_update:bypass',
        'response:mode',
      ],
    );
    final list = options(r1);
    expect(
      list.singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'reviewer',
    );
    expect(list.singleWhere((o) => o['id'] == 'mode')['currentValue'], 'plan');
    final load = await h!.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    expect(
      options(load).singleWhere((o) => o['id'] == 'mode')['currentValue'],
      'bypass',
      reason: 'итог — последний запрос',
    );
  });

  test('two parallel agent selections: both answer, the last wins', () async {
    final sessionId = await ready([
      agentFile('reviewer', mode: 'plan'),
      agentFile('writer', mode: 'standard'),
    ]);
    await h!.client.drain();
    final mark = h!.client.received.length;

    final first = set(sessionId, 'reviewer');
    final second = set(sessionId, 'writer');
    final r1 = await first.timeout(const Duration(seconds: 5));
    final r2 = await second.timeout(const Duration(seconds: 5));
    await h!.client.drain();

    expect(
      options(r1).singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'reviewer',
    );
    expect(
      options(r2).singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'writer',
    );
    expect(
      [
        for (final u in TestClient.updates(h!.client.received.sublist(mark)))
          u['sessionUpdate'],
      ],
      everyElement('current_mode_update'),
      reason: 'config_option_update не дублирует ответы (ACP-11)',
    );
  });

  test('an agent switching to a model without reasoning leaves the effort '
      'note', () async {
    final sessionId = await ready([
      agentFile('plain', mode: 'standard', model: 'scripted/scripted-1'),
    ]);
    await h!.client.request('session/set_config_option', {
      'sessionId': sessionId,
      'configId': 'model',
      'value': 'scripted/thinker',
    });

    final response = await set(sessionId, 'plain');

    expect(options(response).map((o) => o['id']), isNot(contains('effort')));
    await h!.client.drain();
    final turn = await h!.prompt(sessionId, 'Hi');
    final chunks = [
      for (final u in TestClient.updates(
        h!.client.received.take(h!.client.received.indexOf(turn)),
      ))
        if (u['sessionUpdate'] == 'agent_message_chunk')
          (u['content']! as Map)['text'],
    ];
    expect(
      chunks.first,
      startsWith('Reasoning effort is not supported by scripted/scripted-1;'),
    );
  });

  test('session/load replays the agent option with the chosen agent', () async {
    final sessionId = await ready([agentFile('reviewer', mode: 'plan')]);
    await set(sessionId, 'reviewer');
    await h!.client.drain();
    final mark = h!.client.received.length;

    final load = await h!.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });

    expect(load.error, isNull);
    final received = h!.client.received;
    final replay = TestClient.updates(
      received.sublist(mark, received.indexOf(load)),
    ).where((u) => u['sessionUpdate'] == 'config_option_update').single;
    final agent = (replay['configOptions']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((o) => o['id'] == 'agent');
    expect(agent['currentValue'], 'reviewer');
    expect(
      options(load).singleWhere((o) => o['id'] == 'agent')['currentValue'],
      'reviewer',
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

final class _FixedFiles implements ProjectFilesSource {
  const _FixedFiles(this.files);

  final ProjectFiles files;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async => files;
}
