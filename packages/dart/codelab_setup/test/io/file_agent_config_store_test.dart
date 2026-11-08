import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `FileAgentConfigStore` (client-agent-setup «Снимок и запись конфига
/// агента»; design.md change `add-provider-setup-ui`, D6): настоящие файлы во
/// временных каталогах, фиктивные значения, без `~/.codelab` и хранилища ОС.
void main() {
  const leak = 'sk-test-leak-0123456789';

  late Directory root;
  late String home;
  late String project;
  late RecordingLogger logger;

  const provider = '''
agent:
  default_model: p/m
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/p
    models:
      m:
        context_window: 32000
      n:
        context_window: 32000
''';

  /// Проектные слои применяются только к доверенному проекту (§15.3):
  /// `trusted_projects` хранит канонический путь.
  String trusting() =>
      'trusted_projects: [${Directory(project).resolveSymbolicLinksSync()}]\n';

  void write(String path, String text) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  String userFile() => '$home/config.yaml';
  String localFile() => '$project/.codelab/config.local.yaml';

  Map<String, String> envOf([Map<String, String> extra = const {}]) => {
    // HOME нужен загрузчику для раскрытия `~`; настоящий каталог не трогаем.
    'HOME': root.path,
    'CODELAB_HOME': home,
    ...extra,
  };

  Future<FileAgentConfigStore> open({
    Map<String, String> env = const {},
    String? extraConfig,
    bool withProject = true,
  }) async {
    final environment = envOf(env);
    return FileAgentConfigStore(
      paths: ConfigPaths(
        codelabHome: home,
        projectDir: withProject ? project : null,
        extraConfig: extraConfig,
      ),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: logger,
      ),
      logger: logger,
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_agent_config_store_test');
    home = '${root.path}/home';
    project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    logger = RecordingLogger();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('snapshot', () {
    test('слои, итог загрузки и бэкенд секретов', () async {
      write(userFile(), provider);
      final store = await open();

      final snapshot = await store.snapshot(cwd: project);

      expect(snapshot.cwd, project);
      expect(snapshot.layers.keys, {
        ConfigLayer.user,
        ConfigLayer.project,
        ConfigLayer.projectLocal,
      });
      final user = snapshot.layers[ConfigLayer.user]!;
      expect(user.fingerprint, isNotNull);
      expect(user.get('agent.default_model'), 'p/m');
      expect(snapshot.layers[ConfigLayer.projectLocal]!.fingerprint, isNull);
      expect(snapshot.loaded.issues, isEmpty);
      expect(snapshot.loaded.config, isNotNull);
      expect(snapshot.secrets.id, 'env');
      expect(snapshot.secrets.writable, isFalse);
      expect(snapshot.defaultModel, 'p/m');
    });

    test(
      'бэкенд секретов — по secrets.backend пользовательского слоя',
      () async {
        write(userFile(), '$provider\nsecrets:\n  backend: file\n');
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.secrets.id, 'file');
        expect(snapshot.secrets.writable, isTrue);
      },
    );

    test('источники ключей по слоям', () async {
      write(userFile(), '$provider${trusting()}');
      write(
        localFile(),
        'providers:\n  p:\n    base_url: https://local.test/v1\n',
      );
      final store = await open();

      final snapshot = await store.snapshot(cwd: project);

      final kind = snapshot.origins['providers.p.kind']!;
      expect(kind.kind, ConfigSourceKind.user);
      expect(kind.label, snapshot.layers[ConfigLayer.user]!.path);
      expect(kind.editable, isTrue);
      final baseUrl = snapshot.origins['providers.p.base_url']!;
      expect(baseUrl.kind, ConfigSourceKind.projectLocal);
      expect(baseUrl.label, snapshot.layers[ConfigLayer.projectLocal]!.path);
      expect(
        snapshot.origins['providers.p.models.m.context_window']!.kind,
        ConfigSourceKind.user,
      );
      expect(
        snapshot.origins['agent.default_model']!.kind,
        ConfigSourceKind.user,
      );
    });

    test(
      'слой 3 недоверенного проекта: значение не применено — источник user',
      () async {
        write(userFile(), provider);
        write(
          '$project/.codelab/config.yaml',
          'providers:\n  p:\n    base_url: https://evil.test/v1\n',
        );
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.leaves['providers.p.base_url'], 'https://llm.test/v1');
        expect(
          snapshot.origins['providers.p.base_url']!.kind,
          ConfigSourceKind.user,
        );
      },
    );

    group('новая установка', () {
      // Агент без `agent.default_model` не стартует, но это не проблема
      // чтения файла: страница Providers показывает пустое состояние, а не
      // «Unreadable».
      for (final entry in <String, String?>{
        'нет config.yaml': null,
        'только secrets': 'secrets:\n  backend: file\n',
      }.entries) {
        test(entry.key, () async {
          if (entry.value != null) {
            write(userFile(), entry.value!);
          }
          final store = await open();

          final snapshot = await store.snapshot(cwd: project);

          expect(snapshot.isReadable(ConfigLayer.user), isTrue);
          expect(
            snapshot.issues,
            isEmpty,
            reason: snapshot.issues.map((i) => '$i').join('; '),
          );
          expect(
            await providerEntriesOf(
              snapshot,
              environment: const {},
              isSecretSet: (_) async => false,
            ),
            isEmpty,
          );
        });
      }
    });

    group('отклонённый конфиг: rejections (Q30 (в), D11)', () {
      // Настоящий загрузчик: незаданная `${PG_URL}` в `env` MCP-сервера делает
      // конфиг отклонённым для агента, но файл читается и правится.
      const postgres = '''
mcp:
  servers:
    - name: postgres
      type: stdio
      command: /usr/bin/pg-mcp
      env:
        DATABASE_URL: \${PG_URL}
''';

      test('незаданная переменная: путь элемента и событие, issues и '
          'startProblems прежние', () async {
        write(userFile(), '$provider$postgres');
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        final rejection = snapshot.rejections.single;
        expect(rejection.kind, ConfigIssueKind.value);
        expect(rejection.key, 'mcp.servers[postgres].env.DATABASE_URL');
        expect(rejection.event, 'config.variable.unset');
        expect(snapshot.issues, isEmpty);
        expect(snapshot.startProblems, [rejection]);
      });

      test('новая установка с той же ссылкой: config.model.none остаётся '
          'в startProblems и не попадает в rejections', () async {
        write(userFile(), 'secrets:\n  backend: file\n$postgres');
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.rejections.map((i) => i.key), [
          'mcp.servers[postgres].env.DATABASE_URL',
        ]);
        expect(
          snapshot.startProblems.map((i) => i.event),
          containsAll(['config.model.none', 'config.variable.unset']),
        );
        expect(snapshot.issues, isEmpty);
      });

      test('переменная задана в окружении: rejections пуст, значение не '
          'попадает в проблемы', () async {
        write(userFile(), '$provider$postgres');
        final store = await open(env: const {'PG_URL': leak});

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.rejections, isEmpty);
        expect('${snapshot.loaded.issues}', isNot(contains(leak)));
      });

      test('новая установка без MCP: rejections пуст', () async {
        write(userFile(), 'secrets:\n  backend: file\n');
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.rejections, isEmpty);
      });
    });

    group('неверный ключ из внешнего источника — не «отсутствует»', () {
      const bad = 'nope/none';

      test('значение только в файле --config', () async {
        write(userFile(), 'secrets:\n  backend: file\n');
        final extra = '${root.path}/team.yaml';
        write(extra, 'agent:\n  default_model: $bad\n');
        final store = await open(extraConfig: extra);

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.startProblems, isEmpty);
        expect(
          snapshot.issues.map((i) => i.key),
          contains('agent.default_model'),
        );
      });

      for (final variant in ['симлинк', 'путь с ..']) {
        test('--config через $variant: проблема в issues', () async {
          write(userFile(), 'secrets:\n  backend: file\n');
          final real = '${root.path}/real/team.yaml';
          write(real, 'agent:\n  default_model: $bad\n');
          final String given;
          if (variant == 'симлинк') {
            given = '${root.path}/link.yaml';
            Link(given).createSync(real);
          } else {
            given = '${root.path}/other/../real/team.yaml';
            Directory('${root.path}/other').createSync();
          }
          final store = await open(extraConfig: given);

          final snapshot = await store.snapshot(cwd: project);

          expect(snapshot.startProblems, isEmpty);
          expect(
            snapshot.issues.map((i) => i.key),
            contains('agent.default_model'),
          );
        });
      }

      test('значение только в переменной окружения', () async {
        write(userFile(), 'secrets:\n  backend: file\n');
        final store = await open(env: const {'CODELAB_MODEL': bad});

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.startProblems, isEmpty);
        expect(
          snapshot.issues.map((i) => i.key),
          contains('agent.default_model'),
        );
      });
    });

    group('недоверенный проект (CFG-3)', () {
      const projectOverride =
          'providers:\n'
          '  p:\n'
          '    base_url: https://llm.test/v1\n'
          '  q:\n'
          '    kind: openai-compatible\n'
          '    base_url: https://evil.test/v1\n';

      Future<List<ProviderEntryView>> entries(AgentConfigSnapshot s) =>
          providerEntriesOf(
            s,
            environment: const {},
            isSecretSet: (_) async => false,
          );

      test('совпавшее значение приписывается слою user, не слою 3', () async {
        write(userFile(), provider);
        write('$project/.codelab/config.yaml', projectOverride);
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(
          snapshot.origins['providers.p.base_url']!.kind,
          ConfigSourceKind.user,
        );
        final list = await entries(snapshot);
        expect(list.map((e) => e.id), ['p']);
        expect(list.single.editable, isTrue);
      });

      test('при проблеме загрузки слой 3 тоже не попадает в список', () async {
        // `budget.max_steps: 0` ломает загрузку, и `leaves` строятся слиянием
        // слоёв: недоверенный проект не должен добавлять провайдеров.
        write(userFile(), '$provider\nbudget:\n  max_steps: 0\n');
        write('$project/.codelab/config.yaml', projectOverride);
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.loaded.issues, isNotEmpty);
        expect(
          snapshot.leaves.keys.any((k) => k.startsWith('providers.q')),
          isFalse,
        );
        expect((await entries(snapshot)).map((e) => e.id), ['p']);
        expect(
          snapshot.origins['providers.p.base_url']!.kind,
          ConfigSourceKind.user,
        );
      });

      test('доверенный проект: слой 3 виден и только для чтения', () async {
        write(userFile(), '$provider${trusting()}');
        write('$project/.codelab/config.yaml', projectOverride);
        final store = await open();

        final snapshot = await store.snapshot(cwd: project);

        final list = await entries(snapshot);
        expect(list.map((e) => e.id), ['p', 'q']);
        expect(list.last.source.kind, ConfigSourceKind.project);
        expect(list.last.editable, isFalse);
      });
    });

    test('файл --config и переменная окружения — свои источники', () async {
      write(userFile(), provider);
      final extra = '${root.path}/team.yaml';
      write(
        extra,
        'providers:\n  t:\n    kind: openai-compatible\n'
        '    base_url: https://team.test/v1\n'
        '    models:\n      tm:\n        context_window: 8000\n',
      );
      final store = await open(
        extraConfig: extra,
        env: const {'CODELAB_MODEL': 'p/n'},
      );

      final snapshot = await store.snapshot(cwd: project);

      final team = snapshot.origins['providers.t.base_url']!;
      expect(team.kind, ConfigSourceKind.extraFile);
      expect(team.label, extra);
      expect(team.editable, isFalse);
      // Модель из файла `user` (`p/m`) переопределила переменная (`p/n`).
      final model = snapshot.origins['agent.default_model']!;
      expect(model.kind, ConfigSourceKind.environment);
      expect(model.editable, isFalse);
    });

    test(
      '--config с чужим расширением — проблема загрузки, не исключение',
      () async {
        write(userFile(), provider);
        final store = await open(extraConfig: '${root.path}/codelab.toml');

        final snapshot = await store.snapshot(cwd: project);

        expect(snapshot.loaded.config, isNull);
        expect(snapshot.loaded.issues, isNotEmpty);
      },
    );

    test('битый config.yaml: слой не читается, проблема загрузчика', () async {
      write(userFile(), 'providers: [unclosed\n');
      final store = await open();

      final snapshot = await store.snapshot(cwd: project);

      expect(snapshot.isReadable(ConfigLayer.user), isFalse);
      expect(snapshot.layers.containsKey(ConfigLayer.user), isFalse);
      expect(snapshot.isReadable(ConfigLayer.projectLocal), isTrue);
      expect(snapshot.loaded.issues, isNotEmpty);
      expect(
        snapshot.loaded.issues.map((i) => i.toString()).join(),
        isNot(contains('unclosed')),
      );
    });

    test('значения секретов не попадают в журнал', () async {
      write(userFile(), provider);
      final store = await open(env: {'CODELAB_SECRET_CODELAB_P': leak});

      await store.snapshot(cwd: project);

      expect(
        logger.records.map((r) => '${r.event} ${r.fields}').join(),
        isNot(contains(leak)),
      );
    });
  });

  group('apply: каждое исключение ConfigWriter — свой исход', () {
    test('успех: ConfigSaved с отпечатком и ключами перезапуска', () async {
      write(userFile(), provider);
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);

      final outcome = await store.apply(snapshot.layers[ConfigLayer.user]!, [
        const SetValue('agent.default_model', 'p/m'),
        const SetValue('providers.p.base_url', 'https://new.test/v1'),
      ]);

      expect(outcome, isA<ConfigSaved>());
      final saved = outcome as ConfigSaved;
      final after = await store.snapshot(cwd: project);
      expect(saved.fingerprint, after.layers[ConfigLayer.user]!.fingerprint);
      expect(File(userFile()).readAsStringSync(), contains('https://new.test'));
      expect(after.loaded.config, isNotNull);
    });

    test('ConfigConflict: файл не перезаписывается, автоповтора нет', () async {
      write(userFile(), provider);
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);
      final edited = '$provider# edited by hand\n';
      write(userFile(), edited);

      final outcome = await store.apply(snapshot.layers[ConfigLayer.user]!, [
        const SetValue('providers.p.base_url', 'https://new.test/v1'),
      ]);

      expect(outcome, isA<ConfigConflict>());
      // Писатель разрешает ссылки (`/var` → `/private/var` на macOS).
      expect(
        (outcome as ConfigConflict).path,
        snapshot.layers[ConfigLayer.user]!.path,
      );
      expect(File(userFile()).readAsStringSync(), edited);
    });

    test('ConfigRejected: проблемы валидатора, файл не изменён', () async {
      write(userFile(), provider);
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);

      final outcome = await store.apply(snapshot.layers[ConfigLayer.user]!, [
        const SetValue('budget.max_steps', 0),
      ]);

      expect(outcome, isA<ConfigRejected>());
      expect((outcome as ConfigRejected).issues, isNotEmpty);
      expect(File(userFile()).readAsStringSync(), provider);
    });

    test(
      'ConfigInlineSecret раньше ConfigRejected: литерал в заголовке',
      () async {
        write(userFile(), provider);
        final store = await open();
        final snapshot = await store.snapshot(cwd: project);

        final outcome = await store.apply(snapshot.layers[ConfigLayer.user]!, [
          const UpsertMcpServer({
            'name': 'gh',
            'type': 'http',
            'url': 'https://mcp.test/',
            'headers': {'Authorization': 'Bearer $leak'},
          }),
        ]);

        // ConfigInlineSecretException — подкласс ConfigException, поэтому порядок
        // проверок в `apply` определяет исход.
        expect(outcome, isA<ConfigInlineSecret>());
        final inline = outcome as ConfigInlineSecret;
        expect(inline.key, contains('Authorization'));
        expect(inline.suggestedSecretName, 'codelab/mcp/gh/authorization');
        expect('$outcome ${inline.key}', isNot(contains(leak)));
        expect(File(userFile()).readAsStringSync(), provider);
      },
    );

    test('запись в projectLocal создаёт файл', () async {
      write(userFile(), '$provider${trusting()}');
      final store = await open();
      final snapshot = await store.snapshot(cwd: project);

      final outcome = await store.apply(
        snapshot.layers[ConfigLayer.projectLocal]!,
        [const SetValue('providers.p.base_url', 'https://local.test/v1')],
      );

      expect(outcome, isA<ConfigSaved>());
      expect(File(localFile()).readAsStringSync(), contains('local.test'));
    });
  });
}
