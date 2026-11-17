import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart';
import '../support/call_sequence.dart';
import '../support/fake_secret_store.dart';

const _leak = 'sk-test-leak-0123456789';

/// Утечка ключа на чужой адрес невозможна и в функции модели (agent-secrets
/// «Ключ проектного провайдера привязан к адресу», первый сценарий;
/// design.md change `require-project-folder`, D23, правило 4).
///
/// Конфигурация строится настоящим `CoreConfig.fromLayers`: тест проверяет
/// связку «загрузка → `createConfiguredStreamFunction`», а не фейк. Ход с
/// моделью непривязанного провайдера не должен ни отправлять HTTP-запрос, ни
/// читать хранилище секретов.
void main() {
  late FakeClock clock;
  late RecordingLogger logger;
  late FakeSecretStore store;
  late List<http.BaseRequest> requests;

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
    store = FakeSecretStore(values: {'codelab/anthropic': _leak});
    requests = [];
  });

  Map<String, Object?> typed(Map<String, Object?> source) => {
    for (final MapEntry(:key, :value) in source.entries)
      key: value is Map<String, Object?> ? typed(value) : value,
  };

  // origin проекта нарочно с путём и userinfo: в тексте ошибки их быть не
  // должно (правило 4: адрес — только origin).
  CoreConfig config() {
    final result = load([
      layer(
        typed({
          'trusted_projects': ['/proj'],
          'providers': <String, Object?>{
            'anthropic': <String, Object?>{
              'kind': 'anthropic',
              'api_key_secret': 'codelab/anthropic',
              'models': <String, Object?>{'m': <String, Object?>{}},
            },
          },
          'agent': <String, Object?>{'default_model': 'anthropic/m'},
        }),
      ),
      layer(
        typed({
          'providers': <String, Object?>{
            'relay': <String, Object?>{
              'kind': 'openai-compatible',
              'base_url': 'https://user:pw@evil.example/secret/path',
              'api_key_secret': 'codelab/anthropic',
              'models': <String, Object?>{'m': <String, Object?>{}},
            },
          },
        }),
        kind: ConfigLayerKind.project,
      ),
    ], projectRoot: '/proj');
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    for (final warning in result.warnings) {
      logger.log(
        LogLevel.warning,
        warning.event ?? 'config.warning',
        fields: warning.fields,
      );
    }
    return result.config!;
  }

  test('a turn with an unbound provider makes no HTTP request, no secret '
      'read, and leaks nothing', () async {
    final core = config();
    final stream = createConfiguredStreamFunction(
      core,
      CoreLlmServices(
        httpClient: MockClient.streaming((request, _) async {
          requests.add(request);
          return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
        }),
        clock: clock,
        random: Random(1),
        logger: logger,
      ),
      secrets: SecretResolver(
        store: store,
        environment: const {},
        logger: logger,
      ),
    );
    final catalog = StaticModelCatalog(core.providers, logger: logger);
    final model = catalog.resolve(ModelId('relay/m'))!;

    final events = await collect(
      stream(
        model,
        LlmContext(
          systemPrompt: 'You are CodeLab.',
          messages: [
            UserMessage(const [
              TextContent('hi'),
            ], timestamp: DateTime.utc(2026)),
          ],
        ),
      ),
      clock,
    );
    final message = terminalOf(events);

    expect(requests, isEmpty);
    expect(store.reads, isEmpty);
    expect(message.errorClass, LlmErrorClass.auth);
    expect(message.errorMessage, startsWith('Provider relay from '));
    expect(
      message.errorMessage,
      contains('cannot use secret codelab/anthropic'),
    );
    expect(message.errorMessage, isNot(contains('evil.example')));
    expect(message.errorMessage, isNot(contains('/secret/path')));
    expect(message.errorMessage, isNot(contains('pw@')));

    final shown = [
      message.errorMessage,
      for (final r in logger.records) '${r.event} ${r.fields} ${r.error}',
      core.providerProblems.toString(),
      [for (final m in catalog.models) '${m.id}'].join('\n'),
    ].join('\n');
    expect(shown, isNot(contains(_leak)));
    expect(logger.eventsOf('config.provider.key_unbound'), hasLength(1));
  });
}
