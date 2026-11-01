import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Программная запись секретов (agent-secrets «Программная запись секретов»;
/// design.md change `add-agent-secret-store`, D15).
void main() {
  late Directory root;
  late String home;
  late FakeSecretProcessRunner runner;

  const value = 'sk-test-0123456789abcdef';

  SecretAdmin fileAdmin({Map<String, String> environment = const {}}) =>
      SecretAdmin(
        store: FileSecretStore(
          path: '$home/secrets.yaml',
          runner: runner,
          platform: 'linux',
        ),
        environment: environment,
        platform: 'linux',
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('secret_admin_test');
    home = '${root.path}/home';
    runner = FakeSecretProcessRunner();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('store saves, then overwriting reports Updated', () async {
    final admin = fileAdmin();

    final first = await admin.store('codelab/openai', value);
    final second = await admin.store('codelab/openai', '$value-2');

    expect(first, isA<SecretStored>());
    expect((first as SecretStored).name, 'codelab/openai');
    expect(first.backend, 'file');
    expect(second, isA<SecretUpdated>());
    final listing = await admin.list() as SecretListing;
    expect(listing.names, ['codelab/openai']);
  });

  test('no child process receives the value in argv or stdin', () async {
    await fileAdmin().store('codelab/openai', value);

    expect(runner.calls, isNotEmpty);
    for (final call in runner.calls) {
      expect(call.arguments.join(' '), isNot(contains(value)));
      expect(call.stdin, isNull);
    }
  });

  test(
    'invalid name and invalid value are results, the store is not called',
    () async {
      final store = _CountingStore();
      final admin = SecretAdmin(store: store, environment: const {});

      final badName = await admin.store('Bad Name', 'v');
      final badValue = await admin.store('codelab/a', 'a\nb-$value');
      final empty = await admin.store('codelab/a', '');
      final carriage = await admin.store('codelab/a', 'a\rb');

      expect(badName, isA<SecretInvalidName>());
      expect(
        (badName as SecretInvalidName).reason,
        'expected a secret name: lowercase letters, digits and . _ / -, '
        'up to 128 characters',
      );
      expect(badValue, isA<SecretInvalidValue>());
      expect(empty, isA<SecretInvalidValue>());
      expect(carriage, isA<SecretInvalidValue>());
      expect(store.calls, 0);
      for (final result in [badName, badValue, empty, carriage]) {
        expect(result.toString(), isNot(contains(value)));
      }
    },
  );

  test('a name whose variable collides with another stored name', () async {
    final admin = fileAdmin();
    await admin.store('codelab/a-b', 'one');

    final result = await admin.store('codelab/a.b', 'two');

    expect(result, isA<SecretCollision>());
    result as SecretCollision;
    expect(result.name, 'codelab/a.b');
    expect(result.other, 'codelab/a-b');
    expect(result.variable, 'CODELAB_SECRET_CODELAB_A_B');
    expect(
      result.toString(),
      contains(
        'SecretCollision(name: codelab/a.b, other: codelab/a-b, '
        'variable: CODELAB_SECRET_CODELAB_A_B)',
      ),
    );
    expect((await fileAdmin().list() as SecretListing).names, ['codelab/a-b']);
  });

  test('env is read-only: structured data, file backend offered', () async {
    final admin = SecretAdmin(
      store: EnvSecretStore(environment: const {}),
      environment: const {},
      platform: 'macos',
    );

    final result = await admin.store('codelab/openai', value);
    final deleted = await admin.delete('codelab/openai');

    for (final r in [result, deleted]) {
      expect(r, isA<SecretReadOnly>());
      r as SecretReadOnly;
      expect(r.backend, 'env');
      expect(r.variable, 'CODELAB_SECRET_CODELAB_OPENAI');
      expect(r.fileBackendOffered, isTrue);
      expect(
        r.toString(),
        'SecretReadOnly(backend: env, variable: CODELAB_SECRET_CODELAB_OPENAI, '
        'fileBackendOffered: true)',
      );
      expect(r.toString(), isNot(contains(value)));
    }
  });

  test(
    'on Windows the file backend is not offered, only the variable',
    () async {
      final admin = SecretAdmin(
        store: EnvSecretStore(environment: const {}),
        environment: const {},
        platform: 'windows',
      );

      final result =
          await admin.store('codelab/openai', value) as SecretReadOnly;

      expect(result.variable, 'CODELAB_SECRET_CODELAB_OPENAI');
      expect(result.fileBackendOffered, isFalse);
      expect(result.toString(), isNot(contains('secrets.backend: file')));
    },
  );

  test(
    'a refused store is Failed with the chmod hint, without the value',
    () async {
      final admin = fileAdmin();
      await admin.store('codelab/a', 'v');
      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);

      final result = await admin.store('codelab/b', value);
      final listing = await admin.list();

      expect(result, isA<SecretFailed>());
      expect((result as SecretFailed).reason, contains('chmod 600'));
      expect(result.toString(), isNot(contains(value)));
      expect(listing, isA<SecretListFailed>());
      expect((listing as SecretListFailed).reason, contains('chmod 600'));
    },
  );

  test('an unexpected store error is Failed with the type only', () async {
    final admin = SecretAdmin(
      store: _ThrowingStore(StateError('leaks $value')),
      environment: const {},
    );

    final result = await admin.store('codelab/a', 'v') as SecretFailed;

    expect(result.reason, isNot(contains(value)));
    expect(result.toString(), isNot(contains(value)));
  });

  test('delete removes, and an absent name is reported, not failed', () async {
    final admin = fileAdmin();
    await admin.store('codelab/a', 'v');

    final removed = await admin.delete('codelab/a');
    final absent = await admin.delete('codelab/a');
    final invalid = await admin.delete('Bad Name');

    expect(removed, isA<SecretDeleted>());
    expect(absent, isA<SecretNotSet>());
    expect(invalid, isA<SecretInvalidName>());
    expect((await admin.list() as SecretListing).names, isEmpty);
  });

  test('list returns sorted names and override variable names only', () async {
    final admin = fileAdmin(
      environment: {
        'CODELAB_SECRET_Z': 'z-value',
        'CODELAB_SECRET_A': 'a-value',
        'CODELAB_DEBUG_SECRETS': '1',
        'PATH': '/bin',
      },
    );
    await admin.store('codelab/b', 'v');
    await admin.store('codelab/a', 'v');

    final listing = await admin.list() as SecretListing;

    expect(listing.backend.id, 'file');
    expect(listing.names, ['codelab/a', 'codelab/b']);
    expect(listing.overrides, ['CODELAB_SECRET_A', 'CODELAB_SECRET_Z']);
    expect(listing.toString(), isNot(contains('a-value')));
  });

  group('value limits', () {
    test('a value over 64 KiB is invalid, exactly 64 KiB is stored', () async {
      final admin = fileAdmin();

      final big = await admin.store('codelab/a', 'x' * (64 * 1024 + 1));
      final multibyte = await admin.store('codelab/a', 'я' * (32 * 1024 + 1));
      final ok = await admin.store('codelab/a', 'x' * (64 * 1024));

      expect(
        big,
        isA<SecretInvalidValue>().having(
          (r) => r.reason,
          'reason',
          'secret value is longer than 64 KiB',
        ),
      );
      expect(multibyte, isA<SecretInvalidValue>());
      expect(ok, isA<SecretStored>());
    });

    test('a lone surrogate is invalid, a surrogate pair is stored', () async {
      final admin = fileAdmin();

      final lone = await admin.store('codelab/a', 'a\uD800b');
      final pair = await admin.store('codelab/b', 'key \u{1F511}');

      expect(
        lone,
        isA<SecretInvalidValue>().having(
          (r) => r.reason,
          'reason',
          'secret value is not valid Unicode (unpaired surrogate)',
        ),
      );
      expect(pair, isA<SecretStored>());
      expect((await admin.list() as SecretListing).names, ['codelab/b']);
    });
  });

  group('checkStore', () {
    test('returns null when the name can be stored', () async {
      final admin = fileAdmin();
      await admin.store('codelab/a', 'v');

      expect(await admin.checkStore('codelab/a'), isNull); // перезапись
      expect(await admin.checkStore('codelab/new'), isNull);
    });

    test('reports invalid name, read-only backend, collision and failure '
        'without a value', () async {
      final admin = fileAdmin();
      await admin.store('codelab/a-b', 'v');
      final readOnly = SecretAdmin(
        store: EnvSecretStore(environment: const {}),
        environment: const {},
        platform: 'macos',
      );

      expect(await admin.checkStore('Bad Name'), isA<SecretInvalidName>());
      expect(await admin.checkStore('codelab/a.b'), isA<SecretCollision>());
      expect(await readOnly.checkStore('codelab/a'), isA<SecretReadOnly>());
      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);
      expect(await admin.checkStore('codelab/z'), isA<SecretFailed>());
    });

    test(
      'store gives the same outcome as checkStore for those cases',
      () async {
        final admin = fileAdmin();
        await admin.store('codelab/a-b', 'v');

        final check = await admin.checkStore('codelab/a.b');
        final stored = await admin.store('codelab/a.b', 'two');

        expect(stored.toString(), check.toString());
      },
    );

    test('does not write or create anything', () async {
      final admin = fileAdmin();

      await admin.checkStore('codelab/a');

      expect(runner.calls, isEmpty);
      expect(Directory(home).existsSync(), isFalse);
    });
  });

  test(
    'toString of results follows Class(field: value) and has no value',
    () async {
      final admin = fileAdmin();
      final results = <Object>[
        await admin.store('codelab/a', value),
        await admin.store('codelab/a', '$value-2'),
        await admin.delete('codelab/a'),
        await admin.delete('codelab/a'),
        await admin.store('Bad Name', value),
        await admin.store('codelab/a', ''),
        await admin.list(),
      ];

      expect(results.map((r) => r.toString()), [
        'SecretStored(name: codelab/a, backend: file)',
        'SecretUpdated(name: codelab/a, backend: file)',
        'SecretDeleted(name: codelab/a, backend: file)',
        'SecretNotSet(name: codelab/a, backend: file)',
        'SecretInvalidName(reason: expected a secret name: lowercase letters, '
            'digits and . _ / -, up to 128 characters)',
        'SecretInvalidValue(reason: empty secret value)',
        'SecretListing(backend: file, names: [], overrides: [])',
      ]);
    },
  );

  test('toString of every outcome omits the value', () async {
    final admin = fileAdmin();
    final results = <Object>[
      await admin.store('codelab/a', value),
      await admin.store('codelab/a', '$value-2'),
      await admin.delete('codelab/a'),
      await admin.delete('codelab/a'),
    ];

    for (final result in results) {
      expect(result.toString(), isNot(contains(value)));
    }
  });
}

final class _CountingStore implements DescribedSecretStore {
  int calls = 0;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'memory', writable: true);

  @override
  Future<String?> read(String name) async {
    calls++;
    return null;
  }

  @override
  Future<void> write(String name, String value) async => calls++;

  @override
  Future<void> delete(String name) async => calls++;

  @override
  Future<List<String>> names() async {
    calls++;
    return const [];
  }
}

final class _ThrowingStore extends _CountingStore {
  _ThrowingStore(this.error);

  final Object error;

  @override
  Future<List<String>> names() async => throw error;

  @override
  Future<void> write(String name, String value) async => throw error;
}
