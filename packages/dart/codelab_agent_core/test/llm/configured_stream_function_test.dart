import 'dart:convert';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import '../support/fake_secret_store.dart';
import '../support/provider_harness.dart';

/// Проекция `CoreConfig` в функцию модели (design.md change
/// `add-embedded-agent-mode`, решение пользователя 2026-11-02, п. A): одна
/// функция вместо двух копий проводки в `codelab-agent` и `codelab_embedded`.
void main() {
  late FakeClock clock;
  late List<http.BaseRequest> requests;
  late RecordingLogger log;

  setUp(() {
    clock = FakeClock();
    requests = [];
    log = RecordingLogger();
  });

  CoreLlmServices services() => CoreLlmServices(
    httpClient: MockClient.streaming((request, _) async {
      requests.add(request);
      return http.StreamedResponse(
        Stream.value(utf8.encode(readSseFixture('openai/text.sse'))),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }),
    clock: clock,
    random: Random(1),
    logger: log,
  );

  ModelRef modelOf(String provider) => ModelRef(
    provider: provider,
    id: 'm',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('https://$provider.test/v1'),
    contextWindow: 128000,
    maxOutputTokens: 4096,
  );

  CatalogProvider catalog(String name, {ProviderKeyRef? key}) =>
      CatalogProvider(
        ProviderConfig(
          name: name,
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('https://$name.test/v1'),
        ),
        key: key,
      );

  final context = LlmContext(
    systemPrompt: 'You are CodeLab.',
    messages: [
      UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
    ],
  );

  Future<AssistantMessage> turn(StreamFunction stream, String provider) async =>
      terminalOf(await collect(stream(modelOf(provider), context), clock));

  SecretResolver resolver(DescribedSecretStore store) =>
      SecretResolver(store: store, environment: const {}, logger: log);

  test('the key of the config provider goes to the request through the '
      'resolver', () async {
    final stream = createConfiguredStreamFunction(
      CoreConfig(
        defaultModel: modelOf('a'),
        providers: [catalog('a', key: const SecretKeyRef('codelab/a'))],
      ),
      services(),
      secrets: resolver(FakeSecretStore(values: {'codelab/a': 'sk-a-0123456'})),
    );

    final message = await turn(stream, 'a');

    expect(message.errorMessage, isNull);
    expect(requests.single.headers['Authorization'], 'Bearer sk-a-0123456');
  });

  test(
    'a provider problem of the config is an auth error without HTTP',
    () async {
      final stream = createConfiguredStreamFunction(
        CoreConfig(
          defaultModel: modelOf('a'),
          providers: [catalog('a')],
          providerProblems: const {'a': 'API key secret codelab/a is not set.'},
        ),
        services(),
      );

      final message = await turn(stream, 'a');

      expect(message.errorClass, LlmErrorClass.auth);
      expect(message.errorMessage, contains('codelab/a'));
      expect(requests, isEmpty);
    },
  );

  test('a request goes to the provider of the chosen model', () async {
    final stream = createConfiguredStreamFunction(
      CoreConfig(
        defaultModel: modelOf('a'),
        providers: [catalog('a'), catalog('b')],
      ),
      services(),
    );

    await turn(stream, 'b');

    expect(requests.single.url.host, 'b.test');
  });

  test('a header template of the config provider is rendered with the secret '
      'and the value stays out of the logs', () async {
    const value = 'org-secret-0123456789';
    final stream = createConfiguredStreamFunction(
      CoreConfig(
        defaultModel: modelOf('a'),
        providers: [
          CatalogProvider(
            catalog('a').config,
            headerTemplates: {
              'X-Test': SecretTemplate(const [
                SecretLiteral('Bearer '),
                SecretReference('codelab/a/org'),
              ]),
            },
          ),
        ],
      ),
      services(),
      secrets: resolver(FakeSecretStore(values: {'codelab/a/org': value})),
    );

    final message = await turn(stream, 'a');

    expect(message.errorMessage, isNull);
    expect(requests.single.headers['X-Test'], 'Bearer $value');
    expect(log.records.join('\n'), isNot(contains(value)));
  });
}
