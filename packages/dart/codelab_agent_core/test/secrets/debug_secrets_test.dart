import 'dart:convert';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/call_sequence.dart';
import '../support/fake_secret_store.dart';
import '../support/provider_harness.dart';

const _value = 'sk-test-0123456789abcdef';

/// Диагностика обращений к секретам (agent-secrets «Диагностика обращений к
/// секретам»; `core/debug-secrets-never-logs-value`; CFG-10; design.md change
/// `add-agent-secret-store`, D3, D10).
void main() {
  late RecordingLogger logger;

  setUp(() => logger = RecordingLogger());

  SecretResolver resolver({
    required bool debug,
    DescribedSecretStore? store,
    Map<String, String> environment = const {},
  }) => SecretResolver(
    store: store ?? MemorySecretStore({'codelab/openai': _value}),
    environment: environment,
    logger: logger,
    debug: debug,
  );

  /// Всё, что видит приёмник лога: событие, поля, ошибка, стек.
  String raw() => [
    for (final r in logger.records)
      '${r.event} ${r.fields.entries.map((e) => '${e.key}=${e.value}').join(' ')} '
          '${r.error} ${r.stack}',
  ].join('\n');

  /// Ни значения, ни его подстроки длиной 4 и более символов, ни длины, ни
  /// SHA-256 (hex, base64, base64url) во ВСЕХ записях лога.
  void expectNoTraceOf(String value) {
    final text = raw();
    expect(text, isNot(contains(value)));
    for (var length = 4; length <= value.length; length++) {
      for (var i = 0; i + length <= value.length; i++) {
        expect(
          text,
          isNot(contains(value.substring(i, i + length))),
          reason: value.substring(i, i + length),
        );
      }
    }
    final digest = sha256.convert(utf8.encode(value));
    expect(text, isNot(contains(digest.toString())));
    expect(text, isNot(contains(base64.encode(digest.bytes))));
    expect(text, isNot(contains(base64Url.encode(digest.bytes))));
  }

  test(
    'lookups carry name, purpose, source and found, and never the value',
    () async {
      final r = resolver(debug: true, environment: {'OPENAI_API_KEY': _value});

      await r.secret(
        'codelab/openai',
        purpose: 'providers.openai.api_key_secret',
      );
      await r.secret(
        'codelab/openai',
        purpose: 'providers.openai.api_key_secret',
      );
      r.env('OPENAI_API_KEY', purpose: 'providers.local.api_key_env');

      final lookups = logger.eventsOf('secrets.lookup');
      expect(lookups, hasLength(3));
      expect(lookups.every((l) => l.level == LogLevel.info), isTrue);
      expect(
        [for (final l in lookups) l.fields],
        [
          {
            'name': 'codelab/openai',
            'purpose': 'providers.openai.api_key_secret',
            'source': 'memory',
            'found': true,
          },
          {
            'name': 'codelab/openai',
            'purpose': 'providers.openai.api_key_secret',
            'source': 'cache',
            'found': true,
          },
          {
            'name': 'OPENAI_API_KEY',
            'purpose': 'providers.local.api_key_env',
            'source': 'env',
            'found': true,
          },
        ],
      );

      expectNoTraceOf(_value);
      for (final record in lookups) {
        expect(record.fields.values, isNot(contains(_value.length)));
      }
    },
  );

  test(
    'missing and unavailable lookups are found: false with the backend id',
    () async {
      final missing = resolver(debug: true);
      await missing.secret('codelab/none', purpose: 'p1');
      final unavailable = resolver(
        debug: true,
        store: FakeSecretStore(
          id: 'file',
          failWith: const SecretStoreUnavailableException(
            backend: 'file',
            reason: 'denied',
          ),
        ),
      );
      await unavailable.secret('codelab/x', purpose: 'p2');
      missing.env('NOPE', purpose: 'p3');

      expect(
        [for (final l in logger.eventsOf('secrets.lookup')) l.fields],
        [
          {
            'name': 'codelab/none',
            'purpose': 'p1',
            'source': 'memory',
            'found': false,
          },
          {
            'name': 'codelab/x',
            'purpose': 'p2',
            'source': 'file',
            'found': false,
          },
          {'name': 'NOPE', 'purpose': 'p3', 'source': 'env', 'found': false},
        ],
      );
    },
  );

  test('without the mode there are no secrets.lookup records', () async {
    final r = resolver(debug: false);

    await r.secret('codelab/openai', purpose: 'p');
    await r.secret('codelab/openai', purpose: 'p');
    r.env('OPENAI_API_KEY', purpose: 'p');

    expect(logger.eventsOf('secrets.lookup'), isEmpty);
    expect(raw(), isNot(contains(_value)));
  });

  // Сценарий `core/debug-secrets-never-logs-value` на дороге провайдера:
  // ключ и значение заголовка проходят через createRoutedStreamFunction, один
  // логгер на резолвер и CoreLlmServices (design.md, D4, D10).
  group('provider path', () {
    const org = 'org-test-9f8e7d6c5b4a';
    final model = ModelRef(
      provider: 'openai',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://api.example/v1'),
      contextWindow: 128000,
      maxOutputTokens: 4096,
    );
    final context = LlmContext(
      systemPrompt: 'You are CodeLab.',
      messages: [
        UserMessage(const [TextContent('hi')], timestamp: DateTime.utc(2026)),
      ],
    );

    StreamFunction routed(SecretResolver secrets, FakeClock clock, int status) {
      final provider = ProviderConfig(
        name: 'openai',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('https://api.example/v1'),
      );
      final body = status == 200
          ? readSseFixture('openai/text.sse')
          : '{"error":{"message":"bad key $_value and $org"}}';
      return createRoutedStreamFunction(
        [provider],
        CoreLlmServices(
          httpClient: MockClient.streaming(
            (request, _) async => http.StreamedResponse(
              Stream.value(utf8.encode(body)),
              status,
              headers: {'content-type': 'text/event-stream'},
            ),
          ),
          clock: clock,
          random: Random(1),
          logger: logger,
        ),
        keys: const {'openai': SecretKeyRef('codelab/openai')},
        headerTemplates: {
          'openai': {
            'X-Org': SecretTemplate(const [
              SecretLiteral('Org '),
              SecretReference('codelab/org'),
            ]),
          },
        },
        secrets: secrets,
      );
    }

    test('two turns: lookups are memory, then cache; no value in any '
        'record', () async {
      final clock = FakeClock();
      final r = resolver(
        debug: true,
        store: MemorySecretStore({
          'codelab/openai': _value,
          'codelab/org': org,
        }),
      );
      // Ход 1: цепочка строится и читает ключ и заголовок через резолвер.
      final first = routed(r, clock, 401);
      final failed = terminalOf(await collect(first(model, context), clock));
      expect(failed.errorClass, LlmErrorClass.auth);
      // Ход 2 той же функции цепочку берёт из её кэша (D4) и резолвер не
      // зовёт; новая функция на том же резолвере (второй хост или сессия)
      // читает ключ из кэша резолвера.
      await collect(first(model, context), clock);
      final second = routed(r, clock, 200);
      final ok = terminalOf(await collect(second(model, context), clock));
      expect(ok.errorMessage, isNull);

      final lookups = logger.eventsOf('secrets.lookup');
      expect(
        [
          for (final l in lookups)
            (l.fields['name'], l.fields['source'], l.fields['found']),
        ],
        [
          ('codelab/openai', 'memory', true),
          ('codelab/org', 'memory', true),
          ('codelab/openai', 'cache', true),
          ('codelab/org', 'cache', true),
        ],
      );
      expect(
        lookups.first.fields['purpose'],
        'providers.openai.api_key_secret',
      );
      expect(lookups[1].fields['purpose'], 'providers.openai.headers.X-Org');
      for (final record in lookups) {
        expect(record.fields.values, isNot(contains(_value.length)));
        expect(record.fields.values, isNot(contains(org.length)));
      }
      expectNoTraceOf(_value);
      expectNoTraceOf(org);
    });
  });
}
