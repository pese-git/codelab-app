import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/config_writer_harness.dart';
import '../support/fake_secret_process_runner.dart';

/// Запись конфига `ConfigWriter` (agent-configuration «Запись конфига
/// ConfigWriter», сценарии «Сохранение формата», «Ключ модели с точкой»,
/// «Удаление таблицы провайдера», «Сервер MCP по имени», «Конфликт с ручной
/// правкой», «Невалидный итог не пишется», «Недоверенный проект»,
/// «Литеральный токен MCP», «Литеральный токен через config set»,
/// «Литеральный секрет во вложенном значении»; design.md change
/// `add-config-writer-and-reload`, D5, D15; CFG-13).
///
/// Файлы — во временных `CODELAB_HOME` и `cwd`; значения «секретов» в тестах
/// выдуманные, и ни одно из них не должно попасть в текст исключения.
void main() {
  late ConfigWriterHarness h;

  setUp(
    () => h = ConfigWriterHarness.create(
      environment: {'LLM_URL': 'https://env.test/v1'},
    ),
  );
  tearDown(() => h.dispose());

  const user = ConfigTarget.user();

  Future<ConfigWriteResult> apply(
    List<ConfigEdit> edits, {
    ConfigTarget target = user,
  }) async => h.writer.apply(await h.writer.read(target), edits);

  /// Загрузка итоговой конфигурации теми же слоями, что у хоста.
  ConfigLoadResult load() => ConfigLoader().load(
    cwd: h.cwd,
    environment: {'CODELAB_HOME': h.home, 'LLM_URL': 'https://env.test/v1'},
  );

  Matcher inlineSecretWithoutValue(String value, {String? suggested}) =>
      isA<ConfigInlineSecretException>()
          .having((e) => e.toString(), 'toString', isNot(contains(value)))
          .having(
            (e) => e.suggestedSecretName,
            'suggestedSecretName',
            suggested ?? isNotEmpty,
          );

  group('сохранение формата', () {
    test('Сохранение формата: меняется только строка default_model', () async {
      const original =
          '# Agent config\r\n'
          'agent: # models\r\n'
          '  default_model: p/m # chosen\r\n'
          '  fallback: [p/n]\r\n'
          '\r\n'
          '# providers\r\n'
          'providers:\r\n'
          '  p:\r\n'
          '    kind: openai-compatible\r\n'
          '    base_url: https://llm.test/v1\r\n'
          '    models:\r\n'
          '      m: {}\r\n'
          '      n: {}\r\n';
      h.write(h.userPath, original);

      final result = await apply([
        const SetValue('agent.default_model', 'p/n'),
      ]);

      expect(
        h.read(h.userPath),
        original.replaceFirst('default_model: p/m', 'default_model: p/n'),
      );
      expect(result.path, h.userPath);
      expect(
        result.fingerprint,
        configFingerprint(File(h.userPath).readAsBytesSync()),
      );
      expect(result.restartRequiredKeys, isEmpty);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test(
      'Ключ модели с точкой: один ключ и модель читается из загрузки',
      () async {
        h.write(h.userPath, baseConfig);

        await apply([
          const SetValue(
            'providers.p.models."qwen2.5-coder-32b".context_window',
            32768,
          ),
        ]);

        final models = loadYaml(h.read(h.userPath))['providers']['p']['models'];
        expect(
          (models as YamlMap).keys,
          containsAll(['m', 'n', 'qwen2.5-coder-32b']),
        );
        final provider = load().config!.providers.single;
        expect(provider.models['qwen2.5-coder-32b']!.contextWindow, 32768);
      },
    );

    test(
      'строки off, yes и \${VAR} пишутся в кавычках и читаются строками',
      () async {
        h.write(h.userPath, baseConfig);

        await apply([
          const SetValue('providers.p.models.m.name', 'off'),
          const SetValue('providers.p.models.n.name', 'yes'),
          const SetValue('providers.p.base_url', r'${LLM_URL}'),
        ]);

        final text = h.read(h.userPath);
        expect(text, contains('"off"'));
        expect(text, contains('"yes"'));
        expect(text, contains(r"'${LLM_URL}'"));
        final provider = loadYaml(text)['providers']['p'];
        expect(provider['models']['m']['name'], isA<String>());
        expect(provider['models']['m']['name'], 'off');
        expect(provider['models']['n']['name'], 'yes');
        expect(provider['base_url'], r'${LLM_URL}');
      },
    );

    test('ссылка со слэшем пишется в одинарных кавычках без экранирования '
        '(D5); спецсимволы читаются обратно', () async {
      h.write(h.userPath, baseConfig);
      final values = {
        'providers.p.headers.X-A': r'Bearer ${secret:codelab/mcp/gh/x}',
        'providers.p.headers.X-B': r"it's ${a/b}",
        'providers.p.headers.X-C': 'line1\nline2 \${X}',
        'providers.p.headers.X-D': 'ctl\u0001 \${X} \\ back',
      };
      await h.writer.apply(await h.writer.read(const ConfigTarget.user()), [
        for (final e in values.entries) SetValue(e.key, e.value),
      ]);

      final text = h.read(h.userPath);
      expect(text, contains(r"X-A: 'Bearer ${secret:codelab/mcp/gh/x}'"));
      expect(text, isNot(contains(r'\/')));
      final headers = loadYaml(text)['providers']['p']['headers'];
      for (final e in values.entries) {
        expect(headers[e.key.split('.').last], e.value);
      }
    });

    // Первая запись в пустой слой может нести и провайдера, и явную модель по
    // умолчанию одной правкой (как `provider add --default`, D6); без ключа
    // модель выбирается неявно (`optional-default-model`, D1).
    const firstProvider = [
      SetValue('providers.p.kind', 'openai-compatible'),
      SetValue('providers.p.base_url', 'https://llm.test/v1'),
      SetValue('providers.p.models.m.context_window', 8192),
      SetValue('agent.default_model', 'p/m'),
    ];

    test('файл из одних комментариев: комментарии сохраняются', () async {
      h.write(h.userPath, '# my config\n# keep me\n');

      await apply(firstProvider);

      final text = h.read(h.userPath);
      expect(text, startsWith('# my config\n# keep me\n'));
      expect(load().config!.defaultModel.id, 'm');
    });

    test('нет файла: создаётся с новыми ключами', () async {
      final result = await apply(firstProvider);

      expect(load().config!.defaultModel.id, 'm');
      expect(result.fingerprint, isNotEmpty);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test(
      'новый ключ в несортированном отображении добавляется в конец',
      () async {
        // `yaml_edit` вставляет по алфавиту только в отображение с уже
        // отсортированными ключами, иначе в конец (D5, ограничения).
        const original =
            '''
${baseConfig}budget:
  max_tokens: 5000
  max_steps: 4
''';
        h.write(h.userPath, original);

        await apply([const SetValue('budget.max_duration', '5m')]);

        expect(h.read(h.userPath), '$original  max_duration: 5m\n');
      },
    );

    test(
      'Порядок нового ключа: по алфавиту, в конец и в конец списка',
      () async {
        // Характеризация `yaml_edit` (R3-2, D5, «Порядок вставки»): код писателя
        // порядок не выбирает.
        const sorted =
            '''
${baseConfig}budget:
  # steps
  max_steps: 4
  max_tokens: 5000 # tail
''';
        h.write(h.userPath, sorted);
        await apply([const SetValue('budget.max_duration', '5m')]);
        expect(
          h.read(h.userPath),
          '${baseConfig}budget:\n  # steps\n  max_duration: 5m\n'
          '  max_steps: 4\n  max_tokens: 5000 # tail\n',
        );

        const unsorted =
            '''
${baseConfig}budget:
  max_tokens: 5000 # tail
  # steps
  max_steps: 4
''';
        h.write(h.userPath, unsorted);
        await apply([const SetValue('budget.max_duration', '5m')]);
        expect(h.read(h.userPath), '$unsorted  max_duration: 5m\n');

        h.write(
          h.userPath,
          '${baseConfig}mcp:\n  servers:\n    - name: b\n      type: http\n'
          '      url: https://b.test/mcp\n',
        );
        await apply([
          const UpsertMcpServer({
            'name': 'a',
            'type': 'http',
            'url': 'https://a.test/mcp',
          }),
        ]);
        expect(load().config!.mcpServers.map((s) => s.name), ['b', 'a']);
      },
    );

    test('повтор того же значения не меняет байты файла', () async {
      h.write(h.userPath, baseConfig);
      final before = await h.writer.read(user);

      final result = await h.writer.apply(before, [
        const SetValue('agent.default_model', 'p/m'),
      ]);

      expect(h.read(h.userPath), baseConfig);
      expect(result.fingerprint, before.fingerprint);
    });

    test('read: снимок несуществующего файла и разобранного слоя', () async {
      final missing = await h.writer.read(user);
      expect(missing.fingerprint, isNull);
      expect(missing.values, isEmpty);
      expect(missing.path, h.userPath);

      h.write(h.userPath, baseConfig);
      final snapshot = await h.writer.read(user);
      expect(snapshot.fingerprint, configFingerprint(utf8.encode(baseConfig)));
      expect(snapshot.get('agent.default_model'), 'p/m');
    });
  });

  group('удаление', () {
    const withLocal = '''
providers:
  local:
    kind: openai-compatible
    base_url: https://llm.test/v1
    # about models
    models:
      m: {}
  # other provider
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

    test('Удаление таблицы провайдера: поддерево и его комментарии', () async {
      h.write(h.userPath, withLocal);

      await apply([const RemoveTable('providers.local')]);

      final text = h.read(h.userPath);
      expect(text, isNot(contains('local')));
      expect(text, isNot(contains('about models')));
      expect(text, contains('# other provider'));
      expect(load().issues, isEmpty);
    });

    test(
      'RemoveTable несуществующего ключа и не таблицы — ConfigException',
      () async {
        h.write(h.userPath, withLocal);

        await expectLater(
          apply([const RemoveTable('providers.absent')]),
          throwsA(isA<ConfigException>()),
        );
        await expectLater(
          apply([const RemoveTable('agent.default_model')]),
          throwsA(isA<ConfigException>()),
        );
        expect(h.read(h.userPath), withLocal);
      },
    );

    test('UnsetValue убирает ключ вне реестра, если он есть в файле', () async {
      h.write(h.userPath, '${baseConfig}bogus_key: 1\n');
      expect(load().issues, isNotEmpty);

      await apply([const UnsetValue('bogus_key')]);

      expect(h.read(h.userPath), baseConfig);
      expect(load().issues, isEmpty);
    });

    test('UnsetValue удаляет опустевшее отображение-предок', () async {
      h.write(h.userPath, '${baseConfig}logging:\n  level: debug\n');

      await apply([const UnsetValue('logging.level')]);

      expect(h.read(h.userPath), baseConfig);
    });

    test('UnsetValue ключа, которого нет в файле, — ConfigException', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([const UnsetValue('budget.max_steps')]),
        throwsA(isA<ConfigException>()),
      );
      expect(h.read(h.userPath), baseConfig);
    });
  });

  group('серверы MCP', () {
    const withServers = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
mcp:
  servers:
    - name: github
      type: http
      url: https://old.test/mcp
''';

    test(
      'Сервер MCP по имени: github изменён на месте, docs в конце',
      () async {
        h.write(h.userPath, withServers);

        await apply([
          const UpsertMcpServer({
            'name': 'github',
            'type': 'http',
            'url': 'https://new.test/mcp',
          }),
          const UpsertMcpServer({
            'name': 'docs',
            'type': 'http',
            'url': 'https://docs.test/mcp',
          }),
        ]);

        final servers = load().config!.mcpServers.cast<McpHttpServerConfig>();
        expect([for (final s in servers) s.name], ['github', 'docs']);
        expect(servers.first.url, Uri.parse('https://new.test/mcp'));
        final text = h.read(h.userPath);
        expect(
          text.indexOf('name: docs'),
          greaterThan(text.indexOf('name: github')),
        );
        expect(text, isNot(contains('old.test')));
      },
    );

    test('Upsert без списка создаёт mcp.servers', () async {
      h.write(h.userPath, baseConfig);

      await apply([
        const UpsertMcpServer({
          'name': 'docs',
          'type': 'http',
          'url': 'https://docs.test/mcp',
        }),
      ]);

      expect(load().config!.mcpServers.single.name, 'docs');
    });

    test(
      'RemoveMcpServer убирает элемент по имени; нет такого — ConfigException',
      () async {
        h.write(h.userPath, withServers);

        await expectLater(
          apply([const RemoveMcpServer('absent')]),
          throwsA(isA<ConfigException>()),
        );
        await apply([const RemoveMcpServer('github')]);

        expect(load().config!.mcpServers, isEmpty);
      },
    );

    test('RemoveMcpServer("0") не удаляет первый элемент по номеру: только '
        'по name (ревью итерации 4, safety M)', () async {
      h.write(h.userPath, withServers);
      final before = h.read(h.userPath);

      await expectLater(
        apply([const RemoveMcpServer('0')]),
        throwsA(isA<ConfigException>()),
      );

      expect(h.read(h.userPath), before);
    });
  });

  group('отказы без изменения файла', () {
    test('Конфликт с ручной правкой', () async {
      h.write(h.userPath, baseConfig);
      final snapshot = await h.writer.read(user);
      const manual = '$baseConfig# edited by hand\n';
      h.write(h.userPath, manual);

      await expectLater(
        h.writer.apply(snapshot, [const SetValue('budget.max_steps', 3)]),
        throwsA(isA<ConfigConflictException>()),
      );

      expect(h.read(h.userPath), manual);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test('конфликт: файл появился после read несуществующего', () async {
      final snapshot = await h.writer.read(user);
      h.write(h.userPath, baseConfig);

      await expectLater(
        h.writer.apply(snapshot, [const SetValue('budget.max_steps', 3)]),
        throwsA(isA<ConfigConflictException>()),
      );
      expect(h.read(h.userPath), baseConfig);
    });

    test('Невалидный итог не пишется', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([const SetValue('budget.max_steps', 0)]),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.map((i) => i.key),
            'keys',
            contains('budget.max_steps'),
          ),
        ),
      );

      expect(h.read(h.userPath), baseConfig);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test('ключ вне реестра и слой, который ключ не допускает', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([const SetValue('no.such.key', 1)]),
        throwsA(isA<ConfigException>()),
      );
      await expectLater(
        apply([
          const SetValue('trusted_projects', ['/x']),
        ], target: ConfigTarget.project(h.cwd)),
        throwsA(isA<ConfigException>()),
      );
      expect(File(h.projectPath).existsSync(), isFalse);
      expect(h.read(h.userPath), baseConfig);
    });

    test('Отказ YamlEditor: edit the file manually (профиль YAML)', () async {
      const anchored = 'budget: &b\n  max_steps: 1\nagent: *b\n';
      h.write(h.userPath, anchored);
      final snapshot = ConfigSnapshot(
        target: user,
        path: h.userPath,
        fingerprint: configFingerprint(utf8.encode(anchored)),
        values: const {},
      );

      await expectLater(
        h.writer.apply(snapshot, [const SetValue('budget.max_steps', 5)]),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            'cannot edit budget.max_steps automatically; edit the file '
                'manually',
          ),
        ),
      );
      expect(h.read(h.userPath), anchored);
    });

    test('Отказ YamlEditor: путь проходит через список', () async {
      const odd = 'budget: [1, 2]\n';
      h.write(h.userPath, odd);

      await expectLater(
        apply([const SetValue('budget.max_steps', 5)]),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            contains('cannot edit budget.max_steps automatically'),
          ),
        ),
      );
      expect(h.read(h.userPath), odd);
    });

    test('незаданная \${VAR} — предупреждение, а не ошибка', () async {
      h.write(h.userPath, baseConfig);

      final result = await apply([
        const SetValue('providers.p.base_url', r'${NOT_SET_URL}'),
      ]);

      expect(
        result.warnings.map((w) => w.message).join('\n'),
        contains('NOT_SET_URL'),
      );
      expect(h.read(h.userPath), contains(r"'${NOT_SET_URL}'"));
    });

    test(
      'restartRequiredKeys по реестру и лог config.write без значений',
      () async {
        h.write(h.userPath, baseConfig);

        final result = await apply([
          const SetValue('permissions.mode', 'ask'),
          const SetValue('budget.max_steps', 7),
        ]);

        expect(result.restartRequiredKeys, ['permissions.mode']);
        final record = h.logger.eventsOf('config.write').single;
        expect(record.level, LogLevel.info);
        expect(record.fields['path'], h.userPath);
        expect(record.fields['keys'], ['permissions.mode', 'budget.max_steps']);
      },
    );
  });

  // R3-1 (решение пользователя 2026-11-02): запись блокируют только ошибки
  // загрузки, которых не было до правки; прежние — предупреждения результата.
  group('ошибки, существовавшие до правки', () {
    String keysOf(ConfigWriteResult r) =>
        r.warnings.map((w) => w.key).join(',');

    test(
      'пустой слой: budget.max_steps пишется, нет модели — предупреждение '
      'config.model.none (сценарий «Первая запись в пустой конфиг»)',
      () async {
        final result = await apply([const SetValue('budget.max_steps', 40)]);

        expect(loadYaml(h.read(h.userPath))['budget']['max_steps'], 40);
        final warning = result.warnings.singleWhere(
          (w) => w.key == 'agent.default_model',
        );
        expect(warning.event, 'config.model.none');
        expect(
          warning.message,
          'no model is configured; add a provider with at least one model',
        );
      },
    );

    test('провайдер без моделей в пустой конфиг записывается; нет модели — '
        'прежнее предупреждение config.model.none', () async {
      final result = await apply([
        const SetValue('providers.p.kind', 'openai-compatible'),
        const SetValue('providers.p.base_url', 'https://llm.test/v1'),
      ]);

      expect(File(h.userPath).existsSync(), isTrue);
      expect(keysOf(result), contains('agent.default_model'));
      expect(
        result.warnings
            .singleWhere((w) => w.key == 'agent.default_model')
            .event,
        'config.model.none',
      );
    });

    test('первый провайдер с моделью без agent.default_model: записывается '
        'без предупреждений (сценарий «Первый провайдер без модели по '
        'умолчанию»)', () async {
      final result = await apply([
        const SetValue('providers.gw.kind', 'openai-compatible'),
        const SetValue('providers.gw.base_url', 'https://x/v1'),
        const SetValue('providers.gw.models.m.context_window', 8192),
      ]);

      expect(File(h.userPath).existsSync(), isTrue);
      expect(result.warnings, isEmpty);
      expect(loadYaml(h.read(h.userPath)).containsKey('agent'), isFalse);
      expect(load().config!.defaultModel.id, 'm');
    });

    test(
      'удаление последнего провайдера под default_model — новая ошибка',
      () async {
        h.write(h.userPath, baseConfig);

        await expectLater(
          apply([const RemoveTable('providers.p')]),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.issues.map((i) => i.key),
              'keys',
              contains('agent.default_model'),
            ),
          ),
        );
        expect(h.read(h.userPath), baseConfig);
      },
    );

    test(
      'правка исправляет одну из двух ошибок: пишется, вторая — предупреждение',
      () async {
        h.write(h.userPath, '${baseConfig}bogus_key: 1\nbogus_other: 2\n');

        final result = await apply([const UnsetValue('bogus_key')]);

        expect(h.read(h.userPath), isNot(contains('bogus_key')));
        expect(keysOf(result), contains('bogus_other'));
      },
    );

    test(
      'прежняя ошибка ниже места вставки (строка сдвинулась) — предупреждение',
      () async {
        h.write(h.userPath, '${baseConfig}bogus_key: 1\n');

        final result = await apply([
          const SetValue('providers.p.models.n.name', 'N'),
        ]);

        expect(keysOf(result), contains('bogus_key'));
        expect(h.read(h.userPath), contains('N'));
      },
    );

    test('число проблем одной сигнатуры выросло: лишние — новые (ревью '
        'R3-3, D5)', () async {
      const original =
          '${baseConfig}mcp:\n  servers:\n'
          '    - name: x\n      command: a\n'
          '    - name: x\n      command: b\n';
      h.write(h.userPath, original);

      await expectLater(
        apply([
          const SetValue('mcp.servers', [
            {'name': 'x', 'command': 'a'},
            {'name': 'x', 'command': 'b'},
            {'name': 'x', 'command': 'c'},
          ]),
        ]),
        throwsA(isA<ConfigException>()),
      );
      expect(h.read(h.userPath), original);
    });

    test('новая ошибка рядом со старой по-прежнему блокирует', () async {
      h.write(h.userPath, '${baseConfig}budget:\n  max_steps: 0\n');

      await expectLater(
        apply([const SetValue('budget.max_tokens', 0)]),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('прежние проблемы файла не ослабляют отказы', () {
    test('Ошибка ранней ступени: unset bogus_key записывается, прежняя '
        'max_steps — предупреждение (R3-3, решение 2026-11-03)', () async {
      h.write(
        h.userPath,
        '${baseConfig}bogus_key: 1\nbudget:\n  max_steps: 0\n',
      );

      final result = await apply([const UnsetValue('bogus_key')]);

      expect(h.read(h.userPath), isNot(contains('bogus_key')));
      expect(result.warnings.map((w) => w.key), contains('budget.max_steps'));
    });

    test(
      'Новая ошибка поздней ступени при ранней: файл не меняется (R3-3)',
      () async {
        final original =
            '${baseConfig}bogus_key: 1\nbudget:\n  max_steps: 40\n';
        h.write(h.userPath, original);

        await expectLater(
          apply([const SetValue('budget.max_steps', 0)]),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.issues.map((i) => i.key),
              'keys',
              contains('budget.max_steps'),
            ),
          ),
        );
        expect(h.read(h.userPath), original);
      },
    );

    test('ошибка ранней ступени обрывала проверку базы: unset api_key при '
        'прежних base_url и каталоге записывается (R3-1, решение '
        '2026-11-03)', () async {
      const original = '''
agent:
  default_model: lm/m
providers:
  lm:
    api_key: sk-fake-1
    base_url: "https://u:p@ss@host/v1"
    kind: openai-compatible
    models:
      m:
        context_window: 8192
''';
      h.write(h.userPath, original);

      final result = await apply([const UnsetValue('providers.lm.api_key')]);

      expect(h.read(h.userPath), isNot(contains('api_key')));
      expect(
        result.warnings.map((w) => w.key),
        containsAll(['providers.lm.base_url', 'agent.default_model']),
      );
    });

    test('при ранней ошибке базы новая ошибка поздней ступени блокирует '
        '(R3-1)', () async {
      const original = '''
agent:
  default_model: lm/m
providers:
  lm:
    api_key: sk-fake-1
    base_url: https://host/v1
    kind: openai-compatible
    models:
      m: {}
''';
      h.write(h.userPath, original);

      await expectLater(
        apply([
          const UnsetValue('providers.lm.api_key'),
          const SetValue('providers.lm.base_url', 'ftp://host/v1'),
        ]),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.map((i) => i.key),
            'keys',
            contains('providers.lm.base_url'),
          ),
        ),
      );
      expect(h.read(h.userPath), original);
    });

    test('литеральный секрет отклоняется и при прежних проблемах', () async {
      const original = '${baseConfig}bogus_key: 1\n';
      h.write(h.userPath, original);

      await expectLater(
        apply([
          const SetValue('providers.p.headers', {'Cookie': 'not-a-real-c-9'}),
        ]),
        throwsA(isA<ConfigInlineSecretException>()),
      );
      expect(h.read(h.userPath), original);
    });

    test('запрещённый слой отклоняется и при прежних проблемах', () async {
      h.write(h.userPath, '${baseConfig}bogus_key: 1\n');

      await expectLater(
        apply([
          const SetValue('trusted_projects', ['/x']),
        ], target: ConfigTarget.project(h.cwd)),
        throwsA(isA<ConfigException>()),
      );
      expect(File(h.projectPath).existsSync(), isFalse);
    });

    test('та же проблема в другом файле не маскируется прежней', () async {
      // Проблема `type` по `budget.max_steps` уже есть в локальном слое
      // проекта; такая же новая в пользовательском слое — другая проблема.
      h.write(h.userPath, baseConfig);
      h.write(h.localPath, 'budget:\n  max_steps: not-a-number\n');

      await expectLater(
        apply([const SetValue('budget.max_steps', 'not-a-number')]),
        throwsA(isA<ConfigException>()),
      );
      expect(h.read(h.userPath), baseConfig);
    });
  });

  group('доверие проекта', () {
    test('Недоверенный проект: подсказка и файл не создан', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([
          const UpsertMcpServer({
            'name': 'docs',
            'type': 'http',
            'url': 'https://docs.test/mcp',
          }),
        ], target: ConfigTarget.project(h.cwd)),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.toString(),
            'text',
            allOf(contains('--local'), contains('trusted_projects')),
          ),
        ),
      );

      expect(File(h.projectPath).existsSync(), isFalse);
      expect(Directory('${h.cwd}/.codelab').existsSync(), isFalse);
    });

    test('два прежних ошибочных элемента списка в слое недоверенного проекта '
        'не отменяют отказ untrusted_key (ревью R3-3)', () async {
      h.write(h.userPath, baseConfig);
      const original = 'mcp:\n  servers:\n    - command: x\n    - command: y\n';
      h.write(h.projectPath, original);

      await expectLater(
        apply([
          const SetValue('permissions.mode', 'bypass'),
        ], target: ConfigTarget.project(h.cwd)),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.toString(),
            'text',
            contains('trusted_projects'),
          ),
        ),
      );
      expect(h.read(h.projectPath), original);
    });

    for (final (title, yaml) in [
      ('name не строка', 'mcp:\n  servers:\n    - name: 5\n      command: x\n'),
      (
        'ключ с кавычкой в элементе',
        'mcp:\n  servers:\n    - name: q\n      type: stdio\n'
            '      command: x\n      a"b: 1\n',
      ),
      ('ключ с кавычкой на верхнем уровне', 'x"y: 1\n'),
      ('"mode.x" рядом с mode', 'permissions:\n  "mode.x": 1\n'),
      (
        '"servers.x" рядом со списком',
        'mcp:\n  "servers.x": 1\n  servers:\n    - name: s\n'
            '      type: stdio\n      command: x\n',
      ),
      (
        'имя сервера с "]" и bogus',
        'mcp:\n  servers:\n    - name: "a]b"\n      type: stdio\n'
            '      command: x\n      bogus: 1\n',
      ),
      (
        'десять серверов с одним именем',
        'mcp:\n  servers:\n${'    - name: d\n      type: stdio\n      command: x\n' * 10}',
      ),
    ]) {
      test('порча проектного слоя ($title) не отменяет отказ при записи '
          'permissions.mode (ревью R3-3, fail-closed)', () async {
        h.write(h.userPath, baseConfig);
        h.write(h.projectPath, yaml);

        await expectLater(
          apply([
            const SetValue('permissions.mode', 'bypass'),
          ], target: ConfigTarget.project(h.cwd)),
          throwsA(isA<ConfigException>()),
        );
        expect(h.read(h.projectPath), yaml);
      });
    }

    test('удаление испорченного элемента проходит, если кандидат проверяется '
        'полностью (ревью R3-3)', () async {
      h.write(
        h.userPath,
        '${baseConfig}mcp:\n  servers:\n'
        '    - name: bad\n      command: x\n      a"b: 1\n',
      );

      await apply([const RemoveMcpServer('bad')]);

      expect(h.read(h.userPath), isNot(contains('bad')));
    });

    group('проверка неполна (fail-closed, R3-3)', () {
      ConfigIssue incompleteIssue() => ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: '',
        source: h.userPath,
        message: 'the config could not be fully checked; fix the file by hand',
        event: validationIncompleteEvent,
      );

      ConfigWriter writerWith(
        List<ConfigIssue> candidate,
        List<ConfigIssue> baseline,
      ) {
        var calls = 0;
        return ConfigWriter(
          codelabHome: h.home,
          environment: {'CODELAB_HOME': h.home},
          loader: ConfigLoader(),
          candidateCheck:
              (target, text, {required cwd, required environment, platform}) =>
                  (
                    issues: calls++ == 0 ? candidate : baseline,
                    warnings: const [],
                  ),
          logger: h.logger,
          processRunner: FakeSecretProcessRunner(),
          clock: h.clock,
          random: Random(7),
          cwd: h.cwd,
        );
      }

      test('кандидат с неполнотой: отказ, даже если она есть и в базе, файл '
          'не изменён', () async {
        h.write(h.userPath, baseConfig);
        final writer = writerWith([incompleteIssue()], [incompleteIssue()]);

        await expectLater(
          writer.apply(await writer.read(const ConfigTarget.user()), [
            const SetValue('budget.max_steps', 7),
          ]),
          throwsA(isA<ConfigException>()),
        );
        expect(h.read(h.userPath), baseConfig);
      });

      test('база неполна, кандидат полный: запись проходит', () async {
        h.write(h.userPath, baseConfig);
        final writer = writerWith(const [], [incompleteIssue()]);

        await writer.apply(await writer.read(const ConfigTarget.user()), [
          const SetValue('budget.max_steps', 7),
        ]);

        expect(h.read(h.userPath), contains('max_steps: 7'));
      });
    });

    test('доверенный проект: запись проходит', () async {
      h.write(h.userPath, '${baseConfig}trusted_projects: ["${h.cwd}"]\n');

      await apply([
        const UpsertMcpServer({
          'name': 'docs',
          'type': 'http',
          'url': 'https://docs.test/mcp',
        }),
      ], target: ConfigTarget.project(h.cwd));

      expect(File(h.projectPath).existsSync(), isTrue);
      expect(load().config!.mcpServers.single.name, 'docs');
    });
  });

  group('литеральные секреты', () {
    const server = {'name': 'gh', 'type': 'http', 'url': 'https://h.test/mcp'};

    Future<void> expectRejected(
      List<ConfigEdit> edits,
      String value, {
      String? suggested,
    }) async {
      final before = File(h.userPath).existsSync() ? h.read(h.userPath) : null;
      await expectLater(
        apply(edits),
        throwsA(inlineSecretWithoutValue(value, suggested: suggested)),
      );
      expect(File(h.userPath).existsSync() ? h.read(h.userPath) : null, before);
      expect(h.leftovers(h.userPath), isEmpty);
      expect(
        h.logger.records.map((r) => '$r').join('\n'),
        isNot(contains(value)),
      );
    }

    test('Литеральный токен MCP: Authorization в UpsertMcpServer', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected(
        [
          const UpsertMcpServer({
            'name': 'github',
            'type': 'http',
            'url': 'https://h.test/mcp',
            'headers': {'Authorization': 'Bearer not-a-real-key-abc'},
          }),
        ],
        'not-a-real-key-abc',
        suggested: 'codelab/mcp/github/authorization',
      );
    });

    test(
      'Литеральный токен через config set: mcp.servers с X-Api-Key',
      () async {
        h.write(h.userPath, baseConfig);

        await expectRejected([
          SetValue('mcp.servers', [
            {
              ...server,
              'headers': {'X-Api-Key': 'not-a-real-key-k1'},
            },
          ]),
        ], 'not-a-real-key-k1');
      },
    );

    test(
      'Литеральный токен через config set: providers.p.headers с Cookie',
      () async {
        h.write(h.userPath, baseConfig);

        await expectRejected([
          const SetValue('providers.p.headers', {
            'Cookie': 'not-a-real-cookie-1',
          }),
        ], 'not-a-real-cookie-1');
      },
    );

    test('переменная окружения GITHUB_TOKEN в env сервера', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected(
        [
          UpsertMcpServer({
            'name': 'gh',
            'type': 'stdio',
            'command': 'gh-mcp',
            'env': {'GITHUB_TOKEN': 'not-a-real-token-1'},
          }),
        ],
        'not-a-real-token-1',
        suggested: 'codelab/mcp/gh/github_token',
      );
    });

    test('имя нормализуется: x_api-KEY и другой регистр', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        SetValue('mcp.servers', [
          {
            ...server,
            'headers': {'x_api-KEY': 'not-a-real-key-k2'},
          },
        ]),
      ], 'not-a-real-key-k2');
      await expectRejected([
        const SetValue('providers.p.headers', {
          'PROXY-AUTHORIZATION': 'not-a-real-key-k3',
        }),
      ], 'not-a-real-key-k3');
    });

    test('ссылка \${…} и несекретное имя проходят', () async {
      h.write(h.userPath, baseConfig);

      final result = await apply([
        SetValue('mcp.servers', [
          {
            ...server,
            'headers': {
              'X-Api-Key': r'${GH_KEY}',
              'Authorization': r'Bearer ${secret:codelab/mcp/gh/authorization}',
              'X-Team': 'platform',
            },
          },
        ]),
      ]);

      // Переменная окружения писателя не задана: предупреждение, а не отказ.
      expect(result.warnings.map((w) => w.message).join(), contains('GH_KEY'));
      expect(h.read(h.userPath), contains('platform'));
    });

    test(
      'смешанное значение Bearer литерал + \${X} отклоняется (R1-1)',
      () async {
        // Граница до change add-config-literal-secrets-and-migrate (D5)
        // закрыта: значение режется по `${…}`, литерал рядом со ссылкой
        // распознаётся по шаблону.
        h.write(h.userPath, baseConfig);

        await expectRejected([
          SetValue('mcp.servers', [
            {
              ...server,
              'headers': {
                'Authorization': r'Bearer not-a-real-key-m1 ${GH_KEY}',
              },
            },
          ]),
        ], 'not-a-real-key-m1');
      },
    );

    test('Литеральный секрет во вложенном значении: exec.env', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('exec', {
          'env': {'GITHUB_TOKEN': 'not-a-real-token-2'},
        }),
      ], 'not-a-real-token-2');
    });

    test('Литеральный секрет во вложенном значении: лист token', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('exec', {
          'local_fallback': true,
          'extra': {
            'deep': {'token': 'not-a-real-t-3'},
          },
        }),
      ], 'not-a-real-t-3');
    });

    test('api_key провайдера: подсказка codelab/<id>', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected(
        [const SetValue('providers.p.api_key', 'not-a-real-key-ak')],
        'not-a-real-key-ak',
        suggested: 'codelab/p',
      );
    });

    test('непрозрачное поддерево providers.*.auth: access_token', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('providers.p.auth', {
          'access_token': 'not-a-real-key-at1',
        }),
      ], 'not-a-real-key-at1');
    });

    test('регистр и разделители имени: Token и API_KEY', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('providers.p.auth', {'Token': 'not-a-real-key-t2'}),
      ], 'not-a-real-key-t2');
      await expectRejected([
        const SetValue('providers.p.auth', {'API_KEY': 'not-a-real-key-t3'}),
      ], 'not-a-real-key-t3');
    });

    test('вложенный apiKey2 в tools.web', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('tools.web', {
          'search': {
            'backends': {
              'b': {'apiKey2': 'not-a-real-key-w4'},
            },
          },
        }),
      ], 'not-a-real-key-w4');
    });

    test(
      'строки списка под секретным именем в непрозрачном поддереве',
      () async {
        h.write(h.userPath, baseConfig);

        await expectRejected([
          const SetValue('providers.p.key_rotation', {
            'keys': ['not-a-real-key-kr1'],
          }),
        ], 'not-a-real-key-kr1');
        await expectRejected([
          const SetValue('providers.p.auth', {
            'tokens': ['not-a-real-key-kr2'],
          }),
        ], 'not-a-real-key-kr2');
        await expectRejected([
          const SetValue('tools.web', {
            'x': {
              'y': {
                'api_key': ['not-a-real-key-kr3'],
              },
            },
          }),
        ], 'not-a-real-key-kr3');
      },
    );

    test('числовые max_tokens и X-Max-Tokens не считаются секретом', () async {
      h.write(h.userPath, baseConfig);

      await apply([
        const SetValue('llm', {
          'x': {'max_tokens': 4096},
        }),
        const SetValue('tools.web', {
          'search': {
            'backends': {
              'b': {'max_output_tokens': 100, 'context_tokens': 8000},
            },
          },
        }),
        const SetValue('providers.p.headers', {'X-Max-Tokens': 100}),
      ]).then<void>(
        (_) {},
        onError: (Object e) {
          // Схема может отвергнуть число в `headers`, но не как секрет.
          expect(e, isNot(isA<ConfigInlineSecretException>()));
        },
      );
    });

    test('число и булево под секретным именем в непрозрачном узле', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('providers.p.key_rotation', {
          'keys': [123456],
        }),
      ], '123456');
      await expectRejected([
        const SetValue('providers.p.auth', {'token': 987654}),
      ], '987654');
    });

    test('api_key_env с литералом вместо имени переменной — литерал', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('tools.web', {
          'search': {
            'backends': {
              'b': {'api_key_env': 'not-a-real-key-live-123'},
            },
          },
        }),
      ], 'not-a-real-key-live-123');
      await expectRejected([
        const SetValue('tools.web', {
          'search': {
            'backends': {
              'b': {'api_key_secret': 'Not A Name With Spaces'},
            },
          },
        }),
      ], 'Not A Name With Spaces');
    });

    test(
      'ссылки api_key_env и api_key_secret в непрозрачном узле проходят',
      () async {
        h.write(h.userPath, baseConfig);

        await apply([
          const SetValue('tools.web', {
            'search': {
              'backends': {
                'b': {
                  'api_key_env': 'BRAVE_KEY',
                  'api_key_secret': 'codelab/search-b',
                },
              },
            },
          }),
        ]);
      },
    );

    test('число под секретным именем в headers — литерал', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('providers.p.headers', {'X-Api-Key': 123456}),
      ], '123456');
    });

    test(
      'одноимённые серверы mcp.servers различаются номером элемента',
      () async {
        h.write(h.userPath, '''
${baseConfig}mcp:
  servers:
    - name: gh
      type: http
      url: https://h.test/mcp
      headers:
        X-Api-Key: not-a-real-key-dup
''');
        const literal = {'X-Api-Key': 'not-a-real-key-dup'};

        await expectRejected([
          const SetValue('mcp.servers', [
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://h.test/mcp',
              'headers': literal,
            },
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://h.test/mcp',
              'headers': literal,
            },
          ]),
        ], 'not-a-real-key-dup');
      },
    );

    test('exec.secrets: допустимое имя в secret проходит', () async {
      h.write(h.userPath, baseConfig);

      await apply([
        const SetValue('exec.secrets', [
          {'env': 'GH', 'secret': 'codelab/gh'},
        ]),
      ]);

      expect(
        loadYaml(h.read(h.userPath))['exec']['secrets'][0]['secret'],
        'codelab/gh',
      );
    });

    test('exec.secrets: недопустимое имя отклоняется как литерал', () async {
      h.write(h.userPath, baseConfig);

      await expectRejected([
        const SetValue('exec.secrets', [
          {'env': 'GH', 'secret': 'Not-A-Valid Name!'},
        ]),
      ], 'Not-A-Valid Name!');
    });

    test('проверяются только значения, изменённые этой записью', () async {
      // Ручная правка с литералом загружается до 8.11 (D5): она не должна
      // блокировать несвязанные правки и удаление других серверов.
      h.write(h.userPath, '''
${baseConfig}mcp:
  servers:
    - name: gh
      type: http
      url: https://h.test/mcp
      headers:
        X-Api-Key: not-a-real-key-hand
    - name: docs
      type: http
      url: https://docs.test/mcp
''');

      await apply([const SetValue('budget.max_steps', 10)]);
      await apply([const RemoveMcpServer('docs')]);

      expect(h.read(h.userPath), contains('not-a-real-key-hand'));
      expect(loadYaml(h.read(h.userPath))['budget']['max_steps'], 10);
    });
  });

  group('блокировка', () {
    test(
      'занятый lock: ConfigConflictException, чужой lock не тронут',
      () async {
        h.write(h.userPath, baseConfig);
        h.write('${h.userPath}.lock', '4242 aaaa');
        h.touch('${h.userPath}.lock', age: const Duration(seconds: 1));

        await expectLater(
          apply([const SetValue('budget.max_steps', 3)]),
          throwsA(isA<ConfigConflictException>()),
        );

        expect(h.read('${h.userPath}.lock'), '4242 aaaa');
        expect(h.read(h.userPath), baseConfig);
        expect(h.logger.eventsOf('config.write.stale_lock'), isEmpty);
      },
    );

    test('lock старше 10 с снимается с config.write.stale_lock', () async {
      h.write(h.userPath, baseConfig);
      h.write('${h.userPath}.lock', '4242 aaaa');
      h.touch('${h.userPath}.lock', age: const Duration(seconds: 11));

      await apply([const SetValue('budget.max_steps', 3)]);

      final record = h.logger.eventsOf('config.write.stale_lock').single;
      expect(record.level, LogLevel.warning);
      expect(record.fields, {'path': h.userPath, 'age_ms': 11000});
      expect(loadYaml(h.read(h.userPath))['budget']['max_steps'], 3);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test(
      'гонка снятия устаревшего lock: свежий lock возвращается на место',
      () async {
        late ConfigWriterHarness race;
        race = ConfigWriterHarness.create(
          seam: (point) async {
            if (point != ConfigWriteSeam.staleLockChecked) {
              return;
            }
            // Второй писатель успел снять устаревший lock и создать свой
            // свежий, пока первый ещё не переименовал увиденный им файл.
            final lock = '${race.userPath}.lock';
            File(lock).deleteSync();
            race.write(lock, '777 bbbb');
            race.touch(lock, age: Duration.zero);
          },
        );
        addTearDown(race.dispose);
        race.write(race.userPath, baseConfig);
        race.write('${race.userPath}.lock', '4242 aaaa');
        race.touch('${race.userPath}.lock', age: const Duration(seconds: 30));
        final snapshot = await race.writer.read(user);

        await expectLater(
          race.writer.apply(snapshot, [const SetValue('budget.max_steps', 3)]),
          throwsA(isA<ConfigConflictException>()),
        );

        expect(race.read('${race.userPath}.lock'), '777 bbbb');
        expect(race.leftovers(race.userPath), ['config.yaml.lock']);
        expect(race.read(race.userPath), baseConfig);
        expect(race.logger.eventsOf('config.write.stale_lock'), isEmpty);
      },
    );
  });

  group('значения не попадают в вывод', () {
    test(
      'toString исключений и результата не содержит значений правок',
      () async {
        h.write(h.userPath, baseConfig);

        final result = await apply([
          const SetValue('providers.p.models.m.name', 'Display Name Visible'),
        ]);
        const secret = UpsertMcpServer({
          'name': 'gh',
          'headers': {'Authorization': 'not-a-real-key-ts'},
        });

        expect(result.toString(), isNot(contains('Display Name Visible')));
        expect(secret.toString(), isNot(contains('not-a-real-key-ts')));
        expect(
          h.logger.records.map((r) => r.toString()).join('\n'),
          isNot(contains('Display Name Visible')),
        );
      },
    );
  });

  group('итог нескольких файлов: preview и validate(pending:) (R8-10)', () {
    const trusted = 'trusted_projects: [PROJECT]\n';

    void twoLayers() {
      h.write(
        h.userPath,
        trusted.replaceFirst('PROJECT', h.cwd) +
            baseConfig.replaceFirst(
              '    models:',
              '    api_key: sk-${'a1b2c3d4e5' * 3}\n    models:',
            ),
      );
      h.write(
        h.projectPath,
        'providers:\n  p:\n    api_key: ghp_${'abcdef0123' * 3}abcdef\n',
      );
    }

    const user = ConfigTarget.user();
    const project = ConfigTarget.project;

    test('preview возвращает итоговый текст без записи', () async {
      twoLayers();
      final before = h.read(h.userPath);
      final snapshot = await h.writer.read(user);

      final text = await h.writer.preview(snapshot, [
        const SetValue('providers.p.api_key_secret', 'codelab/p'),
        const UnsetValue('providers.p.api_key'),
      ]);

      expect(text.text, contains('api_key_secret: codelab/p'));
      expect(text.text, isNot(contains('api_key:')));
      expect(h.read(h.userPath), before);
    });

    // D25 (change `require-project-folder`): пара «литерал в user + ссылка в
    // project» двух источников больше не даёт (правило группы D23), поэтому
    // смысл `pending` проверяется на другой межслойной зависимости: правка
    // `user` удаляет провайдера `p`, а модель по умолчанию `p/m` задаёт
    // `project`.
    test('без pending правка одного слоя даёт проблему каталога моделей; с '
        'итогом соседнего слоя — чисто', () async {
      h.write(
        h.userPath,
        trusted.replaceFirst('PROJECT', h.cwd) +
            baseConfig
                .replaceFirst('agent:\n  default_model: p/m\n', '')
                .replaceFirst(
                  'providers:\n',
                  'providers:\n  q:\n    kind: openai-compatible\n'
                      '    base_url: https://q.test/v1\n    models:\n'
                      '      m: {}\n',
                ),
      );
      h.write(h.projectPath, 'agent:\n  default_model: p/m\n');
      final snapshot = await h.writer.read(user);
      final edits = [const UnsetValue('providers.p')];
      final neighbour = await h.writer.preview(
        await h.writer.read(project(h.cwd)),
        [const SetValue('agent.default_model', 'q/m')],
      );

      await expectLater(
        h.writer.validate(snapshot, edits),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.map((i) => i.message).join('\n'),
            'messages',
            contains('is not in the model catalog'),
          ),
        ),
      );
      await h.writer.validate(snapshot, edits, pending: [neighbour]);
    });

    test('шов candidateCheck не обходится и при непустом pending', () async {
      twoLayers();
      var calls = 0;
      final writer = ConfigWriter(
        codelabHome: h.home,
        environment: {'CODELAB_HOME': h.home},
        loader: ConfigLoader(),
        candidateCheck:
            (target, text, {required cwd, required environment, platform}) {
              calls++;
              return (issues: const [], warnings: const []);
            },
        logger: h.logger,
        processRunner: FakeSecretProcessRunner(),
        clock: h.clock,
        random: Random(7),
        cwd: h.cwd,
      );
      final neighbour = await writer.preview(
        await writer.read(project(h.cwd)),
        [const UnsetValue('providers.p.api_key')],
      );

      await writer.validate(
        await writer.read(user),
        [const UnsetValue('providers.p.api_key')],
        pending: [neighbour],
      );

      expect(calls, greaterThan(0));
    });
  });
}
