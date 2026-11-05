// Адаптер `ProfileSecrets` в `lib/app/` поверх `ClientSecretAccess` (задача
// 1.12 change `add-provider-setup-ui`; design.md D3, D4, D13, D18).
//
// Только временный `CODELAB_HOME` и фиктивные значения: настоящие
// `~/.codelab/*` и хранилище ОС не читаются. Обычные `test`, не `testWidgets`:
// настоящий файл внутри fake-async зоны зависал бы.

import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/client_profile_secrets.dart';
import 'package:codelab_setup/io.dart' as setup;
import 'package:codelab_desktop/app/connection_environment.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_logger.dart';

void main() {
  const leak = 'sk-test-leak-0123456789';

  late Directory root;
  late String home;
  late RecordingLogger events;

  Future<ProfileSecrets> open({Map<String, String> extra = const {}}) =>
      openProfileSecrets(
        environment: ConnectionEnvironment.of({'CODELAB_HOME': home, ...extra}),
        logger: CodeLabEmbeddedLogger(logger: events),
      );

  void writeConfig(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  setUp(() {
    root = Directory.systemTemp.createTempSync('client_profile_secrets_test');
    home = '${root.path}/home';
    Directory(home).createSync();
    // Бэкенд `file` требует закрытый от группы `$CODELAB_HOME`.
    Process.runSync('/bin/chmod', ['700', home]);
    events = RecordingLogger();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('backend file', () {
    setUp(() => writeConfig('secrets:\n  backend: file\n'));

    test('writes once, never overwrites, and reads without a cache', () async {
      final secrets = await open();

      expect(secrets.backend.id, 'file');
      expect(secrets.backend.writable, isTrue);
      expect(secrets.backend.unavailableReason, isNull);
      expect(await secrets.isSet('codelab/ws-ci'), isFalse);
      expect(await secrets.read('codelab/ws-ci'), isNull);

      expect(
        await secrets.store('codelab/ws-ci', const SecretText('a')),
        isA<Stored>(),
      );
      expect(
        await secrets.store('codelab/ws-ci', const SecretText('b')),
        isA<Exists>(),
      );

      expect(await secrets.read('codelab/ws-ci'), 'a');
      expect(await secrets.isSet('codelab/ws-ci'), isTrue);
      expect(await secrets.names(), ['codelab/ws-ci']);

      // Замена другим процессом видна при следующем чтении.
      await (await open()).delete('codelab/ws-ci');
      expect(await secrets.read('codelab/ws-ci'), isNull);
    });

    test('delete reports Deleted, then NotSet', () async {
      final secrets = await open();
      await secrets.store('codelab/x', const SecretText('v'));

      expect(await secrets.delete('codelab/x'), isA<Deleted>());
      expect(await secrets.delete('codelab/x'), isA<NotSet>());
    });

    test('a name the store rejects is a failure without the value', () async {
      final secrets = await open();

      final result = await secrets.store('Bad Name', const SecretText(leak));

      expect(result, isA<Failed>());
      expect('${(result as Failed).message} $result', isNot(contains(leak)));
    });

    test('the value is nowhere in the adapter output or the log', () async {
      final secrets = await open();
      await secrets.store('codelab/p', const SecretText(leak));

      expect(secrets.toString(), isNot(contains(leak)));
      expect('${secrets.backend.unavailableReason}', isNot(contains(leak)));
      expect(events.entries.toString(), isNot(contains(leak)));
    });
  });

  group('read-only backend (default env)', () {
    test('says so with the capitalised hint of the CLI and refuses to '
        'write', () async {
      final secrets = await open();

      expect(secrets.backend.id, 'env');
      expect(secrets.backend.writable, isFalse);
      final reason = secrets.backend.unavailableReason!;
      expect(reason, startsWith('Secret store env is read-only. '));
      expect(reason, contains('$home/config.yaml'));
      expect(reason, endsWith('.'));

      final result = await secrets.store(
        'codelab/profiles/devbox/token',
        const SecretText(leak),
      );
      expect(result, isA<ReadOnly>());
      expect(
        (result as ReadOnly).reason,
        startsWith('Secret store env is read-only. '),
      );
      expect(
        result.reason,
        contains('CODELAB_SECRET_CODELAB_PROFILES_DEVBOX_TOKEN'),
      );
      expect(result.reason, isNot(contains(leak)));
    });

    test('the plain auto -> env choice keeps the CLI advice and has no '
        'config reason', () async {
      final secrets = await open();

      expect(
        secrets.backend.unavailableReason,
        contains("Add 'secrets.backend: file'"),
      );
      expect(secrets.backend.unavailableReason, isNot(contains('keychain')));
      expect((secrets as DescribedProfileSecrets).backendProblem, isNull);
    });

    test('delete is refused too, and the override variable is read', () async {
      final secrets = await open(extra: {'CODELAB_SECRET_CODELAB_WS_CI': leak});

      expect(await secrets.delete('codelab/ws-ci'), isA<ReadOnly>());
      expect(await secrets.read('codelab/ws-ci'), leak);
      expect(await secrets.isSet('codelab/ws-ci'), isTrue);
    });
  });

  group('a broken user config', () {
    test('keeps the store read-only and shows the backend reason instead '
        'of the advice to add secrets.backend', () async {
      writeConfig('secrets: [unclosed\n');

      final secrets = await open();

      expect(secrets.backend.writable, isFalse);
      expect(
        secrets.backend.unavailableReason,
        'The user config file cannot be read, so secrets are read-only until '
        'it is fixed.',
      );
      expect(
        (secrets as DescribedProfileSecrets).backendProblem,
        'the user config file cannot be read, so secrets are read-only until '
        'it is fixed',
      );
      expect(
        secrets.backend.unavailableReason,
        isNot(contains("Add 'secrets.backend: file'")),
      );
      final result = await secrets.store('codelab/p', const SecretText(leak));
      expect(
        (result as ReadOnly).reason,
        'The user config file cannot be read, so secrets are read-only until '
        'it is fixed.',
      );
      expect(result.reason, isNot(contains(leak)));
    });

    test('an invalid secrets.backend value shows its reason without the '
        'value', () async {
      writeConfig('secrets:\n  backend: $leak\n');

      final secrets = await open();

      expect(secrets.backend.writable, isFalse);
      expect(secrets.backend.unavailableReason, startsWith('Secrets.backend'));
      expect(secrets.backend.unavailableReason, isNot(contains(leak)));
      expect(
        secrets.backend.unavailableReason,
        isNot(contains("Add 'secrets.backend: file'")),
      );
    });
  });

  test('an invalid CODELAB_HOME gives a read-only store with the reason, '
      'not an exception', () async {
    final secrets = await openProfileSecrets(
      environment: ConnectionEnvironment.of(const {'CODELAB_HOME': '~bob/cl'}),
      logger: CodeLabEmbeddedLogger(logger: events),
    );

    expect(secrets.backend.writable, isFalse);
    expect(secrets.backend.unavailableReason, isNotEmpty);
    expect(await secrets.names(), isEmpty);
    expect(await secrets.isSet('codelab/x'), isFalse);
    expect(await secrets.read('codelab/x'), isNull);
    expect(
      await secrets.store('codelab/x', const SecretText('v')),
      isA<ReadOnly>(),
    );
  });

  group('translation of the admin outcome (SETUP-5)', () {
    ReadOnly readOnly(setup.SecretReadOnly _) => const ReadOnly('read-only');

    test('SecretStored is Stored', () {
      expect(
        profileSecretWriteOf(
          const setup.SecretStored('codelab/p', 'file'),
          readOnly,
        ),
        isA<Stored>(),
      );
    });

    test(
      'SecretUpdated means a foreign secret was overwritten in a race: it '
      'is Exists, so the profile is not written and nothing is rolled back',
      () async {
        final result = profileSecretWriteOf(
          const setup.SecretUpdated('codelab/p', 'file'),
          readOnly,
        );

        expect(result, isA<Exists>());
      },
    );
  });
}
