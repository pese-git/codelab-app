import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/fake_secret_store.dart';

const _value = 'sk-test-0123456789abcdef';

/// Даёт запущенным вызовам дойти до `read`: без реального времени.
Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

/// Резолвер секретов (agent-secrets «Резолвер секретов»; design.md change
/// `add-agent-secret-store`, D3, D10).
void main() {
  late RecordingLogger logger;

  setUp(() => logger = RecordingLogger());

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

  group('order', () {
    test('a variable wins over the store and the store is not read', () async {
      final store = FakeSecretStore(values: {'codelab/openai': 'store-value'});
      final lookup = await resolver(
        store,
        environment: {'CODELAB_SECRET_CODELAB_OPENAI': 'env-value'},
      ).secret('codelab/openai', purpose: 'providers.openai.api_key_secret');

      expect(lookup, isA<SecretFound>());
      lookup as SecretFound;
      expect(lookup.value, 'env-value');
      expect(lookup.source, 'env');
      expect(store.reads, isEmpty);
    });

    test('an empty variable does not count: the store is read', () async {
      final store = FakeSecretStore(values: {'codelab/a': 'v'});
      final lookup = await resolver(
        store,
        environment: {'CODELAB_SECRET_CODELAB_A': ''},
      ).secret('codelab/a', purpose: 'p');

      expect((lookup as SecretFound).value, 'v');
      expect(lookup.source, 'fake');
    });

    test('a value from the store carries the id of the backend', () async {
      final lookup = await resolver(
        FakeSecretStore(values: {'codelab/a': 'v'}, id: 'file'),
      ).secret('codelab/a', purpose: 'p');

      expect((lookup as SecretFound).source, 'file');
    });

    test('an invalid name is missing without touching the store', () async {
      final store = FakeSecretStore(values: {'Bad Name': 'v'});
      final lookup = await resolver(store).secret('Bad Name', purpose: 'p');

      expect(lookup, isA<SecretMissing>());
      expect((lookup as SecretMissing).backend, 'fake');
      expect(store.reads, isEmpty);
    });

    test('an empty value in the store is missing', () async {
      final lookup = await resolver(
        FakeSecretStore(values: {'codelab/a': ''}),
      ).secret('codelab/a', purpose: 'p');

      expect(lookup, isA<SecretMissing>());
    });
  });

  group('cache', () {
    test('a found value is cached, a missing one is not', () async {
      final store = FakeSecretStore(values: {'codelab/a': 'va'});
      final r = resolver(store);

      final first = await r.secret('codelab/a', purpose: 'p');
      final second = await r.secret('codelab/a', purpose: 'p');
      final missing = await r.secret('codelab/b', purpose: 'p');
      store.values['codelab/b'] = 'vb';
      final found = await r.secret('codelab/b', purpose: 'p');

      expect((first as SecretFound).source, 'fake');
      expect((second as SecretFound).source, 'cache');
      expect(second.value, 'va');
      expect(missing, isA<SecretMissing>());
      expect((found as SecretFound).value, 'vb');
      expect(store.reads, ['codelab/a', 'codelab/b', 'codelab/b']);
    });

    test(
      'a replaced value of a cached secret stays old until restart',
      () async {
        final store = FakeSecretStore(values: {'codelab/a': 'old'});
        final r = resolver(store);
        await r.secret('codelab/a', purpose: 'p');
        store.values['codelab/a'] = 'new';

        expect(
          ((await r.secret('codelab/a', purpose: 'p')) as SecretFound).value,
          'old',
        );
        expect(
          ((await resolver(store).secret('codelab/a', purpose: 'p'))
                  as SecretFound)
              .value,
          'new',
        );
      },
    );
  });

  group('single flight', () {
    test('concurrent requests of one name make one read', () async {
      final gate = Completer<void>();
      final store = FakeSecretStore(values: {'codelab/a': 'va'}, gate: gate);
      final r = resolver(store);

      final all = Future.wait([
        r.secret('codelab/a', purpose: 'p1'),
        r.secret('codelab/a', purpose: 'p2'),
        r.secret('codelab/a', purpose: 'p3'),
      ]);
      await _flush();
      gate.complete();
      final results = await all;

      expect(store.reads, ['codelab/a']);
      expect(
        [for (final l in results) (l as SecretFound).value],
        ['va', 'va', 'va'],
      );
    });

    test('a request after a missing result reads again', () async {
      final store = FakeSecretStore();
      final r = resolver(store);

      await r.secret('codelab/a', purpose: 'p');
      await r.secret('codelab/a', purpose: 'p');

      expect(store.reads, hasLength(2));
    });
  });

  group('unavailable store', () {
    test('two names give two SecretUnavailable and one warning', () async {
      const reason =
          '/h/secrets.yaml has permissions 0644; run: chmod 600 /h/secrets.yaml';
      final store = FakeSecretStore(
        id: 'file',
        failWith: const SecretStoreUnavailableException(
          backend: 'file',
          reason: reason,
        ),
      );
      final r = resolver(store);

      final a = await r.secret('codelab/a', purpose: 'p');
      final b = await r.secret('codelab/b', purpose: 'p');

      for (final lookup in [a, b]) {
        expect(lookup, isA<SecretUnavailable>());
        lookup as SecretUnavailable;
        expect(lookup.backend, 'file');
        expect(lookup.reason, reason);
      }
      final warnings = logger.eventsOf('secrets.backend.unavailable');
      expect(warnings, hasLength(1));
      expect(warnings.single.level, LogLevel.warning);
      expect(warnings.single.fields, {'backend': 'file', 'reason': reason});
    });

    test('a foreign exception gives only its type as the reason, the text '
        'is dropped', () async {
      final store = FakeSecretStore(
        id: 'foreign',
        failWith: StateError('boom with $_value inside'),
      );
      final r = resolver(store, debug: true);

      final lookup = await r.secret('codelab/a', purpose: 'p');

      expect(lookup, isA<SecretUnavailable>());
      lookup as SecretUnavailable;
      expect(lookup.backend, 'foreign');
      expect(lookup.reason, 'secret store failed: StateError');
      final all = [
        for (final rec in logger.records)
          '${rec.event} ${rec.fields} ${rec.error} ${rec.stack}',
      ].join('\n');
      expect(all, isNot(contains(_value)));
      expect(all, isNot(contains('boom')));
      expect(logger.eventsOf('secrets.backend.unavailable').single.fields, {
        'backend': 'foreign',
        'reason': 'secret store failed: StateError',
      });
    });

    test(
      'another reason is another warning; unavailable is not cached',
      () async {
        final store = FakeSecretStore(
          values: {'codelab/a': 'va'},
          failWith: const SecretStoreUnavailableException(
            backend: 'fake',
            reason: 'first',
          ),
        );
        final r = resolver(store);

        await r.secret('codelab/a', purpose: 'p');
        store.failWith = const SecretStoreUnavailableException(
          backend: 'fake',
          reason: 'second',
        );
        await r.secret('codelab/a', purpose: 'p');
        store.failWith = null;
        final recovered = await r.secret('codelab/a', purpose: 'p');

        expect(logger.eventsOf('secrets.backend.unavailable'), hasLength(2));
        expect((recovered as SecretFound).value, 'va');
      },
    );
  });

  group('env()', () {
    test('reads only the environment of the resolver', () {
      final store = FakeSecretStore(values: {'OPENAI_API_KEY': 'store'});
      final r = resolver(store, environment: {'OPENAI_API_KEY': 'from-env'});

      final found = r.env('OPENAI_API_KEY', purpose: 'p');
      final missing = r.env('OTHER_KEY', purpose: 'p');
      final empty = resolver(
        store,
        environment: {'K': ''},
      ).env('K', purpose: 'p');

      expect((found as SecretFound).value, 'from-env');
      expect(found.source, 'env');
      expect(missing, isA<SecretMissing>());
      expect((missing as SecretMissing).backend, 'env');
      expect(empty, isA<SecretMissing>());
      expect(store.reads, isEmpty);
    });
  });

  group('toString', () {
    test('never prints the value', () async {
      final found = SecretFound(_value, 'env');
      final lookup = await resolver(
        FakeSecretStore(values: {'codelab/a': _value}),
      ).secret('codelab/a', purpose: 'p');

      expect('$found', isNot(contains(_value)));
      expect('$found', isNot(contains('sk-')));
      expect('$lookup', isNot(contains(_value)));
      const exception = SecretStoreUnavailableException(
        backend: 'file',
        reason: 'some reason',
      );
      expect('$exception', contains('file'));
      expect('$exception', contains('some reason'));
    });
  });

  group('MemorySecretStore', () {
    test('is a described writable store with id memory', () async {
      final store = MemorySecretStore({'codelab/a': 'va'});

      expect(store.backend.id, 'memory');
      expect(store.backend.writable, isTrue);
      expect(store.backend.unavailableReason, isNull);
      expect(await store.read('codelab/a'), 'va');
      await store.write('codelab/b', 'vb');
      expect(await store.names(), ['codelab/a', 'codelab/b']);
      await store.delete('codelab/a');
      expect(await store.read('codelab/a'), isNull);
    });
  });
}
