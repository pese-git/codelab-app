import 'dart:convert';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' as cfg;
import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../session/recording_store.dart';
import '../support/call_sequence.dart';
import '../support/fake_secret_store.dart';
import '../support/provider_harness.dart';

// Заведомо фиктивные значения.
const _key = 'sk-test-0123456789abcdef';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
const _base = 'https://api.example/v1';
const _migrate = 'run: codelab secret migrate';

/// Ключ провайдера при запросе: литерал файла и ссылка-значение (agent-secrets
/// «Ключ провайдера при запросе» и «Секреты MCP-серверов конфигурации»;
/// design.md change `add-config-literal-secrets-and-migrate`, D4, D2, R8-4;
/// задача 1.3).
void main() {
  late FakeClock clock;
  late RecordingLogger logger;
  late List<http.BaseRequest> requests;
  late int status;
  late String responseBody;

  setUp(() {
    clock = FakeClock();
    logger = RecordingLogger();
    requests = [];
    status = 200;
    responseBody = readSseFixture('openai/text.sse');
  });

  CoreLlmServices services() => CoreLlmServices(
    httpClient: MockClient.streaming((request, _) async {
      requests.add(request);
      return http.StreamedResponse(
        Stream.value(utf8.encode(responseBody)),
        status,
        headers: {'content-type': 'text/event-stream'},
      );
    }),
    clock: clock,
    random: Random(1),
    logger: logger,
  );

  ProviderConfig provider({String? apiKey}) => ProviderConfig(
    name: 'openai',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse(_base),
    apiKey: apiKey,
  );

  final model = ModelRef(
    provider: 'openai',
    id: 'm',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse(_base),
    contextWindow: 128000,
    maxOutputTokens: 4096,
  );

  final context = LlmContext(
    systemPrompt: 'You are CodeLab.',
    messages: [
      UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
    ],
  );

  Future<AssistantMessage> turn(StreamFunction stream) async =>
      terminalOf(await collect(stream(model, context), clock));

  String logText() => [
    for (final r in logger.records) '${r.event} ${r.fields} ${r.error}',
  ].join('\n');

  group('a literal api_key from the file', () {
    test('goes into the request as is, without a resolver', () async {
      final stream = createRoutedStreamFunction([
        provider(apiKey: _key),
      ], services());

      final ok = await turn(stream);

      expect(ok.errorMessage, isNull);
      expect(requests.single.headers['Authorization'], 'Bearer $_key');
    });

    test('is scrubbed from the text of a 401 and from the log', () async {
      status = 401;
      responseBody =
          '{"error":{"message":"Incorrect API key provided: $_key"}}';
      final stream = createRoutedStreamFunction([
        provider(apiKey: _key),
      ], services());

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(failed.errorMessage, isNot(contains(_key)));
      expect(failed.errorMessage, contains('[REDACTED]'));
      expect(logText(), isNot(contains(_key)));
    });

    test('a literal key shorter than 8 characters is not scrubbed (D4, '
        'Risks); other keys are scrubbed at any length', () {
      for (final (short, scrubbed) in [
        ('x', false),
        ('ollama', false),
        ('abcdefg', false),
        ('abcdefgh', true),
      ]) {
        final config = ProviderConfig(
          name: 'p',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse(_base),
          apiKey: short,
          literalApiKey: true,
        );
        expect(config.secrets.contains(short), scrubbed, reason: short);
      }
      // Ключ хоста или хранилища — без порога, как раньше.
      expect(provider(apiKey: 'abc').secrets, contains('abc'));
    });

    test('a 5-character key from the store is scrubbed from a 401', () async {
      status = 401;
      responseBody = '{"error":{"message":"bad key ab123"}}';
      final stream = createRoutedStreamFunction(
        [provider()],
        services(),
        keys: const {'openai': SecretKeyRef('codelab/openai')},
        secrets: SecretResolver(
          store: FakeSecretStore(values: {'codelab/openai': 'ab123'}),
          environment: const {},
          logger: logger,
        ),
      );

      final failed = await turn(stream);

      expect(failed.errorMessage, isNot(contains('ab123')));
    });

    test('a FormatException that quotes the key leaves no value in the '
        'error text (5)', () async {
      const bad = 'sk-test-0123456789\u00a0abcdef';
      final stream = createRoutedStreamFunction(
        [provider(apiKey: bad)],
        CoreLlmServices(
          httpClient: MockClient.streaming((request, _) async {
            throw FormatException(
              'Invalid HTTP header field value: "Bearer $bad"',
            );
          }),
          clock: clock,
          random: Random(1),
          logger: logger,
        ),
      );

      final failed = await turn(stream);

      expect(failed.errorMessage, isNotNull);
      expect(failed.errorMessage, isNot(contains('0123456789')));
      expect(logText(), isNot(contains('0123456789')));
    });

    test('is kept when the provider also has header references', () async {
      final store = FakeSecretStore(values: {'codelab/openai/org': 'org-42'});
      final stream = createRoutedStreamFunction(
        [provider(apiKey: _key)],
        services(),
        headerTemplates: {
          'openai': {
            'X-Org': SecretTemplate(const [
              SecretReference('codelab/openai/org'),
            ]),
          },
        },
        secrets: SecretResolver(
          store: store,
          environment: const {},
          logger: logger,
        ),
      );

      final ok = await turn(stream);

      expect(ok.errorMessage, isNull);
      expect(requests.single.headers['Authorization'], 'Bearer $_key');
      expect(requests.single.headers['X-Org'], 'org-42');
    });

    test(
      'end to end: a loaded config feeds the request and the 401 text',
      () async {
        final result = cfg.load([
          cfg.layer(
            cfg.withValues(cfg.baseValues(), {
              'providers': {
                'openai': {
                  'kind': 'openai-compatible',
                  'base_url': _base,
                  'api_key': _key,
                },
              },
            }),
          ),
        ]);
        final providers = result.config!.providers;
        status = 401;
        responseBody = '{"error":{"message":"bad key $_key"}}';
        final stream = createRoutedStreamFunction(
          [for (final p in providers) p.config],
          services(),
          keys: {
            for (final p in providers)
              if (p.key != null) p.config.name: p.key!,
          },
        );

        final failed = await turn(stream);

        expect(requests.single.headers['Authorization'], 'Bearer $_key');
        expect(failed.errorMessage, isNot(contains(_key)));
      },
    );
  });

  group('a reference that is a secret value (CFG-9 p.3)', () {
    test(
      'api_key_env: auth without HTTP, no store read, no value anywhere',
      () async {
        final store = FakeSecretStore(values: {_github: 'x'});
        final stream = createRoutedStreamFunction(
          [provider()],
          services(),
          keys: const {
            'openai': UnusableKeyRef('providers.openai.api_key_env'),
          },
          secrets: SecretResolver(
            store: store,
            environment: {_github: 'y'},
            logger: logger,
            debug: true,
          ),
        );

        final failed = await turn(stream);

        expect(failed.errorClass, LlmErrorClass.auth);
        expect(
          failed.errorMessage,
          'API key reference providers.openai.api_key_env looks like a secret '
          'value, not a name; $_migrate',
        );
        expect(requests, isEmpty);
        expect(store.reads, isEmpty);
        expect(logger.eventsOf('secrets.lookup'), isEmpty);
        expect(logText(), isNot(contains(_github)));
      },
    );

    test(
      'also without a resolver: the same text, not "no secret resolver"',
      () async {
        final stream = createRoutedStreamFunction(
          [provider()],
          services(),
          keys: const {
            'openai': UnusableKeyRef('providers.openai.api_key_secret'),
          },
        );

        final failed = await turn(stream);

        expect(failed.errorClass, LlmErrorClass.auth);
        expect(
          failed.errorMessage,
          'API key reference providers.openai.api_key_secret looks like a '
          'secret value, not a name; $_migrate',
        );
        expect(requests, isEmpty);
      },
    );

    test(
      'markers of every template are checked before the store is read',
      () async {
        final store = FakeSecretStore(values: {'codelab/openai': 'x'});
        final stream = createRoutedStreamFunction(
          [provider()],
          services(),
          keys: const {'openai': SecretKeyRef('codelab/openai')},
          headerTemplates: {
            'openai': {
              'X-Org': SecretTemplate(const [UnusableSecretReference()]),
            },
          },
          secrets: SecretResolver(
            store: store,
            environment: const {},
            logger: logger,
          ),
        );

        final failed = await turn(stream);

        expect(failed.errorClass, LlmErrorClass.auth);
        expect(failed.errorMessage, contains('providers.openai.headers.X-Org'));
        expect(store.reads, isEmpty);
      },
    );

    test('a header template with a marker fails the same way and names the '
        'header', () async {
      final store = FakeSecretStore();
      final stream = createRoutedStreamFunction(
        [provider()],
        services(),
        headerTemplates: {
          'openai': {
            'X-Org': SecretTemplate(const [
              SecretLiteral('Org '),
              UnusableSecretReference(),
            ]),
          },
        },
        secrets: SecretResolver(
          store: store,
          environment: const {},
          logger: logger,
        ),
      );

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(
        failed.errorMessage,
        'API key reference providers.openai.headers.X-Org looks like a secret '
        'value, not a name; $_migrate',
      );
      expect(requests, isEmpty);
      expect(store.reads, isEmpty);
    });
  });

  group('an MCP server with such a reference', () {
    test('is failed with the same text, the store is never asked', () async {
      final store = FakeSecretStore(values: {_github: 'x'});
      final mcp = FakeMcpConnector();
      final resolver = SecretResolver(
        store: store,
        environment: const {},
        logger: RecordingLogger(),
      );
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        steps: const [],
        sessions: RecordingStore(),
        mcp: mcp,
        mcpServers: [
          McpHttpServerConfig(
            name: 'gh',
            url: Uri.parse('https://gh.example.com/mcp'),
            origin: McpServerOrigin.config,
            secretValues: {
              'headers.Authorization': SecretTemplate(const [
                SecretLiteral('Bearer '),
                UnusableSecretReference(),
              ]),
            },
          ),
        ],
        secrets: resolver,
      );

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      expect(mcp.expandFailures.single, {
        'gh':
            'secret reference mcp.servers[gh].headers.Authorization looks '
            'like a secret value, not a name; $_migrate',
      });
      expect(mcp.expanded.single, isEmpty);
      expect(store.reads, isEmpty);
    });
  });
}
