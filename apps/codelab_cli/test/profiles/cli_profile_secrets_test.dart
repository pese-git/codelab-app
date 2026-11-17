// Адаптер `ProfileSecrets` CLI поверх `ClientSecretAccess` (ревью итерации 1
// change `add-provider-setup-ui`; design.md, D4, D13): порядок проверок
// `checkStore` → `isSet` → `store`, `Exists` вместо перезаписи, типизированные
// сбои. Временный `CODELAB_HOME` с бэкендом `file`, значения фиктивные.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/io.dart' as setup;
import 'package:test/test.dart';

const _name = 'codelab/profiles/devbox/token';
const _value = 'sk-test-leak-0123456789';

final class _SilentLogger implements setup.Logger {
  @override
  bool isEnabled(setup.LogLevel level) => false;

  @override
  void log(
    setup.LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

void main() {
  late Directory tmp;
  late String home;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_secrets_');
    home = '${tmp.path}/home';
    Directory(home).createSync(recursive: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProfileSecrets> open({
    String backend = 'file',
    Map<String, String> extraEnvironment = const {},
  }) {
    File(
      '$home/config.yaml',
    ).writeAsStringSync('secrets:\n  backend: $backend\n');
    return openCliProfileSecrets(
      environment: {'CODELAB_HOME': home, ...extraEnvironment},
      logger: _SilentLogger(),
    );
  }

  test('store, read, names and isSet on the file backend; the value never '
      'appears in a result', () async {
    final secrets = await open();

    expect(secrets.backend.id, 'file');
    expect(secrets.backend.writable, isTrue);
    final stored = await secrets.store(_name, const SecretText(_value));
    expect(stored, isA<Stored>());
    expect(await secrets.read(_name), _value);
    expect(await secrets.isSet(_name), isTrue);
    expect(await secrets.names(), [_name]);
    expect('$stored', isNot(contains(_value)));
  });

  test('an existing name is Exists and the value is not replaced', () async {
    final secrets = await open();
    await secrets.store(_name, const SecretText(_value));

    final again = await secrets.store(_name, const SecretText('other-value'));

    expect(again, isA<Exists>());
    expect(await secrets.read(_name), _value);
  });

  test(
    'a name set by the CODELAB_SECRET_ override counts as existing',
    () async {
      final secrets = await open(
        extraEnvironment: {
          'CODELAB_SECRET_CODELAB_PROFILES_DEVBOX_TOKEN': 'from-env',
        },
      );

      expect(
        await secrets.store(_name, const SecretText('new-value')),
        isA<Exists>(),
      );
    },
  );

  test('delete: Deleted, then NotSet', () async {
    final secrets = await open();
    await secrets.store(_name, const SecretText(_value));

    expect(await secrets.delete(_name), isA<Deleted>());
    expect(await secrets.delete(_name), isA<NotSet>());
    expect(await secrets.isSet(_name), isFalse);
  });

  test('the env backend is read-only: ReadOnly for store and delete, with '
      'a hint', () async {
    final secrets = await open(backend: 'env');

    expect(secrets.backend.writable, isFalse);
    final write = await secrets.store(_name, const SecretText(_value));
    expect(write, isA<ReadOnly>());
    expect((write as ReadOnly).reason, contains('read-only'));
    expect(await secrets.delete(_name), isA<ReadOnly>());
  });

  test('an invalid name is Failed, not an exception', () async {
    final secrets = await open();

    expect(
      await secrets.store('Bad Name', const SecretText(_value)),
      isA<Failed>(),
    );
    expect(await secrets.delete('Bad Name'), isA<Failed>());
  });

  test('a broken store file: names throws SecretStoreUnavailableException, '
      'store and delete are Failed with the type only', () async {
    final secrets = await open();
    File('$home/secrets.yaml').writeAsStringSync('::: not yaml [');

    await expectLater(
      secrets.names(),
      throwsA(isA<setup.SecretStoreUnavailableException>()),
    );
    final write = await secrets.store(_name, const SecretText(_value));
    expect(write, isA<Failed>());
    expect('$write', isNot(contains(_value)));
    expect(await secrets.delete(_name), isA<Failed>());
  });

  group('the outcome translation', () {
    test('SecretUpdated means the name appeared meanwhile: Exists, not '
        'Stored (the rollback must not touch it)', () {
      expect(
        profileSecretWriteOf(setup.SecretUpdated(_name, 'file'), home: '/h'),
        isA<Exists>(),
      );
      expect(
        profileSecretWriteOf(setup.SecretStored(_name, 'file'), home: '/h'),
        isA<Stored>(),
      );
    });

    test('the read-only hint is the lowercase CLI text, without a capital '
        'or a final period (D3)', () {
      const readOnly = setup.SecretReadOnly(
        backend: 'env',
        variable: 'CODELAB_SECRET_X',
        fileBackendOffered: true,
      );

      final write = profileSecretWriteOf(readOnly, home: '/h') as ReadOnly;

      expect(write.reason, setup.secretReadOnlyHint(readOnly, '/h'));
      expect(write.reason, startsWith('secret store env is read-only'));
    });

    test('the real env backend gives the same lowercase hint', () async {
      final secrets = await open(backend: 'env');

      final write = await secrets.store(_name, const SecretText(_value));

      expect((write as ReadOnly).reason, startsWith('secret store'));
    });
  });
}
