import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import '../support/package_dir.dart';

String _fixture(String path) =>
    File(corePath('test/fixtures/sse/$path')).readAsStringSync();

final _context = LlmContext(
  systemPrompt: 'You are CodeLab.',
  messages: [
    UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
  ],
);

ModelRef _model(ProviderConfig config) => ModelRef(
  provider: config.name,
  id: 'model-1',
  api: config.api,
  baseUrl: config.baseUrl,
  contextWindow: 128000,
  maxOutputTokens: 4096,
);

void main() {
  late FakeClock clock;
  late RecordingLogger logger;

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
  });

  CoreLlmServices services(http.Client client) => CoreLlmServices(
    httpClient: client,
    clock: clock,
    random: Random(42),
    logger: logger,
  );

  test('adapter → watchdogs → retry → fallback: a failure before output is '
      'retried once', () async {
    final config = ProviderConfig(
      name: 'local',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:1234/v1'),
    );
    var requests = 0;
    final client = MockClient.streaming((request, _) async {
      requests++;
      if (requests == 1) {
        throw http.ClientException('Connection reset by peer');
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(_fixture('openai/text.sse'))),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final events = await collect(
      createStreamFunction(config, services(client))(_model(config), _context),
      clock,
    );

    expect(requests, 2);
    expect(events.whereType<StartEvent>(), hasLength(1));
    expect(events.last, isA<DoneEvent>());
    expect(terminalOf(events).content, [const TextContent('Hello, world')]);
    expect(logger.eventsOf('llm.retry'), hasLength(1));
  });

  test('the watchdog of the config times out a silent server', () async {
    final config = ProviderConfig(
      name: 'local',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:1234/v1'),
      timeouts: LlmTimeouts(connect: const Duration(seconds: 5)),
      retry: const RetryPolicy(maxAttempts: 1),
    );
    // A client that never answers and ignores abortTrigger.
    final stalled = MockClient.streaming(
      (request, _) => Completer<http.StreamedResponse>().future,
    );
    final events = <AssistantMessageEvent>[];
    var done = false;
    createStreamFunction(config, services(stalled))(
      _model(config),
      _context,
    ).listen(events.add, onDone: () => done = true);

    await clock.elapse(const Duration(seconds: 5));
    for (var i = 0; i < 10 && !done; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(done, isTrue);
    expect(terminalOf(events).errorClass, LlmErrorClass.timeout);
  });

  test('the adapter is chosen by the provider api', () async {
    final urls = <Uri>[];
    final client = MockClient.streaming((request, _) async {
      urls.add(request.url);
      final body = request.url.path.endsWith('/v1/messages')
          ? _fixture('anthropic/text.sse')
          : _fixture('openai/text.sse');
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final openai = ProviderConfig(
      name: 'openai',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://api.openai.com/v1'),
    );
    final anthropic = ProviderConfig(
      name: 'anthropic',
      api: ProviderApi.anthropicMessages,
      baseUrl: Uri.parse('https://api.anthropic.com'),
    );

    await collect(
      createStreamFunction(openai, services(client))(_model(openai), _context),
      clock,
    );
    await collect(
      createStreamFunction(anthropic, services(client))(
        _model(anthropic),
        _context,
      ),
      clock,
    );

    expect(urls.map((u) => u.path), ['/v1/chat/completions', '/v1/messages']);
  });

  test('an api without an adapter answers badRequest, never throws', () async {
    final config = ProviderConfig(
      name: 'gemini',
      api: ProviderApi.gemini,
      baseUrl: Uri.parse('https://generativelanguage.googleapis.com'),
    );

    final events = await collect(
      createStreamFunction(
        config,
        services(MockClient((_) async => http.Response('', 500))),
      )(_model(config), _context),
      clock,
    );

    expect(terminalOf(events).errorClass, LlmErrorClass.badRequest);
    expect(terminalOf(events).errorMessage, contains('gemini'));
  });
}
