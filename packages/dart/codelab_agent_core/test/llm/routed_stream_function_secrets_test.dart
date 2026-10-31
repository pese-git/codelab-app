import 'dart:async';
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

const _key = 'sk-test-0123456789abcdef';
const _base = 'https://api.example/v1';

/// Ключ провайдера при запросе (agent-secrets «Ключ провайдера при
/// запросе»; design.md change `add-agent-secret-store`, D4, D12).
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

  final provider = ProviderConfig(
    name: 'openai',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse(_base),
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

  SecretResolver resolver(
    DescribedSecretStore store, {
    Map<String, String> environment = const {},
    bool debug = false,
  }) => SecretResolver(
    store: store,
    environment: environment,
    logger: logger,
    debug: debug,
  );

  StreamFunction routed({
    Map<String, ProviderKeyRef> keys = const {},
    Map<String, Map<String, SecretTemplate>> headerTemplates = const {},
    SecretResolver? secrets,
    Map<String, String> unavailable = const {},
  }) => createRoutedStreamFunction(
    [provider],
    services(),
    keys: keys,
    headerTemplates: headerTemplates,
    secrets: secrets,
    unavailable: unavailable,
  );

  const secretKey = {'openai': SecretKeyRef('codelab/openai')};

  Future<AssistantMessage> turn(
    StreamFunction stream, {
    CancelToken? cancel,
  }) async {
    final events = await collect(stream(model, context, cancel: cancel), clock);
    return terminalOf(events);
  }

  String? authorization(int i) => requests[i].headers['Authorization'];

  group('api_key_secret', () {
    test('the key comes from the store; two turns make one read', () async {
      final store = FakeSecretStore(values: {'codelab/openai': _key});
      final stream = routed(keys: secretKey, secrets: resolver(store));

      await turn(stream);
      final second = await turn(stream);

      expect(second.errorMessage, isNull);
      expect(authorization(0), 'Bearer $_key');
      expect(authorization(1), 'Bearer $_key');
      expect(store.reads, ['codelab/openai']);
    });

    test('not set: auth without HTTP, then success after a write without a '
        'restart', () async {
      final store = FakeSecretStore();
      final stream = routed(keys: secretKey, secrets: resolver(store));

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(
        failed.errorMessage,
        'API key secret codelab/openai is not set. '
        'Run: codelab secret set codelab/openai',
      );
      expect(requests, isEmpty);

      store.values['codelab/openai'] = _key;
      final ok = await turn(stream);

      expect(ok.errorMessage, isNull);
      expect(authorization(0), 'Bearer $_key');
    });

    test('unavailable: the text names the backend, the reason and the '
        'variable', () async {
      final store = FakeSecretStore(
        id: 'file',
        failWith: const SecretStoreUnavailableException(
          backend: 'file',
          reason:
              '/h/secrets.yaml has permissions 0644; run: chmod 600 /h/secrets.yaml',
        ),
      );
      final stream = routed(keys: secretKey, secrets: resolver(store));

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(
        failed.errorMessage,
        'API key secret codelab/openai cannot be read: file is unavailable '
        '(/h/secrets.yaml has permissions 0644; run: chmod 600 '
        '/h/secrets.yaml). Set CODELAB_SECRET_CODELAB_OPENAI or fix the '
        'secret store',
      );
      expect(requests, isEmpty);
    });

    test(
      'without a resolver the reference is unavailable, not silent',
      () async {
        final failed = await turn(routed(keys: secretKey));

        expect(failed.errorClass, LlmErrorClass.auth);
        expect(
          failed.errorMessage,
          'API key secret codelab/openai cannot be read: the host has no '
          'secret resolver',
        );
        expect(requests, isEmpty);
      },
    );

    test('the value never reaches the error text of the provider', () async {
      status = 401;
      responseBody =
          '{"error":{"message":"Incorrect API key provided: $_key"}}';
      final stream = routed(
        keys: secretKey,
        secrets: resolver(FakeSecretStore(values: {'codelab/openai': _key})),
      );

      final failed = await turn(stream);

      expect(failed.errorMessage, isNotNull);
      expect(failed.errorMessage, isNot(contains(_key)));
      expect(
        [
          for (final r in logger.records) '${r.event} ${r.fields} ${r.error}',
        ].join('\n'),
        isNot(contains(_key)),
      );
    });
  });

  group('api_key_env', () {
    test('is read through env() at the first request', () async {
      final stream = routed(
        keys: const {'openai': EnvKeyRef('OPENAI_API_KEY')},
        secrets: resolver(
          FakeSecretStore(),
          environment: {'OPENAI_API_KEY': _key},
          debug: true,
        ),
      );

      final ok = await turn(stream);

      expect(ok.errorMessage, isNull);
      expect(authorization(0), 'Bearer $_key');
      final lookup = logger.eventsOf('secrets.lookup').single.fields;
      expect(lookup['name'], 'OPENAI_API_KEY');
      expect(lookup['purpose'], 'providers.openai.api_key_env');
      expect(lookup['source'], 'env');
    });

    test('without a resolver the variable is not read from the process, '
        'the text says so', () async {
      final failed = await turn(
        routed(keys: const {'openai': EnvKeyRef('OPENAI_API_KEY')}),
      );

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(
        failed.errorMessage,
        'API key variable OPENAI_API_KEY cannot be read: the host has no '
        'secret resolver',
      );
      expect(requests, isEmpty);
    });

    test('an unset variable is an auth failure without HTTP', () async {
      final stream = routed(
        keys: const {'openai': EnvKeyRef('OPENAI_API_KEY')},
        secrets: resolver(FakeSecretStore()),
      );

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(failed.errorMessage, 'API key variable OPENAI_API_KEY is not set');
      expect(requests, isEmpty);
    });
  });

  group('headers with references', () {
    test('a header template is expanded from the store', () async {
      final store = FakeSecretStore(
        values: {'codelab/openai/org': 'org-test-42'},
      );
      final stream = routed(
        headerTemplates: {
          'openai': {
            'X-Org': SecretTemplate(const [
              SecretLiteral('Org '),
              SecretReference('codelab/openai/org'),
            ]),
          },
        },
        secrets: resolver(store),
      );

      final ok = await turn(stream);

      expect(ok.errorMessage, isNull);
      expect(requests.single.headers['X-Org'], 'Org org-test-42');
      expect(authorization(0), isNull);
    });

    test('a missing header secret names the header path', () async {
      final stream = routed(
        headerTemplates: {
          'openai': {
            'X-Org': SecretTemplate(const [
              SecretReference('codelab/openai/org'),
            ]),
          },
        },
        secrets: resolver(FakeSecretStore()),
      );

      final failed = await turn(stream);

      expect(failed.errorClass, LlmErrorClass.auth);
      expect(
        failed.errorMessage,
        'secret codelab/openai/org is not set (providers.openai.headers.X-Org). '
        'Run: codelab secret set codelab/openai/org',
      );
      expect(requests, isEmpty);
    });
  });

  group('waiting for the store', () {
    test(
      'cancellation ends the stream as aborted within 1 s, no HTTP',
      () async {
        final gate = Completer<void>();
        final store = FakeSecretStore(
          values: {'codelab/openai': _key},
          gate: gate,
        );
        final stream = routed(keys: secretKey, secrets: resolver(store));
        final source = CancelTokenSource();
        clock.timer(const Duration(milliseconds: 100), source.cancel);

        final failed = await turn(stream, cancel: source.token);

        expect(failed.errorClass, LlmErrorClass.aborted);
        expect(failed.stopReason, StopReason.aborted);
        expect(
          clock.elapsed,
          lessThanOrEqualTo(const Duration(milliseconds: 1100)),
        );
        expect(requests, isEmpty);

        // Позднее значение безопасно: оно только наполняет кэш резолвера.
        gate.complete();
        final ok = await turn(stream);
        expect(ok.errorMessage, isNull);
        expect(store.reads, ['codelab/openai']);
      },
    );

    test(
      'two simultaneous first requests make one read and one chain',
      () async {
        final gate = Completer<void>();
        final store = FakeSecretStore(
          values: {'codelab/openai': _key},
          gate: gate,
        );
        final stream = routed(keys: secretKey, secrets: resolver(store));

        final first = collect(stream(model, context), clock);
        final second = collect(stream(model, context), clock);
        await clock.elapse(const Duration(milliseconds: 100));
        expect(store.reads, ['codelab/openai']);
        gate.complete();
        final results = await Future.wait([first, second]);

        expect(terminalOf(results[0]).errorMessage, isNull);
        expect(terminalOf(results[1]).errorMessage, isNull);
        expect(store.reads, ['codelab/openai']);
        expect(requests, hasLength(2));
      },
    );
  });

  group('values from header templates in redaction', () {
    final bearer = {
      'openai': {
        'Authorization': SecretTemplate(const [
          SecretLiteral('Bearer '),
          SecretReference('codelab/openai'),
        ]),
      },
    };

    test('the bare value in a 401 body reaches neither the error nor the '
        'log', () async {
      status = 401;
      responseBody = '{"error":{"message":"token $_key is revoked"}}';
      final stream = routed(
        headerTemplates: bearer,
        secrets: resolver(FakeSecretStore(values: {'codelab/openai': _key})),
      );

      final failed = await turn(stream);

      expect(authorization(0), 'Bearer $_key');
      expect(failed.errorMessage, isNotNull);
      expect(failed.errorMessage, isNot(contains(_key)));
      expect(
        [
          for (final r in logger.records) '${r.event} ${r.fields} ${r.error}',
        ].join('\n'),
        isNot(contains(_key)),
      );
    });
  });

  test('a failure while resolving ends the stream with an unknown error, '
      'not a hang', () async {
    final stream = routed(
      keys: secretKey,
      secrets: resolver(FakeSecretStore(values: {'codelab/openai': _key})),
    );

    final failed = await turn(stream, cancel: _ThrowingToken());

    expect(failed.errorClass, LlmErrorClass.unknown);
    expect(failed.errorMessage, 'openai: StateError');
    expect(failed.errorMessage, isNot(contains(_key)));
    expect(requests, isEmpty);
    final logged = logger.eventsOf('llm.stream.failed');
    expect(logged, hasLength(1));
    expect(logged.single.fields['provider'], 'openai');
  });

  test('a provider from unavailable still wins over the references', () async {
    final stream = routed(
      keys: const {'openai': EnvKeyRef('OPENAI_API_KEY')},
      secrets: resolver(
        FakeSecretStore(),
        environment: {'OPENAI_API_KEY': _key},
      ),
      unavailable: const {
        'openai': 'API key variable OPENAI_API_KEY is not set',
      },
    );

    final failed = await turn(stream);

    expect(failed.errorMessage, 'API key variable OPENAI_API_KEY is not set');
    expect(requests, isEmpty);
  });
}

/// Токен, чей `onCancel` бросает: имитирует сбой внутри маршрутизатора до
/// запуска цепочки провайдера.
final class _ThrowingToken implements CancelToken {
  @override
  bool get isCancelled => false;

  @override
  Object? get reason => null;

  @override
  Future<void> get onCancel => throw StateError('boom $_key');

  @override
  void throwIfCancelled() {}
}
