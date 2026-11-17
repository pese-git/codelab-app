import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Признак «секреты лежат в файле конфига» и доступность мигратора
/// (embedded-agent «Признак секретов в файле конфига», сценарии «Литеральный
/// ключ в конфиге», «Конфиг со ссылками», «Мигратор доступен через io.dart»;
/// design.md change `add-config-literal-secrets-and-migrate`, D8).
///
/// Всё во временном каталоге; значение «ключа» синтетическое и не должно
/// попасть ни в лог, ни в отчёт. Сети нет: агент открывается, ход не идёт.
void main() {
  final literal = 'sk-${'a1b2c3d4e5' * 3}';

  late Directory temp;
  late String home;
  late Directory project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_secrets_in_config_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    project = Directory('${temp.path}/project')..createSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    await agent?.dispose();
    agent = null;
    temp.deleteSync(recursive: true);
  });

  void writeConfig(String keyLine, {bool fileBackend = false}) =>
      File('$home/config.yaml').writeAsStringSync(
        '${fileBackend ? 'secrets:\n  backend: file\n' : ''}'
        'providers:\n'
        '  p:\n'
        '    kind: openai-compatible\n'
        '    base_url: https://p.test/v1\n'
        '    $keyLine\n'
        '    models:\n'
        '      m: {}\n'
        'agent:\n'
        '  default_model: p/m\n',
      );

  Future<EmbeddedAgent> open() => localEmbeddedAgentOpener(
    environment: {'CODELAB_HOME': home},
    logger: logger,
    httpClient: MockClient((_) async => throw StateError('no network')),
  )(cwd: project.path, hostProfile: 'embedded-cli');

  group('secretsInConfig', () {
    test('литеральный ключ: true, агент открыт, значения в логе нет', () async {
      writeConfig('api_key: $literal');
      agent = await open();
      expect(agent!.secretsInConfig, isTrue);
      expect(logger.eventsOf('config.secret.in_file'), isNotEmpty);
      for (final record in logger.records) {
        expect('${record.fields} ${record.error}', isNot(contains(literal)));
      }
    });

    test('ссылка api_key_secret: false', () async {
      writeConfig('api_key_secret: codelab/p');
      agent = await open();
      expect(agent!.secretsInConfig, isFalse);
    });

    test('признак фиксируется при открытии и не пересчитывается', () async {
      writeConfig('api_key: $literal');
      agent = await open();
      writeConfig('api_key_secret: codelab/p');
      expect(agent!.secretsInConfig, isTrue);
    });

    test('scriptedEmbeddedAgentOpener: false', () async {
      agent = await scriptedEmbeddedAgentOpener(
        llm: {'steps': <Object?>[]},
        codelabHome: home,
        logger: logger,
      )(cwd: project.path, hostProfile: 'embedded-cli');
      expect(agent!.secretsInConfig, isFalse);
    });
  });

  group('мигратор через io.dart', () {
    Future<SecretMigrationReport> dryRun([
      Map<String, String> extraEnv = const {},
    ]) => SecretMigrator().run(
      SecretMigrationOptions(
        cwd: project.path,
        environment: {'CODELAB_HOME': home, ...extraEnv},
        layers: const {
          ConfigLayer.user,
          ConfigLayer.project,
          ConfigLayer.projectLocal,
        },
        dryRun: true,
      ),
    );

    test('--dry-run над литеральным api_key: пункт без значения', () async {
      writeConfig('api_key: $literal', fileBackend: true);
      final report = await dryRun();
      expect(report.problems, isEmpty);
      expect(report.items, isNotEmpty);
      expect(report.items.first, isA<SecretPlanItem>());
      expect(report.canApply, isTrue);
      expect(report.readOnlyBackend, isFalse);
      final text = [...report.stdoutLines, ...report.stderrLines].join('\n');
      expect(text, contains('providers.p.api_key'));
      expect(text, isNot(contains(literal)));
      expect(File('$home/config.yaml').readAsStringSync(), contains(literal));
    });

    test('бэкенд env: только для чтения, применить нельзя', () async {
      writeConfig('api_key: $literal');
      final report = await dryRun();
      expect(report.readOnlyBackend, isTrue);
      expect(report.canApply, isFalse);
      expect(report.exitCode, 1);
    });

    test(
      'конфликт имени с хранилищем: nameConflict без разбора текста',
      () async {
        writeConfig('api_key: $literal', fileBackend: true);
        final secrets = File('$home/secrets.yaml')
          ..writeAsStringSync('"codelab/p": "old-value-0001"\n');
        Process.runSync('/bin/chmod', ['600', secrets.path]);
        final report = await dryRun();
        expect(report.nameConflict, isTrue);
        expect(report.canApply, isFalse);
        expect(report.onlyExtraLayerFindings, isFalse);
      },
    );

    test('находки только в CODELAB_CONFIG: onlyExtraLayerFindings', () async {
      writeConfig('', fileBackend: true);
      final extra = File('${temp.path}/extra.yaml')
        ..writeAsStringSync('providers:\n  p:\n    api_key: $literal\n');
      final report = await dryRun({'CODELAB_CONFIG': extra.path});
      expect(report.onlyExtraLayerFindings, isTrue);
      expect(report.canApply, isFalse);
      expect(report.nameConflict, isFalse);
    });

    test(
      'secretMigrationOptionsFor: --all, без force, окружение открывателя',
      () async {
        writeConfig('api_key: $literal', fileBackend: true);
        final options = secretMigrationOptionsFor(
          cwd: project.path,
          environment: {'CODELAB_HOME': home},
          dryRun: true,
        );
        expect(options.layers, {
          ConfigLayer.user,
          ConfigLayer.project,
          ConfigLayer.projectLocal,
        });
        expect(options.force, isFalse);
        expect(options.dryRun, isTrue);
        // Без -DCODELAB_ALLOW_TEST_SECRETS путь тестового хранилища не берётся.
        expect(options.testStorePath, isNull);
        final report = await SecretMigrator().run(options);
        expect(report.canApply, isTrue);
        expect(report.home, home);
      },
    );
  });
}
