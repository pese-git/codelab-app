import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `providerKeysOf` (design.md change `add-provider-setup-ui`, D7): порт ключей
/// мастера поверх `ClientSecretAccess` на временном `CODELAB_HOME`; фиктивные
/// значения, без хранилища ОС.
void main() {
  const leak = 'sk-test-leak-0123456789';

  late Directory root;
  late String home;
  late RecordingLogger logger;

  Future<ProviderKeys> open({
    String? config,
    Map<String, String> env = const {},
  }) async {
    if (config != null) {
      File('$home/config.yaml').writeAsStringSync(config);
    }
    final access = await ClientSecretAccess.open(
      codelabHome: home,
      environment: env,
      logger: logger,
    );
    return providerKeysOf(access, home: home);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('provider_keys_test');
    home = '${root.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    logger = RecordingLogger();
  });

  tearDown(() => root.deleteSync(recursive: true));

  const fileBackend = 'secrets:\n  backend: file\n';

  test(
    'SecretStored — ProviderKeyCreated, SecretUpdated — ProviderKeyReplaced',
    () async {
      final keys = await open(config: fileBackend);
      expect(keys.backend.id, 'file');
      expect(keys.backend.writable, isTrue);
      expect(keys.readOnlyHint, isNull);

      expect(
        await keys.write('codelab/p', SecretValue(leak)),
        isA<ProviderKeyCreated>(),
      );
      expect(
        await keys.write('codelab/p', SecretValue('second')),
        isA<ProviderKeyReplaced>(),
      );
      expect((await keys.read('codelab/p'))!.reveal(), 'second');
    },
  );

  test(
    'stored не учитывает CODELAB_SECRET_*, read — переменная раньше файла',
    () async {
      var keys = await open(config: fileBackend);
      await keys.write('codelab/p', SecretValue('from-file'));

      keys = await open(
        env: {
          'CODELAB_SECRET_CODELAB_P': 'from-env',
          'CODELAB_SECRET_CODELAB_Q': 'only-env',
        },
      );
      expect(await keys.stored('codelab/p'), isTrue);
      expect((await keys.read('codelab/p'))!.reveal(), 'from-env');
      expect(await keys.stored('codelab/q'), isFalse);
      expect((await keys.read('codelab/q'))!.reveal(), 'only-env');
      expect(await keys.read('codelab/none'), isNull);
    },
  );

  test(
    'бэкенд только для чтения: ProviderKeyRefused с подсказкой D3',
    () async {
      final keys = await open();
      expect(keys.backend.writable, isFalse);
      expect(keys.readOnlyHint, contains('read-only'));

      final outcome = await keys.write('codelab/p', SecretValue(leak));

      final refused = outcome as ProviderKeyRefused;
      expect(refused.reason, contains('read-only'));
      expect(refused.reason, contains('CODELAB_SECRET_CODELAB_P'));
      expect(refused.reason, isNot(contains(leak)));
    },
  );

  test('неверное имя — отказ без значения', () async {
    final keys = await open(config: fileBackend);

    final outcome = await keys.write('Bad Name', SecretValue(leak));

    expect(outcome, isA<ProviderKeyRefused>());
    expect((outcome as ProviderKeyRefused).reason, isNot(contains(leak)));
  });

  test('delete переводит исходы администратора', () async {
    final keys = await open(config: fileBackend);
    await keys.write('codelab/p', SecretValue(leak));

    expect(await keys.delete('codelab/p'), SecretDeletion.deleted);
    expect(await keys.delete('codelab/p'), SecretDeletion.notSet);
  });

  test('битый конфиг: подсказка называет причину', () async {
    final keys = await open(config: 'secrets: [unclosed\n');

    expect(keys.backend.writable, isFalse);
    expect(keys.readOnlyHint, isNotNull);
    expect(keys.readOnlyHint, contains('config.yaml'));
  });
}
