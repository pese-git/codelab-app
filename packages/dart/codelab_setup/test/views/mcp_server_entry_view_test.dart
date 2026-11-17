import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/mcp_snapshots.dart';
import '../support/real_home.dart';

/// Строка страницы «MCP servers» (client-agent-setup «Модели представления
/// настроек»; design.md change `add-provider-setup-ui`, D11 «Сверка с
/// кодом», D17; R0-2, SETUP-1): вид строится по элементу слоя-источника, а не
/// по итоговому списку; `args`, `env` и `headers` проходят правило ядра
/// `displaySafeConfigValue`, URL — `maskUrl`; признак `masked` — у моста.
///
/// Ожидаемый API (задача 5.8): `mcpServerEntriesOf(AgentConfigSnapshot)`,
/// `McpServerEntryView`, `mcpServerElementOf(snapshot, name)`.
void main() {
  const leak = 'sk-test-leak-0123456789';

  McpServerEntryView entry(List<McpServerEntryView> list, String name) =>
      list.singleWhere((e) => e.name == name, orElse: () => fail('нет $name'));

  group('состав и порядок', () {
    test('без серверов список пуст', () {
      expect(mcpServerEntriesOf(mcpSnapshot()), isEmpty);
    });

    test('порядок слияния слоёв: серверы user, затем новые из проектных; '
        'сервер с тем же именем заменяется на месте', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          user: [httpServer('a'), httpServer('b')],
          projectLocal: [
            httpServer('c'),
            httpServer('a', url: 'https://a2/m'),
          ],
        ),
      );

      expect([for (final e in list) e.name], ['a', 'b', 'c']);
      expect(entry(list, 'a').url, 'https://a2/m');
      expect(entry(list, 'a').source.kind, ConfigSourceKind.projectLocal);
    });

    test('вид: тип, цель, включён ли, редактируемость по источнику', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          user: [
            stdioServer('s', command: 'npx', args: ['-y', 'srv']),
            httpServer('h', extra: {'enabled': false}),
          ],
        ),
      );

      final s = entry(list, 's');
      expect(s.kind, McpTransportKind.stdio);
      expect(s.command, 'npx');
      expect(s.args, ['-y', 'srv']);
      expect(s.target, 'npx -y srv');
      expect(s.enabled, isTrue);
      expect(s.source.kind, ConfigSourceKind.user);
      expect(s.editable, isTrue);
      expect(s.disabledHere, isFalse);
      final h = entry(list, 'h');
      expect(h.kind, McpTransportKind.http);
      expect(h.target, 'https://mcp.test/mcp');
      expect(h.enabled, isFalse);
    });
  });

  group('слои проекта', () {
    test('сервер слоя 3 доверенного проекта — только чтение', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(project: [stdioServer('playwright')]),
      );

      final p = entry(list, 'playwright');
      expect(p.source.kind, ConfigSourceKind.project);
      expect(p.editable, isFalse);
      expect(p.disabledHere, isFalse);
    });

    test('слой 3 недоверенного проекта в список не попадает (CFG-3)', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          user: [httpServer('mine')],
          project: [stdioServer('evil')],
          untrustedProject: true,
        ),
      );

      expect([for (final e in list) e.name], ['mine']);
    });

    test(
      '«Disable here»: переопределение {name, enabled: false} в '
      'projectLocal — строка по проектному элементу с disabledHere (Q21)',
      () {
        final list = mcpServerEntriesOf(
          mcpSnapshot(
            project: [stdioServer('playwright', command: 'pw')],
            projectLocal: [
              {'name': 'playwright', 'enabled': false},
            ],
          ),
        );

        final p = entry(list, 'playwright');
        expect(p.command, 'pw', reason: 'цель — из проектного файла');
        expect(p.enabled, isFalse);
        expect(p.disabledHere, isTrue);
        expect(p.source.kind, ConfigSourceKind.project);
        expect(p.editable, isFalse);
      },
    );

    test('полный элемент в projectLocal — обычное переопределение, а не '
        '«disabled here»', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          project: [stdioServer('playwright')],
          projectLocal: [stdioServer('playwright', command: 'mine')],
        ),
      );

      final p = entry(list, 'playwright');
      expect(p.command, 'mine');
      expect(p.disabledHere, isFalse);
      expect(p.editable, isTrue);
      expect(p.source.kind, ConfigSourceKind.projectLocal);
    });

    test('настоящий загрузчик: недоверенный проект скрыт, доверенный '
        'показан', () async {
      final home = RealHome.create('mcp_entry_');
      addTearDown(home.dispose);
      Directory('${home.project}/.codelab').createSync(recursive: true);
      File('${home.project}/.codelab/config.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: p1
      type: http
      url: https://x.test/mcp
''');
      home.writeConfig('agent:\n  default_model: gw/m\n$gatewayProvider');
      expect(mcpServerEntriesOf(await home.load()), isEmpty);

      home.writeConfig(
        'trusted_projects:\n  - ${home.project}\n'
        'agent:\n  default_model: gw/m\n$gatewayProvider',
      );
      final list = mcpServerEntriesOf(await home.load());
      expect([for (final e in list) e.name], ['p1']);
      expect(list.single.source.kind, ConfigSourceKind.project);
    });
  });

  group('порядок слияния', () {
    test('порядок строк совпадает с итоговым списком загрузчика ядра '
        '(merge.dart): первое появление, замена на месте', () async {
      final home = RealHome.create('mcp_order_');
      addTearDown(home.dispose);
      String servers(List<String> names) => [
        'mcp:',
        '  servers:',
        for (final n in names) ...[
          '    - name: $n',
          '      type: http',
          '      url: https://$n.test/mcp',
        ],
      ].join('\n');
      home.writeConfig(
        'trusted_projects:\n  - ${home.project}\n'
        'agent:\n  default_model: gw/m\n$gatewayProvider'
        '${servers(['a', 'b', 'c'])}\n',
      );
      Directory('${home.project}/.codelab').createSync(recursive: true);
      File(
        '${home.project}/.codelab/config.yaml',
      ).writeAsStringSync(servers(['d', 'b']));
      File(
        '${home.project}/.codelab/config.local.yaml',
      ).writeAsStringSync(servers(['e', 'a', 'd']));

      final snapshot = await home.load();

      // Итог загрузчика плоский: `mcp.servers[<name>].<поле>` в порядке
      // итогового списка.
      final merged = <String>[];
      for (final key in snapshot.loaded.values.keys) {
        final match = RegExp(r'^mcp\.servers\[([^\]]+)\]').firstMatch(key);
        if (match != null && !merged.contains(match.group(1))) {
          merged.add(match.group(1)!);
        }
      }
      expect(merged, ['a', 'b', 'c', 'd', 'e']);
      expect([for (final e in mcpServerEntriesOf(snapshot)) e.name], merged);
    });
  });

  group('маскирование значений (R0-2, SETUP-1)', () {
    test('литерал в заголовке скрыт и помечен masked; ссылки и обычные '
        'значения — как есть', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          user: [
            httpServer(
              'gh',
              headers: {
                'Authorization': 'Bearer $leak',
                'X-Ref': r'${secret:codelab/mcp/gh/x-ref}',
                'X-Team': 'core',
              },
            ),
          ],
        ),
      );

      final e = entry(list, 'gh');
      expect(e.headers['Authorization'], '<redacted>');
      expect(e.headers['X-Ref'], r'${secret:codelab/mcp/gh/x-ref}');
      expect(
        e.headers['X-Team'],
        '<redacted>',
        reason: 'значение заголовка — только чистая ссылка \${…}',
      );
      expect(e.masked, isTrue);
      expect('${e.headers} ${e.target} $e', isNot(contains(leak)));
    });

    test('без литералов masked = false', () {
      final list = mcpServerEntriesOf(
        mcpSnapshot(
          user: [
            httpServer(
              'gh',
              headers: {
                'X-Ref': r'${secret:codelab/mcp/gh/x-ref}',
                'X-Env': r'${TEAM}',
              },
            ),
            stdioServer('s', env: {'LOG_LEVEL': 'debug'}),
          ],
        ),
      );

      expect(entry(list, 'gh').masked, isFalse);
      expect(entry(list, 's').masked, isFalse);
    });

    test('заголовок с токеном под нейтральным именем (X-Workspace) скрыт: '
        'значение headers показывается только если это чистая ссылка', () {
      final e = entry(
        mcpServerEntriesOf(
          mcpSnapshot(
            user: [
              httpServer(
                'gh',
                headers: {
                  'X-Workspace': 'ws-4f9a8c2d71b3e605',
                  'X-Mixed': r'Bearer ${secret:codelab/mcp/gh/x-mixed}',
                  'X-Plain': r'${secret:codelab/mcp/gh/x-plain}',
                },
              ),
            ],
          ),
        ),
        'gh',
      );

      expect(e.headers['X-Workspace'], '<redacted>');
      expect(e.headers['X-Mixed'], '<redacted>');
      expect(e.headers['X-Plain'], r'${secret:codelab/mcp/gh/x-plain}');
      expect(e.masked, isTrue);
    });

    test(
      'env с секретным именем и без ссылки скрыт; со ссылкой — как есть',
      () {
        final e = entry(
          mcpServerEntriesOf(
            mcpSnapshot(
              user: [
                stdioServer(
                  's',
                  env: {
                    'GITHUB_TOKEN': 'hunter2',
                    'API_KEY': r'${secret:codelab/mcp/s/api_key}',
                    'LOG_LEVEL': 'debug',
                  },
                ),
              ],
            ),
          ),
          's',
        );

        expect(e.env['GITHUB_TOKEN'], '<redacted>');
        expect(e.env['API_KEY'], r'${secret:codelab/mcp/s/api_key}');
        expect(e.env['LOG_LEVEL'], 'debug');
        expect(e.masked, isTrue);
      },
    );

    test('URL: userinfo и секретный параметр query скрыты maskUrl, цель '
        'целиком не цитирует маркер', () {
      final e = entry(
        mcpServerEntriesOf(
          mcpSnapshot(
            user: [
              httpServer(
                'h',
                url: 'https://u:$leak@h.test/mcp?token=$leak&x=1',
              ),
            ],
          ),
        ),
        'h',
      );

      expect(e.url, 'https://h.test/mcp?token=<redacted>&x=1');
      expect(e.target, e.url);
      expect(e.masked, isTrue);
      expect('$e', isNot(contains(leak)));
    });

    test('args: литерал по шаблону секрета скрыт', () {
      final e = entry(
        mcpServerEntriesOf(
          mcpSnapshot(
            user: [
              stdioServer('s', args: ['--url', 'x', '--key=$leak']),
            ],
          ),
        ),
        's',
      );

      expect(e.args.join(' '), isNot(contains(leak)));
      expect(e.target, isNot(contains(leak)));
      expect(e.masked, isTrue);
    });

    test('args: значение после секретного флага (--token hunter2) скрыто как '
        'в config get (R4-6)', () {
      // Правило пар «флаг значение» живёт в `codelab_agent_io`
      // (`_maskArgs`); `displaySafeConfigValue` его не знает. Реализации
      // 5.8 придётся вынести его в ядро и звать из обоих мест — см. отчёт.
      final e = entry(
        mcpServerEntriesOf(
          mcpSnapshot(
            user: [
              stdioServer('s', args: ['--token', 'hunter2', '--verbose']),
            ],
          ),
        ),
        's',
      );

      expect(e.args, ['--token', '<redacted>', '--verbose']);
      expect(e.masked, isTrue);
    });
  });

  group('сырой элемент слоя для правки', () {
    test('mcpServerElementOf отдаёт элемент слоя-источника как в файле, со '
        'ссылками', () {
      final raw = httpServer(
        'gh',
        headers: {'Authorization': r'${secret:codelab/mcp/gh/authorization}'},
        extra: {'call_timeout': '30s'},
      );
      final found = mcpServerElementOf(mcpSnapshot(user: [raw]), 'gh');

      expect(found, isNotNull);
      expect(found!.layer, ConfigLayer.user);
      expect(found.element, raw);
    });

    test('неизвестное имя и недоверенный проект — null', () {
      expect(mcpServerElementOf(mcpSnapshot(), 'x'), isNull);
      expect(
        mcpServerElementOf(
          mcpSnapshot(project: [stdioServer('x')], untrustedProject: true),
          'x',
        ),
        isNull,
      );
    });

    test('при переопределении побеждает слой с наибольшим приоритетом', () {
      final found = mcpServerElementOf(
        mcpSnapshot(
          user: [stdioServer('s', command: 'u')],
          projectLocal: [stdioServer('s', command: 'l')],
        ),
        's',
      );

      expect(found!.layer, ConfigLayer.projectLocal);
      expect(found.element['command'], 'l');
    });
  });
}
