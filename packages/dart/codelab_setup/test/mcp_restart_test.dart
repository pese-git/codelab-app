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
/// Ожидаемый API (задача 6.1b-1 → реализация): `List<String>
/// restartRequiredServers(AgentConfigSnapshot before, AgentConfigSnapshot
/// after)` в `lib/src/mcp/mcp_restart.dart`, экспорт основного бареля.
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

      expect(restartRequiredServers(before, after), isEmpty);
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
}
