import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/cli/config_output.dart';
import 'package:codelab_agent_io/src/config/environment_layer.dart'
    show buildEnvironmentLayer, environmentLayerVariables;
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Маскирование вывода `config get` и `provider list` (agent-configuration
/// «Подкоманды записи и чтения конфига», сценарии «get маскирует секреты» и
/// «Непрозрачные поддеревья»; design.md change
/// `add-config-writer-and-reload`, D6, R0-2; задача 4.1).
///
/// Подкоманды печатают значения, а файл мог быть правлен руками до
/// редакции секретов (8.11), поэтому одна функция `cli/config_output.dart`
/// закрывает ветки: ключ из `inlineSecretKeys`, секретное имя заголовка,
/// `env` и любого листа, ссылки как есть, слой `env:*` и флагов, непрозрачные
/// поддеревья, userinfo URL. Тест на каждую ветку; значения «секретов»
/// выдуманные.
void main() {
  const redacted = '<redacted>';
  const opaque = '<opaque: edit the file>';

  /// Одно значение под ключом [key] файлового слоя.
  Object? mask(Object? value, String key) => maskConfigValue(value, key: key);

  group('значение листа маскируется', () {
    test('ключ из inlineSecretKeys на любой глубине → <redacted>', () {
      for (final name in inlineSecretKeys) {
        expect(mask({name: 'sk-1'}, 'providers.p'), {
          name: redacted,
        }, reason: name);
      }
      // Глубже первого уровня.
      expect(
        mask({
          'p': {'api_key': 'sk-1'},
        }, 'providers'),
        {
          'p': {'api_key': redacted},
        },
      );
    });

    test('секретный заголовок (нормализованное имя) → <redacted>, '
        'обычный остаётся', () {
      final result = mask([
        {
          'name': 'gh',
          'type': 'http',
          'url': 'https://h',
          'headers': {
            'Authorization': 'Bearer lit-1',
            'X-Api-Key': 'lit-2',
            'Cookie': 'lit-3',
            'X-Trace': 'abc',
          },
        },
      ], 'mcp.servers');

      final headers = ((result! as List).single as Map)['headers'] as Map;
      expect(headers['Authorization'], redacted);
      expect(headers['X-Api-Key'], redacted);
      expect(headers['Cookie'], redacted);
      expect(headers['X-Trace'], 'abc');
    });

    test('секретная переменная env сервера → <redacted>, обычная остаётся', () {
      final result = mask({
        'GITHUB_TOKEN': 'ghp_lit',
        'DB_PASSWORD': 'lit',
        'MODE': 'fast',
      }, 'mcp.servers[gh].env');

      expect(result, {
        'GITHUB_TOKEN': redacted,
        'DB_PASSWORD': redacted,
        'MODE': 'fast',
      });
    });

    test(r'ссылки ${secret:…} и ${VAR} печатаются как есть', () {
      expect(
        mask({
          'Authorization': r'Bearer ${secret:codelab/mcp/gh/authorization}',
          'GITHUB_TOKEN': r'${GH}',
        }, 'mcp.servers[gh].headers'),
        {
          'Authorization': r'Bearer ${secret:codelab/mcp/gh/authorization}',
          'GITHUB_TOKEN': r'${GH}',
        },
      );
      // Ключ из inlineSecretKeys со ссылкой — тоже как есть.
      expect(mask({'api_key': r'${KEY}'}, 'providers.p'), {
        'api_key': r'${KEY}',
      });
    });

    test('секретное имя листа вне headers и env → <redacted>; число под '
        'секретным именем тоже', () {
      expect(
        mask({
          'password': 'pw-1',
          'client_secret': 'cs-1',
          'token': 123456,
        }, 'providers.p'),
        {'password': redacted, 'client_secret': redacted, 'token': redacted},
      );
    });

    test('листья схемы со ссылкой на секрет и счётчики не маскируются', () {
      expect(
        mask({
          'api_key_secret': 'codelab/gw',
          'api_key_env': 'GW_KEY',
          'auth_header': 'Authorization',
          'models': {
            'm': {'max_output_tokens': 4096, 'context_window': 8192},
          },
        }, 'providers.p'),
        {
          'api_key_secret': 'codelab/gw',
          'api_key_env': 'GW_KEY',
          'auth_header': 'Authorization',
          'models': {
            'm': {'max_output_tokens': 4096, 'context_window': 8192},
          },
        },
      );
    });

    test('пустое значение секретного имени не маскируется', () {
      expect(mask({'api_key': ''}, 'providers.p'), {'api_key': ''});
    });

    test('сам запрошенный ключ с секретным именем маскируется', () {
      expect(mask('sk-1', 'providers.p.api_key'), redacted);
    });
  });

  group('непрозрачные поддеревья → <opaque: edit the file>', () {
    test('providers.*.auth и providers.*.key_rotation', () {
      expect(
        mask({
          'auth': {'client_secret': 's-1'},
          'key_rotation': {
            'keys': ['k-1'],
          },
          'kind': 'openai-compatible',
        }, 'providers.p'),
        {'auth': opaque, 'key_rotation': opaque, 'kind': 'openai-compatible'},
      );
    });

    test('запрошенный ключ сам непрозрачен', () {
      expect(mask({'client_secret': 's-1'}, 'providers.p.auth'), opaque);
    });

    test('раздел после MVP целиком', () {
      expect(
        mask({
          'enabled': {'x': 'v'},
        }, 'skills'),
        opaque,
      );
    });

    test('узел без схемы листьев', () {
      expect(
        mask({
          'mystery': {'x': 'v'},
          'kind': 'openai-compatible',
        }, 'providers.p'),
        {'mystery': opaque, 'kind': 'openai-compatible'},
      );
    });
  });

  group('значение не из файла → имя источника', () {
    test('слой окружения: переменная по ключу', () {
      const env = ConfigTree(
        kind: ConfigLayerKind.environment,
        source: 'env',
        values: {},
      );

      expect(
        maskConfigValue('p/m', key: 'agent.default_model', layer: env),
        '<from env:CODELAB_MODEL>',
      );
      expect(
        maskConfigValue(5, key: 'budget.max_steps', layer: env),
        '<from env:CODELAB_MAX_STEPS>',
      );
      expect(
        maskConfigValue('standard', key: 'permissions.mode', layer: env),
        '<from env:CODELAB_PERMISSION_MODE>',
      );
    });

    test('таблица переменных одна у слоя окружения и у маскирования: каждая '
        'переменная слоя даёт <from env:NAME> (ревью итерации 4, arch L4)', () {
      const env = ConfigTree(
        kind: ConfigLayerKind.environment,
        source: 'env',
        values: {},
      );

      expect(environmentLayerVariables, isNotEmpty);
      for (final MapEntry(:key, :value) in environmentLayerVariables.entries) {
        final built = buildEnvironmentLayer({value: '5'}).layer;
        final snapshot = ConfigSnapshot(
          target: const ConfigTarget.user(),
          path: 'env',
          fingerprint: null,
          values: built?.values ?? const {},
        );

        expect(snapshot.get(key), isNotNull, reason: '$value -> $key');
        expect(
          maskConfigValue('5', key: key, layer: env),
          '<from env:$value>',
          reason: key,
        );
      }
    });

    test('родительский ключ слоя окружения: листья поэлементно', () {
      const env = ConfigTree(
        kind: ConfigLayerKind.environment,
        source: 'env',
        values: {},
      );

      expect(
        maskConfigValue(
          {'level': 'debug', 'file': '/tmp/x.log'},
          key: 'logging',
          layer: env,
        ),
        {
          'level': '<from env:CODELAB_LOG_LEVEL>',
          'file': '<from env:CODELAB_LOG_FILE>',
        },
      );
    });

    test('предконфигурация провайдера: имя из источника слоя', () {
      const preconfig = ConfigTree(
        kind: ConfigLayerKind.environment,
        source: 'env:CODELAB_PROVIDER_CONFIG',
        values: {},
      );

      expect(
        maskConfigValue(
          {'kind': 'openai-compatible', 'base_url': 'https://u:pw@h/v1'},
          key: 'providers.env',
          layer: preconfig,
        ),
        {
          'kind': '<from env:CODELAB_PROVIDER_CONFIG>',
          'base_url': '<from env:CODELAB_PROVIDER_CONFIG>',
        },
      );
    });

    test('слой флагов', () {
      const flags = ConfigTree(
        kind: ConfigLayerKind.flags,
        source: 'flags',
        values: {},
      );

      expect(
        maskConfigValue('p/m', key: 'agent.default_model', layer: flags),
        '<from flags>',
      );
    });

    test('слой файла источник не подставляет', () {
      const file = ConfigTree(
        kind: ConfigLayerKind.user,
        source: '/h/config.yaml',
        values: {},
      );

      expect(
        maskConfigValue('p/m', key: 'agent.default_model', layer: file),
        'p/m',
      );
    });
  });

  group('URL без userinfo', () {
    test('base_url и url', () {
      expect(mask({'base_url': 'https://u:pw@h/v1'}, 'providers.p'), {
        'base_url': 'https://h/v1',
      });
      expect(
        mask([
          {'name': 's', 'type': 'http', 'url': 'https://tok@h/mcp'},
        ], 'mcp.servers'),
        [
          {'name': 's', 'type': 'http', 'url': 'https://h/mcp'},
        ],
      );
      expect(mask('https://u:pw@h/v1', 'providers.p.base_url'), 'https://h/v1');
    });

    test('userinfo с @ и спецсимволами удаляется целиком (R4-5)', () {
      expect(
        mask('https://us%40er:p%40ss@h:8443/v1?x=1#f', 'providers.p.base_url'),
        'https://h:8443/v1?x=1#f',
      );
      // Авторитет с несколькими @ не разбирается однозначно: fail closed.
      expect(mask('https://a:b@c@d.test/v1', 'providers.p.base_url'), redacted);
      expect(
        mask(r'https://${U}:${P}@h.test/v1', 'providers.p.base_url'),
        'https://h.test/v1',
      );
    });

    test('неразбираемый URL → <redacted>', () {
      expect(mask('https://[::1/v1', 'providers.p.base_url'), redacted);
      expect(mask('https://h:port/v1', 'providers.p.base_url'), redacted);
    });

    test('значения query-параметров с секретными именами → <redacted>, '
        'ссылки и обычные параметры остаются (R4-5)', () {
      expect(
        mask(
          'https://h.test/v1?api_key=sk-1&X-Token=t2&model=m&key=\${K}',
          'providers.p.base_url',
        ),
        'https://h.test/v1?api_key=<redacted>&X-Token=<redacted>&model=m'
        r'&key=${K}',
      );
      expect(
        mask([
          {'name': 's', 'type': 'http', 'url': 'https://h/mcp?access_token=ab'},
        ], 'mcp.servers'),
        [
          {
            'name': 's',
            'type': 'http',
            'url': 'https://h/mcp?access_token=<redacted>',
          },
        ],
      );
    });

    test('@ без авторитета (схема не распознана) → <redacted> (R4-5)', () {
      for (final raw in [
        'user:pass@host:8080/v1',
        'u:p@h',
        'https:u:p@h/',
        'proxyuser:FAKEPASS@proxy.example:8080/v1',
      ]) {
        expect(mask(raw, 'providers.p.base_url'), redacted, reason: raw);
      }
    });

    test('фрагмент и matrix-параметры маскируются как query (R4-5)', () {
      expect(
        mask('https://h/v1#token=FAKE', 'providers.p.base_url'),
        'https://h/v1#token=<redacted>',
      );
      expect(
        mask('https://h/v1#a=1&api_key=FAKE', 'providers.p.base_url'),
        'https://h/v1#a=1&api_key=<redacted>',
      );
      expect(
        mask('https://h/v1;token=FAKE/x;m=1', 'providers.p.base_url'),
        'https://h/v1;token=<redacted>/x;m=1',
      );
    });

    test('литерал, похожий на токен-заменитель, не считается ссылкой', () {
      expect(
        mask('https://h/v1?token=sk-refx0x-abc', 'providers.p.base_url'),
        'https://h/v1?token=<redacted>',
      );
    });

    test('адрес без userinfo и не-URL остаются как есть', () {
      expect(
        mask('http://localhost:1/v1', 'providers.p.base_url'),
        'http://localhost:1/v1',
      );
      expect(mask(r'${LLM_URL}', 'providers.p.base_url'), r'${LLM_URL}');
    });
  });

  group('отображения и списки поэлементно', () {
    test('соседний сервер и скаляры не затрагиваются', () {
      final result = mask([
        {
          'name': 'a',
          'type': 'stdio',
          'command': 'npx',
          'args': ['-y', 'pkg'],
          'env': {'API_TOKEN': 'lit'},
        },
        {'name': 'b', 'type': 'http', 'url': 'https://h'},
      ], 'mcp.servers');

      expect(result, [
        {
          'name': 'a',
          'type': 'stdio',
          'command': 'npx',
          'args': ['-y', 'pkg'],
          'env': {'API_TOKEN': redacted},
        },
        {'name': 'b', 'type': 'http', 'url': 'https://h'},
      ]);
    });
  });

  group('render', () {
    test('скаляр — одна строка, структура — JSON построчно', () {
      expect(renderConfigValue('p/m'), ['p/m']);
      expect(renderConfigValue(40), ['40']);
      expect(renderConfigValue(true), ['true']);
      expect(renderConfigValue({'a': 1}), ['{', '  "a": 1', '}']);
    });
  });

  group('подкоманды печатают замаскированное', () {
    late Directory root;
    late String home;
    late String cwd;

    setUp(() {
      root = Directory(
        Directory.systemTemp
            .createTempSync('config_output')
            .resolveSymbolicLinksSync(),
      );
      home = '${root.path}/home';
      cwd = '${root.path}/proj';
      Directory(home).createSync();
      Directory(cwd).createSync();
      Process.runSync('/bin/chmod', ['700', home]);
      File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    api_key: sk-1
    base_url: https://u:pw@h/v1
    models:
      m: {}
    auth:
      client_secret: s-1
    key_rotation:
      keys: [k-1]
mcp:
  servers:
    - name: gh
      type: http
      url: https://h
      headers:
        Authorization: "Bearer lit"
      env:
        GITHUB_TOKEN: "\${GH}"
''');
    });

    tearDown(() => root.deleteSync(recursive: true));

    Future<ConfigCommandResult> get(
      String key, {
      ConfigGetLayer layer = ConfigGetLayer.merged,
      Map<String, String> extra = const {},
    }) => ConfigCommands(processRunner: FakeSecretProcessRunner()).get(
      ConfigGetOptions(
        key: key,
        cwd: cwd,
        environment: {'CODELAB_HOME': home, ...extra},
        layer: layer,
      ),
    );

    test('сценарий «get маскирует секреты»', () async {
      final provider = await get('providers.p');
      final servers = await get('mcp.servers');
      final model = await get(
        'agent.default_model',
        extra: {'CODELAB_MODEL': 'p/m'},
      );

      final out = [
        ...provider.stdout,
        ...servers.stdout,
        ...model.stdout,
      ].join('\n');
      expect(provider.exitCode, 0, reason: provider.stderr.join('\n'));
      expect(servers.exitCode, 0, reason: servers.stderr.join('\n'));
      expect(model.exitCode, 0, reason: model.stderr.join('\n'));
      expect(out, contains(redacted));
      expect(out, contains('https://h/v1'));
      expect(out, contains(r'${GH}'));
      expect(out, contains('<from env:CODELAB_MODEL>'));
      expect(model.stdout.last, 'layer: env');
      for (final secret in ['sk-1', 'pw', 'Bearer lit', 'u:pw']) {
        expect(out, isNot(contains(secret)), reason: secret);
      }
    });

    test('сценарий «Непрозрачные поддеревья»', () async {
      final result = await get('providers.p');

      final out = result.stdout.join('\n');
      expect(out, contains(opaque));
      expect(result.stdout.any((l) => l.contains('"auth": "$opaque"')), isTrue);
      expect(
        result.stdout.any((l) => l.contains('"key_rotation": "$opaque"')),
        isTrue,
      );
      expect(out, isNot(contains('s-1')));
      expect(out, isNot(contains('k-1')));
    });

    test('--layer user маскирует так же, как merged', () async {
      final result = await get('providers.p', layer: ConfigGetLayer.user);

      final out = result.stdout.join('\n');
      expect(out, contains(redacted));
      expect(out, isNot(contains('sk-1')));
      expect(out, isNot(contains('u:pw')));
    });

    test('provider list: адрес без userinfo', () async {
      File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://u:pw@h/v1
    models:
      m: {}
agent:
  default_model: p/m
''');

      final result =
          await ProviderCommands(
            processRunner: FakeSecretProcessRunner(),
            openStore:
                ({required choice, required environment, required home}) =>
                    MemorySecretStore(),
          ).list(
            ProviderListOptions(cwd: cwd, environment: {'CODELAB_HOME': home}),
          );

      final out = result.stdout.join('\n');
      expect(result.exitCode, 0, reason: result.stderr.join('\n'));
      expect(out, contains('https://h/v1'));
      expect(out, isNot(contains('pw')));
    });

    test('provider list: адрес из предконфигурации — имя источника', () async {
      File('$home/config.yaml').writeAsStringSync('');

      final result =
          await ProviderCommands(
            processRunner: FakeSecretProcessRunner(),
            openStore:
                ({required choice, required environment, required home}) =>
                    MemorySecretStore(),
          ).list(
            ProviderListOptions(
              cwd: cwd,
              environment: {
                'CODELAB_HOME': home,
                'CODELAB_PROVIDER_TYPE': 'openai-compatible',
                'CODELAB_PROVIDER_CONFIG':
                    '{"id":"env","base_url":"https://u:pw@e.test/v1",'
                    '"model":"m","context_window":4096}',
              },
            ),
          );

      final out = result.stdout.join('\n');
      expect(result.exitCode, 0, reason: result.stderr.join('\n'));
      expect(out, contains('<from env:CODELAB_PROVIDER_CONFIG>'));
      expect(out, isNot(contains('e.test')));
      expect(out, isNot(contains('pw')));
    });
  });
}
