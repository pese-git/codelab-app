import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import 'support/mcp_snapshots.dart';

/// `restartRequiredServers(before, after)` (change `add-provider-setup-ui`,
/// D11 «Итерация 6: сервер, отложенный до перезапуска», решение Q31 (а);
/// app-settings «Новый stdio-сервер ждёт перезапуска»; задача 6.1b-1).
///
/// Почему мост, а не Cubit: признак «сервер начнёт работать только после
/// Restart agent» даёт одно правило ядра — `planConfigReload` (правило 3:
/// R0-1, R0-4, R6-1). Мост лишь берёт из плана имена серверов; копии правила
/// (`stdio`, подстановки в `http`, `sameConnection`) в нём быть не должно, и
/// тесты проверяют поведение правила ядра на настоящих файлах.
///
/// Снимки — настоящий `FileAgentConfigStore` во временном `CODELAB_HOME`;
/// секреты — только имена, значений нет.
///
/// API: `restartRequiredServers(before, after)` → `List<String>` в
/// `lib/src/mcp/mcp_restart.dart`, экспорт основного бареля.
void main() {
  late Directory root;
  late String home;
  late String project;
  late FileAgentConfigStore store;

  const provider = '''
agent:
  default_model: p/m
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m:
        context_window: 32000
''';

  String stdio(
    String name, {
    String args = '[]',
    bool? enabled,
    String extra = '',
  }) =>
      '    - name: $name\n'
      '      type: stdio\n'
      '      command: /usr/bin/server\n'
      '      args: $args\n'
      '${enabled == null ? '' : '      enabled: $enabled\n'}'
      '$extra';

  String http(String name, {String headers = ''}) =>
      '    - name: $name\n'
      '      type: http\n'
      '      url: https://mcp.test/mcp\n'
      '$headers';

  /// Записывает `config.yaml` пользователя: провайдер и список серверов.
  Future<AgentConfigSnapshot> snapshotOf(List<String> servers) async {
    File('$home/config.yaml').writeAsStringSync(
      '$provider'
      '${servers.isEmpty ? '' : 'mcp:\n  servers:\n${servers.join()}'}',
    );
    return store.snapshot(cwd: project);
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('mcp_restart_test');
    home = '${root.path}/home';
    project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    final environment = {'HOME': root.path, 'CODELAB_HOME': home};
    final logger = RecordingLogger();
    store = FileAgentConfigStore(
      paths: ConfigPaths(codelabHome: home, projectDir: project),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: logger,
      ),
      logger: logger,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('сервер, отложенный до перезапуска (правило 3 ядра)', () {
    test('новый stdio-сервер: в списке', () async {
      final before = await snapshotOf([]);
      final after = await snapshotOf([stdio('fs')]);

      expect(restartRequiredServers(before, after), ['fs']);
    });

    test('enabled false → true: в списке', () async {
      final before = await snapshotOf([stdio('fs', enabled: false)]);
      final after = await snapshotOf([stdio('fs', enabled: true)]);

      expect(restartRequiredServers(before, after), ['fs']);
    });

    test('новый http с секретом в заголовке (R0-4): в списке', () async {
      final before = await snapshotOf([]);
      final after = await snapshotOf([
        http(
          'github',
          headers:
              '      headers:\n'
              '        Authorization: "\${secret:codelab/mcp/github/authorization}"\n',
        ),
      ]);

      expect(restartRequiredServers(before, after), ['github']);
    });

    test('новый http без подстановок: пусто', () async {
      final before = await snapshotOf([]);
      final after = await snapshotOf([http('plain')]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('правка args включённого stdio (sameConnection): в списке', () async {
      final before = await snapshotOf([stdio('fs', args: '[a]')]);
      final after = await snapshotOf([stdio('fs', args: '[b]')]);

      expect(restartRequiredServers(before, after), ['fs']);
    });

    test('правка call_timeout у включённого сервера: пусто', () async {
      final before = await snapshotOf([stdio('fs')]);
      final after = await snapshotOf([
        stdio('fs', extra: '      call_timeout: 90s\n'),
      ]);
      // Без этого пустой ответ мог бы означать отклонённый конфиг.
      expect(after.loaded.config, isNotNull, reason: '${after.loaded.issues}');

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('правка args выключенного сервера (R6-1 откладывает её в ядре): '
        'сервер не назван, он не запустится', () async {
      final before = await snapshotOf([
        stdio('fs', args: '[a]', enabled: false),
      ]);
      final after = await snapshotOf([
        stdio('fs', args: '[b]', enabled: false),
      ]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('выключение вместе со сменой args: пусто', () async {
      final before = await snapshotOf([stdio('fs', args: '[a]')]);
      final after = await snapshotOf([
        stdio('fs', args: '[b]', enabled: false),
      ]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('имя с символами, ломающими разбор ключа показа (".", "]", "[", '
        'кавычка): сервер назван (имена берутся из plan.deferred.servers, а не '
        'из restartRequiredKeys)', () async {
      for (final name in ['my.srv', 'a]b', 'a[b', 'a"b']) {
        final before = await snapshotOf([]);
        final after = await snapshotOf([
          stdio('"${name.replaceAll('"', r'\"')}"'),
        ]);
        expect(
          after.loaded.config,
          isNotNull,
          reason: '$name: ${after.loaded.issues}',
        );

        expect(restartRequiredServers(before, after), [name], reason: name);
      }
    });

    test('удаление сервера: пусто', () async {
      final before = await snapshotOf([stdio('fs')]);
      final after = await snapshotOf([]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('выключение сервера true → false: пусто', () async {
      final before = await snapshotOf([stdio('fs')]);
      final after = await snapshotOf([stdio('fs', enabled: false)]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('без изменений: пусто', () async {
      final before = await snapshotOf([stdio('fs')]);
      final after = await snapshotOf([stdio('fs')]);

      expect(restartRequiredServers(before, after), isEmpty);
    });

    test('несколько серверов: только затронутые, по порядку конфига', () async {
      final before = await snapshotOf([stdio('a'), http('web')]);
      final after = await snapshotOf([
        stdio('a'),
        http('web'),
        stdio('b'),
        stdio('c'),
      ]);

      expect(restartRequiredServers(before, after), ['b', 'c']);
    });
  });

  group('нет применённого конфига', () {
    test('у любого снимка нет loaded.config: пусто', () async {
      final good = await snapshotOf([stdio('fs')]);
      // Снимок на фейковых слоях несёт пустой `ConfigLoadResult` без `config`.
      final noConfig = mcpSnapshot(user: [stdioServer('other')]);
      expect(noConfig.loaded.config, isNull);

      expect(restartRequiredServers(noConfig, good), isEmpty);
      expect(restartRequiredServers(good, noConfig), isEmpty);
      expect(restartRequiredServers(noConfig, noConfig), isEmpty);
    });
  });

  group('restartRequiredProviders (Q35): провайдер ждёт перезапуска', () {
    // Те же правила ядра (`planConfigReload`, R0-4): провайдер «с ключом»
    // (`api_key_secret`, `api_key_env`, `${…}` в адресе и заголовках)
    // откладывается целиком, если он новый или сменилась группа адреса и
    // аутентификации; модели существующего провайдера применяются сразу.
    const base = '''
agent:
  default_model: p/m
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m:
        context_window: 32000
''';

    String provider(
      String id, {
      String baseUrl = 'https://q.test/v1',
      String key = '',
      String models = '      m2:\n        context_window: 32000\n',
    }) =>
        '  $id:\n'
        '    kind: openai-compatible\n'
        '    base_url: $baseUrl\n'
        '$key'
        '    models:\n'
        '$models';

    Future<AgentConfigSnapshot> configOf(String text) async {
      File('$home/config.yaml').writeAsStringSync(text);
      return store.snapshot(cwd: project);
    }

    const secretKey = '    api_key_secret: codelab/q\n';

    test('новый провайдер с api_key_secret: в списке (R0-4)', () async {
      final before = await configOf(base);
      final after = await configOf('$base${provider('q', key: secretKey)}');
      expect(after.loaded.config, isNotNull, reason: '${after.loaded.issues}');

      expect(restartRequiredProviders(before, after), ['q']);
    });

    test('новый провайдер с api_key_env: в списке', () async {
      final before = await configOf(base);
      final after = await configOf(
        '$base${provider('q', key: '    api_key_env: Q_KEY\n')}',
      );
      expect(after.loaded.config, isNotNull, reason: '${after.loaded.issues}');

      expect(restartRequiredProviders(before, after), ['q']);
    });

    test('новый провайдер без ключа: пусто (правило ядра)', () async {
      final before = await configOf(base);
      final after = await configOf('$base${provider('q')}');
      expect(after.loaded.config, isNotNull, reason: '${after.loaded.issues}');

      expect(restartRequiredProviders(before, after), isEmpty);
    });

    test('правка моделей существующего провайдера с прежним ключом: пусто '
        '(применяется сразу)', () async {
      final before = await configOf('$base${provider('q', key: secretKey)}');
      final after = await configOf(
        '$base${provider('q', key: secretKey, models: '      m2:\n'
            '        context_window: 32000\n      m3:\n'
            '        context_window: 32000\n')}',
      );
      expect(after.loaded.config, isNotNull, reason: '${after.loaded.issues}');

      expect(restartRequiredProviders(before, after), isEmpty);
    });

    test('смена base_url существующего провайдера с ключом: в списке', () async {
      final before = await configOf('$base${provider('q', key: secretKey)}');
      final after = await configOf(
        '$base${provider('q', baseUrl: 'https://other.test/v1', key: secretKey)}',
      );

      expect(restartRequiredProviders(before, after), ['q']);
    });

    test('смена ключа существующего провайдера: в списке', () async {
      final before = await configOf('$base${provider('q', key: secretKey)}');
      final after = await configOf(
        '$base${provider('q', key: '    api_key_secret: codelab/other\n')}',
      );

      expect(restartRequiredProviders(before, after), ['q']);
    });

    test('смена base_url существующего провайдера без ключа: пусто '
        '(правило ядра)', () async {
      final before = await configOf('$base${provider('q')}');
      final after = await configOf(
        '$base${provider('q', baseUrl: 'https://other.test/v1')}',
      );

      expect(restartRequiredProviders(before, after), isEmpty);
    });

    test('порядок как в конфиге after', () async {
      final before = await configOf(base);
      final after = await configOf(
        '$base${provider('z', key: secretKey)}${provider('a', key: secretKey)}',
      );

      expect(restartRequiredProviders(before, after), ['z', 'a']);
    });

    test('у снимка нет loaded.config: пусто', () async {
      final good = await configOf(base);
      final noConfig = mcpSnapshot(user: [stdioServer('other')]);

      expect(restartRequiredProviders(noConfig, good), isEmpty);
      expect(restartRequiredProviders(good, noConfig), isEmpty);
    });
  });
}
