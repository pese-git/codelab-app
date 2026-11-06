import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/real_home.dart';

/// Строки `/settings` (client-agent-setup «Состав моста codelab_setup для
/// настройки агента»; design.md change `add-provider-setup-ui`, D17, Q15).
///
/// Снимки строит настоящий `FileAgentConfigStore` на временном
/// `CODELAB_HOME` (D26): происхождение ключей, доверие к проекту и источники
/// `--config`/окружение определяет загрузчик, а не тест.
void main() {
  const leak = 'sk-test-leak-0123456789';
  late RealHome home;

  setUp(() => home = RealHome.create('setting_field_view_'));
  tearDown(() => home.dispose());

  SettingFieldView row(List<SettingFieldView> rows, String key) =>
      rows.singleWhere((r) => r.key == key, orElse: () => fail('нет $key'));

  // Загрузка без проблем: при `no model is configured` итог загрузки пуст и
  // env/--config в снимке не видны (см. отчёт: ограничение снимка).
  const validConfig = '''
agent:
  default_model: gw/m
$gatewayProvider''';

  void writeProject(String name, String text) {
    Directory('${home.project}/.codelab').createSync(recursive: true);
    File('${home.project}/.codelab/$name').writeAsStringSync(text);
  }

  group('состав строк', () {
    test('только ключи реестра со scope shared', () async {
      final rows = settingFieldsOf(await home.load());

      expect(rows, isNotEmpty);
      expect(
        rows.every((r) => r.descriptor.scope == SettingScope.shared),
        isTrue,
      );
      // fileOnly-ключи (agent.fallback, providers.*.api_key) строк не имеют.
      expect(rows.any((r) => r.key == 'agent.fallback'), isFalse);
      expect(rows.any((r) => r.key.endsWith('.api_key')), isFalse);
      expect(
        row(rows, 'agent.effort').descriptor.type,
        SettingType.enumeration,
      );
    });

    test('порядок строк — порядок реестра', () async {
      final rows = settingFieldsOf(await home.load());
      final order = [
        for (final d in SettingsRegistry.all)
          if (d.scope == SettingScope.shared && !d.key.contains('*')) d.key,
      ];

      expect([
        for (final r in rows)
          if (!r.key.startsWith('providers.')) r.key,
      ], order.where((k) => !k.startsWith('providers.')).toList());
    });

    test('ключи providers.* раскрыты по id провайдеров снимка', () async {
      home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/v1
    models:
      m:
        context_window: 8000
  other:
    kind: anthropic
''');
      final rows = settingFieldsOf(await home.load());

      expect(row(rows, 'providers.gw.base_url').value, 'https://gw.test/v1');
      expect(row(rows, 'providers.other.kind').value, 'anthropic');
      expect(row(rows, 'providers.gw.models.m.context_window').value, 8000);
      expect(rows.any((r) => r.key.contains('*')), isFalse);
      // У провайдера без base_url строка есть, значение — по умолчанию.
      expect(row(rows, 'providers.other.base_url').source, isNull);
    });

    test('без провайдеров строк providers.* нет', () async {
      final rows = settingFieldsOf(await home.load());

      expect(rows.where((r) => r.key.startsWith('providers.')), isEmpty);
    });
  });

  group('значение и источник', () {
    test('null-источник — значение по умолчанию', () async {
      final rows = settingFieldsOf(await home.load());
      final effort = row(rows, 'agent.effort');

      expect(effort.source, isNull);
      expect(effort.isDefault, isTrue);
      expect(effort.value, isNull);
      expect(effort.effectiveValue, 'medium');
      expect(effort.displayValue, 'medium');
      expect(effort.sourceName, 'default');
      expect(effort.editable, isTrue);
    });

    test('слой user', () async {
      home.writeConfig('agent:\n  effort: high\n');
      final effort = row(settingFieldsOf(await home.load()), 'agent.effort');

      expect(effort.value, 'high');
      expect(effort.source?.kind, ConfigSourceKind.user);
      expect(effort.sourceName, 'user');
      expect(effort.isDefault, isFalse);
      expect(effort.editable, isTrue);
    });

    test('слой projectLocal', () async {
      writeProject('config.local.yaml', 'budget:\n  max_steps: 7\n');
      final steps = row(settingFieldsOf(await home.load()), 'budget.max_steps');

      expect(steps.value, 7);
      expect(steps.source?.kind, ConfigSourceKind.projectLocal);
      expect(steps.sourceName, 'local');
      expect(steps.editable, isTrue);
    });

    test('слой project доверенного проекта — только чтение', () async {
      home.writeConfig('trusted_projects:\n  - ${home.project}\n');
      writeProject('config.yaml', 'budget:\n  max_steps: 9\n');
      final steps = row(settingFieldsOf(await home.load()), 'budget.max_steps');

      expect(steps.value, 9);
      expect(steps.source?.kind, ConfigSourceKind.project);
      expect(steps.sourceName, 'project');
      expect(steps.editable, isFalse);
    });

    test('ключ недоверенного проекта источником не считается', () async {
      // `logging` из проектного слоя не читается никогда (CFG-3).
      writeProject('config.yaml', 'logging:\n  level: debug\n');
      final level = row(settingFieldsOf(await home.load()), 'logging.level');

      expect(level.source, isNull);
      expect(level.value, isNull);
      expect(level.sourceName, 'default');
    });

    test('приоритетный слой побеждает', () async {
      // local доверенного проекта не ограничен (CFG-3); у недоверенного он
      // подчиняется правилам слоя 3 и ослабляющий ключ отбрасывается.
      home.writeConfig(
        'trusted_projects:\n  - ${home.project}\nbudget:\n  max_steps: 3\n',
      );
      writeProject('config.local.yaml', 'budget:\n  max_steps: 4\n');
      final steps = row(settingFieldsOf(await home.load()), 'budget.max_steps');

      expect(steps.value, 4);
      expect(steps.sourceName, 'local');
    });

    test('окружение CODELAB_* — источник env, не редактируется', () async {
      home.writeConfig(validConfig);
      final rows = settingFieldsOf(
        await home.load({'CODELAB_MAX_STEPS': '11'}),
      );
      final steps = row(rows, 'budget.max_steps');

      expect(steps.value, 11);
      expect(steps.source?.kind, ConfigSourceKind.environment);
      expect(steps.sourceName, 'env');
      expect(steps.editable, isFalse);
    });

    test('файл CODELAB_CONFIG — источник config, не редактируется', () async {
      home.writeConfig(validConfig);
      final extra = File('${home.root.path}/extra.yaml')
        ..writeAsStringSync('budget:\n  max_steps: 12\n');
      final rows = settingFieldsOf(
        await home.load({'CODELAB_CONFIG': extra.path}),
      );
      final steps = row(rows, 'budget.max_steps');

      expect(steps.value, 12);
      expect(steps.source?.kind, ConfigSourceKind.extraFile);
      expect(steps.sourceName, 'config');
      expect(steps.editable, isFalse);
    });

    test('restartRequired берётся из дескриптора', () async {
      final rows = settingFieldsOf(await home.load());

      for (final r in rows) {
        expect(r.restartRequired, r.descriptor.restartRequired);
      }
      expect(rows.any((r) => r.restartRequired), isTrue);
    });
  });

  group('секреты (SETUP-1)', () {
    test('toString строки секретного ключа не содержит значения', () async {
      home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    api_key_secret: $leak
''');
      final rows = settingFieldsOf(await home.load());
      final secret = row(rows, 'providers.gw.api_key_secret');

      expect(secret.descriptor.secret, isTrue);
      expect(secret.toString(), isNot(contains(leak)));
      for (final r in rows) {
        expect(r.toString(), isNot(contains(leak)), reason: r.key);
      }
    });

    test('литеральный api_key не даёт ни строки, ни значения', () async {
      home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    api_key: $leak
''');
      final rows = settingFieldsOf(await home.load());

      for (final r in rows) {
        expect('${r.value} ${r.displayValue} $r', isNot(contains(leak)));
      }
    });

    test('значения map и mapList в строке не раскрываются', () async {
      home.writeConfig('''
mcp:
  servers:
    - name: s
      url: https://mcp.test
      headers:
        Authorization: $leak
''');
      final rows = settingFieldsOf(await home.load());
      final servers = row(rows, 'mcp.servers');

      expect(servers.displayValue, '1 entry');
      expect(
        '${servers.value} ${servers.displayValue} $servers',
        isNot(contains(leak)),
      );
    });

    test('base_url с токеном в query и userinfo маскируется (R0-2)', () async {
      home.writeConfig('''
providers:
  q:
    kind: openai-compatible
    base_url: https://u:$leak@gw.test/v1?api_key=$leak&x=1
  v:
    kind: openai-compatible
    base_url: https://gw.test/v1?token=$leak
''');
      final rows = settingFieldsOf(await home.load());

      for (final id in ['q', 'v']) {
        final url = row(rows, 'providers.$id.base_url');
        expect(url.displayValue, isNot(contains(leak)));
        expect(url.toString(), isNot(contains(leak)));
        expect(url.displayValue, contains('gw.test'));
      }
      expect(
        row(rows, 'providers.v.base_url').displayValue,
        'https://gw.test/v1?token=<redacted>',
      );
    });

    test('литерал по шаблону секрета в строковом значении скрыт', () async {
      home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    models:
      m:
        name: $leak
''');
      final name = row(
        settingFieldsOf(await home.load()),
        'providers.gw.models.m.name',
      );

      expect(name.displayValue, isNot(contains(leak)));
      expect(name.toString(), isNot(contains(leak)));
    });

    test(
      'токен в пути с percent-кодированием скрыт (общее правило ядра)',
      () async {
        home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/sk%2Dtest%2Dleak%2D0123456789/v1
''');
        final url = row(
          settingFieldsOf(await home.load()),
          'providers.gw.base_url',
        );

        expect(url.displayValue, '<redacted>');
        expect(url.value, '<redacted>');
      },
    );

    test(
      'api_key_secret с именем вида sk-… внутри слова не скрывается',
      () async {
        home.writeConfig('''
providers:
  gw:
    kind: openai-compatible
    api_key_secret: codelab/sk-anthropic-production-key
''');
        final secret = row(
          settingFieldsOf(await home.load()),
          'providers.gw.api_key_secret',
        );

        expect(secret.displayValue, 'codelab/sk-anthropic-production-key');
      },
    );
  });
}
