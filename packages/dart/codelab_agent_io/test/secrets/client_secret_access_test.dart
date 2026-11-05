import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Клиентский доступ к секретам (agent-secrets «Клиентский доступ к
/// секретам»; design.md change `add-provider-setup-ui`, D4).
///
/// Только временный `CODELAB_HOME` и фиктивные значения: настоящие файлы
/// секретов и хранилище ОС не читаются.
void main() {
  const leak = 'sk-test-leak-0123456789';

  late Directory root;
  late String home;
  late RecordingLogger logger;

  Future<ClientSecretAccess> open({
    Map<String, String> environment = const {},
  }) => ClientSecretAccess.open(
    codelabHome: home,
    environment: environment,
    logger: logger,
  );

  void writeConfig(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  setUp(() {
    root = Directory.systemTemp.createTempSync('client_secret_access_test');
    home = '${root.path}/home';
    Directory(home).createSync();
    // FileSecretStore требует закрытый от группы $CODELAB_HOME.
    Process.runSync('/bin/chmod', ['700', home]);
    logger = RecordingLogger();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('порядок «переменная, затем бэкенд»', () {
    test('переменная побеждает, без неё — значение бэкенда', () async {
      writeConfig('secrets:\n  backend: file\n');
      await (await open()).admin.store('codelab/p', 'a');

      final withVariable = await open(
        environment: const {'CODELAB_SECRET_CODELAB_P': 'b'},
      );
      expect(await withVariable.read('codelab/p'), 'b');
      expect(await withVariable.isSet('codelab/p'), isTrue);

      final withoutVariable = await open();
      expect(await withoutVariable.read('codelab/p'), 'a');
      expect(await withoutVariable.isSet('codelab/p'), isTrue);
    });

    test('пустая переменная равна отсутствию', () async {
      writeConfig('secrets:\n  backend: file\n');
      await (await open()).admin.store('codelab/p', 'a');

      final access = await open(
        environment: const {'CODELAB_SECRET_CODELAB_P': ''},
      );

      expect(await access.read('codelab/p'), 'a');
    });

    test('нет ни переменной, ни секрета: null и false', () async {
      final access = await open();

      expect(await access.read('codelab/none'), isNull);
      expect(await access.isSet('codelab/none'), isFalse);
    });

    test('isSet по переменной на бэкенде env', () async {
      final access = await open(
        environment: const {'CODELAB_SECRET_CODELAB_P': 'b'},
      );

      expect(access.backend.id, 'env');
      expect(await access.isSet('codelab/p'), isTrue);
    });
  });

  test('без кэша: замена другим экземпляром видна сразу', () async {
    writeConfig('secrets:\n  backend: file\n');
    final reader = await open();
    final writer = await open();
    await writer.admin.store('codelab/p', 'a');
    expect(await reader.read('codelab/p'), 'a');

    await writer.admin.store('codelab/p', 'c');

    expect(await reader.read('codelab/p'), 'c');
  });

  test('без кэша: переменная читается из окружения заново', () async {
    final environment = <String, String>{'CODELAB_SECRET_CODELAB_P': 'a'};
    final access = await open(environment: environment);
    expect(await access.read('codelab/p'), 'a');

    environment['CODELAB_SECRET_CODELAB_P'] = 'b';

    expect(await access.read('codelab/p'), 'b');
  });

  group('бэкенд по пользовательскому слою', () {
    test('нет config.yaml: env только для чтения', () async {
      final access = await open();

      expect(access.backend.id, 'env');
      expect(access.backend.writable, isFalse);
    });

    test('secrets.backend: file — записываемый file', () async {
      writeConfig('secrets:\n  backend: file\n');

      final access = await open();

      expect(access.backend.id, 'file');
      expect(access.backend.writable, isTrue);
    });

    test('битый YAML: env с причиной, без строк файла', () async {
      writeConfig('secrets: [unclosed\n  backend: file\n$leak\n');

      final access = await open();

      expect(access.backend.id, 'env');
      expect(access.backend.writable, isFalse);
      final reason = access.backend.unavailableReason;
      expect(reason, isNotNull);
      expect(reason, isNotEmpty);
      expect(reason, isNot(contains('unclosed')));
      expect(reason, isNot(contains(leak)));
    });

    test('недопустимое значение: env с причиной без эха значения', () async {
      writeConfig('secrets:\n  backend: $leak\n');

      final access = await open();

      expect(access.backend.id, 'env');
      expect(access.backend.writable, isFalse);
      expect(access.backend.unavailableReason, isNotEmpty);
      expect(access.backend.unavailableReason, isNot(contains(leak)));
    });

    test(
      'запись при сломанном конфиге отклоняется как только чтение',
      () async {
        writeConfig('secrets: [unclosed\n');

        final access = await open();

        expect(
          await access.admin.store('codelab/p', 'a'),
          isA<SecretReadOnly>(),
        );
        expect(File('$home/secrets.yaml').existsSync(), isFalse);
      },
    );
  });

  group('configProblem', () {
    test(
      'битый YAML: текст причины, совпадающий с unavailableReason',
      () async {
        writeConfig('secrets: [unclosed\n');

        final access = await open();

        expect(access.configProblem, isNotEmpty);
        expect(access.configProblem, access.backend.unavailableReason);
      },
    );

    test('недопустимое значение: текст причины без эха', () async {
      writeConfig('secrets:\n  backend: $leak\n');

      final access = await open();

      expect(access.configProblem, isNotEmpty);
      expect(access.configProblem, isNot(contains(leak)));
    });

    test('нет файла: null', () async {
      expect((await open()).configProblem, isNull);
    });

    test('нет ключа secrets.backend: null', () async {
      writeConfig('log:\n  level: info\n');

      expect((await open()).configProblem, isNull);
    });

    test('явный env: null', () async {
      writeConfig('secrets:\n  backend: env\n');

      expect((await open()).configProblem, isNull);
    });

    test('file: null', () async {
      writeConfig('secrets:\n  backend: file\n');

      expect((await open()).configProblem, isNull);
    });
  });

  group('значение не утекает', () {
    test('ни события журнала, ни toString не содержат маркера', () async {
      writeConfig('secrets:\n  backend: file\n');
      final access = await open();
      await access.admin.store('codelab/p', leak);

      expect(await access.read('codelab/p'), leak);
      expect(await access.isSet('codelab/p'), isTrue);

      final dump = [
        for (final record in logger.records)
          '${record.event} ${record.fields} ${record.error}',
        access.toString(),
        access.backend.unavailableReason,
        '${await access.admin.list()}',
      ].join('\n');
      expect(dump, isNot(contains(leak)));
    });

    test('ошибка бэкенда при read: SecretStoreUnavailableException без '
        'значения', () async {
      writeConfig('secrets:\n  backend: file\n');
      final access = await open();
      await access.admin.store('codelab/p', leak);
      Process.runSync('/bin/chmod', ['644', '$home/secrets.yaml']);

      Object? caught;
      try {
        await access.read('codelab/p');
      } on SecretStoreUnavailableException catch (error) {
        caught = error;
      }

      expect(caught, isA<SecretStoreUnavailableException>());
      final error = caught! as SecretStoreUnavailableException;
      expect(error.reason, isNotEmpty);
      expect('$error', isNot(contains(leak)));
      for (final record in logger.records) {
        expect('${record.fields} ${record.error}', isNot(contains(leak)));
      }
    });
  });
}
