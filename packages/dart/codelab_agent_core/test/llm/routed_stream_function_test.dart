import 'dart:convert';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import '../support/provider_harness.dart';

/// `createRoutedStreamFunction` (agent-llm «Фабрика и закрытые адаптеры»,
/// сценарии «Маршрут по провайдеру», «Провайдер без ключа»; design.md change
/// `add-agent-configuration`, D11).
void main() {
  late FakeClock clock;
  late RecordingLogger logger;
  late List<Uri> urls;

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
    urls = [];
  });

  http.Client client() => MockClient.streaming((request, _) async {
    urls.add(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(readSseFixture('openai/text.sse'))),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });

  CoreLlmServices services() => CoreLlmServices(
    httpClient: client(),
    clock: clock,
    random: Random(1),
    logger: logger,
  );

  ProviderConfig provider(String name, String base) => ProviderConfig(
    name: name,
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse(base),
  );

  ModelRef model(String providerName, String base) => ModelRef(
    provider: providerName,
    id: 'm',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse(base),
    contextWindow: 128000,
    maxOutputTokens: 4096,
  );

  final context = LlmContext(
    systemPrompt: 'You are CodeLab.',
    messages: [
      UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
    ],
  );

  test('a request goes only to the provider of the model', () async {
    final stream = createRoutedStreamFunction([
      provider('a', 'https://a.test/v1'),
      provider('b', 'https://b.test/v1'),
    ], services());

    final events = await collect(
      stream(model('b', 'https://b.test/v1'), context),
      clock,
    );

    expect(events.last, isA<DoneEvent>());
    expect(urls.map((u) => u.host).toSet(), {'b.test'});
  });

  test(
    'the chain of a provider is created at its first request, once',
    () async {
      final stream = createRoutedStreamFunction([
        provider('a', 'https://a.test/v1'),
        provider('b', 'https://b.test/v1'),
      ], services());

      await collect(stream(model('a', 'https://a.test/v1'), context), clock);
      await collect(stream(model('a', 'https://a.test/v1'), context), clock);

      expect(urls.map((u) => u.host), ['a.test', 'a.test']);
    },
  );

  test(
    'a provider from unavailable fails with auth and sends no request',
    () async {
      final stream = createRoutedStreamFunction(
        [provider('openai', 'https://api.openai.com/v1')],
        services(),
        unavailable: {'openai': 'API key variable OPENAI_API_KEY is not set'},
      );

      final events = await collect(
        stream(model('openai', 'https://api.openai.com/v1'), context),
        clock,
      );

      final message = terminalOf(events);
      expect(message.errorClass, LlmErrorClass.auth);
      expect(
        message.errorMessage,
        'API key variable OPENAI_API_KEY is not set',
      );
      expect(urls, isEmpty);
    },
  );

  test('an unavailable provider does not stop the others', () async {
    final stream = createRoutedStreamFunction(
      [
        provider('openai', 'https://api.openai.com/v1'),
        provider('b', 'https://b.test/v1'),
      ],
      services(),
      unavailable: {'openai': 'no key'},
    );

    final events = await collect(
      stream(model('b', 'https://b.test/v1'), context),
      clock,
    );

    expect(events.last, isA<DoneEvent>());
  });

  test('an unknown provider is a badRequest', () async {
    final stream = createRoutedStreamFunction([
      provider('a', 'https://a.test/v1'),
    ], services());

    final events = await collect(
      stream(model('zzz', 'https://z.test/v1'), context),
      clock,
    );

    final message = terminalOf(events);
    expect(message.errorClass, LlmErrorClass.badRequest);
    expect(message.errorMessage, 'unknown provider zzz');
    expect(urls, isEmpty);
  });
}
