import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Неявная модель в ACP-проекции без правки кода проекции (agent-runtime
/// «Модель новой сессии», «Последняя выбранная модель»; design.md change
/// `optional-default-model`, D11; задача 2.3): `session/new` не передаёт
/// модель, `currentValue` опции `model` берётся из выбора рантайма, а
/// `session/set_config_option` опции `model` пишет последнюю модель в порт.
void main() {
  late ServerHarness h;

  final thinker = ModelRef(
    provider: 'scripted',
    id: 'thinker',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 64000,
    maxOutputTokens: 8192,
  );

  tearDown(() => h.dispose());

  Future<ServerHarness> start(_FakeLastModel last) async {
    h = await ServerHarness.start(
      models: FixedModelCatalog([scriptedModel, thinker]),
      defaultModelSource: DefaultModelSource.firstProvider,
      lastModel: last,
    );
    await h.initialize();
    return h;
  }

  Map<String, Object?> modelOption(Object? options) => (options! as List)
      .cast<Map<String, Object?>>()
      .singleWhere((o) => o['id'] == 'model');

  test('session/new without a model key: currentValue is the last model '
      'when the catalog knows it', () async {
    await start(_FakeLastModel(const ModelId('scripted/thinker')));

    final response = await h.client.request('session/new', {
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });

    expect(
      modelOption(response.resultMap['configOptions'])['currentValue'],
      'scripted/thinker',
    );
  });

  test('session/new without a model key and without a last model: '
      'currentValue is the implicit model of the config', () async {
    await start(_FakeLastModel(null));

    final response = await h.client.request('session/new', {
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });

    expect(
      modelOption(response.resultMap['configOptions'])['currentValue'],
      'scripted/scripted-1',
    );
  });

  test('set_config_option model writes the last model; session/new alone '
      'does not', () async {
    final last = _FakeLastModel(null);
    await start(last);
    final response = await h.client.request('session/new', {
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    await h.client.next();
    expect(last.writes, isEmpty);

    await h.client.request('session/set_config_option', {
      'sessionId': response.resultMap['sessionId'],
      'configId': 'model',
      'value': 'scripted/thinker',
    });

    expect(last.writes, [const ModelId('scripted/thinker')]);
  });
}

final class _FakeLastModel implements LastModelStore {
  _FakeLastModel(this.stored);

  final ModelId? stored;
  final writes = <ModelId>[];

  @override
  Future<ModelId?> read() async => stored;

  @override
  Future<void> write(ModelId model) async => writes.add(model);
}
