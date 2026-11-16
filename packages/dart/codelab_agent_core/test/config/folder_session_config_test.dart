import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Внутренняя функция подстановки: не публичный API (design.md change
// `defer-restart-keys-in-folder-sessions`, D2), тест импортирует `src/`.
import 'package:codelab_agent_core/src/config/folder_session_config.dart';
import 'package:test/test.dart';

import 'config_support.dart' show layer;
import '../support/project_config_rig.dart' show norm;

/// Подстановка отложенных до перезапуска частей в конфигурацию сессии другой
/// папки (agent-runtime «Сессии других папок при перезагрузке корня»,
/// «Отложенные правки в сессиях других папок»; design.md change
/// `defer-restart-keys-in-folder-sessions`, D1–D5, D9). Красные тесты
/// задачи 1.1.
void main() {
  const marker = 'sk-test-leak-0123456789';
  const environment = {'K1': 'value-1', 'K2': 'value-2'};
  const trusted = ['/A', '/B', '/C'];

  Map<String, Object?> openrouter({
    String env = 'K1',
    String baseUrl = 'https://or.test/v1',
    Map<String, Object?> models = const {'m': <String, Object?>{}},
  }) => {
    'kind': 'openai-compatible',
    'base_url': baseUrl,
    'api_key_env': env,
    'models': models,
  };

  Map<String, Object?> plain(String host) => {
    'kind': 'openai-compatible',
    'base_url': 'https://$host.test/v1',
    'models': {'m': <String, Object?>{}},
  };

  /// Глобальный слой: провайдер с ключом `openrouter` и без ключа `p`.
  Map<String, Object?> user({
    Map<String, Object?>? openrouterGroup,
    Map<String, Object?> providers = const {},
    List<Object?> servers = const [],
    Map<String, Object?>? permissions,
    String model = 'p/m',
  }) => norm({
    'providers': {
      'openrouter': openrouterGroup ?? openrouter(),
      'p': plain('p'),
      ...providers,
    },
    'agent': {'default_model': model},
    if (servers.isNotEmpty) 'mcp': {'servers': servers},
    'permissions': ?permissions,
  });

  /// Загрузка папки [root] настоящим `CoreConfig.fromLayers`: доверие и
  /// ограничения слоёв — как в продукте.
  ConfigLoadResult load(
    String root, {
    required Map<String, Object?> global,
    Map<String, Object?> project = const {},
    Map<String, Object?> local = const {},
    bool trustedFolder = true,
  }) {
    final result = CoreConfig.fromLayers(
      [
        layer(global),
        if (project.isNotEmpty)
          layer(
            norm(project),
            kind: ConfigLayerKind.project,
            source: '$root/.codelab/config.yaml',
          ),
        if (local.isNotEmpty)
          layer(
            norm(local),
            kind: ConfigLayerKind.projectLocal,
            source: '$root/.codelab/config.local.yaml',
          ),
      ],
      environment: environment,
      projectRoot: root,
      pinnedTrustedProjects: trustedFolder ? trusted : const ['/A'],
    );
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    return result;
  }

  FolderSessionConfig defer(ConfigLoadResult root, ConfigLoadResult folder) =>
      deferForFolderSession(
        applied: root.config!,
        appliedValues: root.values,
        folder: folder,
      );

  CoreConfig configOf(FolderSessionConfig result) =>
      (result as FolderSessionAccepted).config;

  List<String> keysOf(FolderSessionConfig result) =>
      (result as FolderSessionAccepted).restartKeys;

  ConfigIssue problemOf(FolderSessionConfig result) =>
      (result as FolderSessionRefused).problem;

  CatalogProvider providerOf(FolderSessionConfig result, String id) =>
      configOf(result).providers.singleWhere((p) => p.config.name == id);

  McpServerConfig serverOf(FolderSessionConfig result, String name) =>
      configOf(result).mcpServers.singleWhere((s) => s.name == name);

  const stdioA = {'name': 'x', 'type': 'stdio', 'command': 'run-a'};
  const stdioB = {'name': 'x', 'type': 'stdio', 'command': 'run-b'};

  group('providers (R0-4, D3)', () {
    test(
      'a global api_key_env change waits for the restart in another '
      'folder: the group of the base, the models of the folder (scenario '
      '"Глобальная смена api_key_env ждёт перезапуска и в другой папке")',
      () {
        final root = load('/A', global: user());
        final folder = load(
          '/B',
          global: user(
            openrouterGroup: openrouter(
              env: 'K2',
              models: {'m': <String, Object?>{}, 'm2': <String, Object?>{}},
            ),
          ),
        );

        final result = defer(root, folder);

        expect(result, isA<FolderSessionAccepted>());
        final provider = providerOf(result, 'openrouter');
        expect((provider.key! as EnvKeyRef).variable, 'K1');
        expect(provider.models.keys, containsAll(['m', 'm2']));
        expect(keysOf(result), ['providers.openrouter']);
        expect(configOf(result).projectRoot, '/B');
      },
    );

    test('a project provider of a trusted folder is not touched by a global '
        'edit of another provider (scenario "Проектный провайдер доверенной '
        'папки работает сразу")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(openrouterGroup: openrouter(env: 'K2')),
        local: {
          'providers': {
            'local': {
              'kind': 'openai-compatible',
              'base_url': 'https://local.test/v1',
              'api_key_secret': 'codelab/local',
              'models': {'m': <String, Object?>{}},
            },
          },
          'agent': {'default_model': 'local/m'},
        },
      );

      final result = defer(root, folder);

      final local = providerOf(result, 'local');
      expect(local.config.baseUrl, Uri.parse('https://local.test/v1'));
      expect((local.key! as SecretKeyRef).name, 'codelab/local');
      expect(configOf(result).defaultModel.provider, 'local');
      expect(
        (providerOf(result, 'openrouter').key! as EnvKeyRef).variable,
        'K1',
      );
      expect(keysOf(result), ['providers.openrouter']);
    });

    test('a project that overrides the changed fields of a global provider '
        'keeps its group (scenario "Проект перекрывает группу глобального '
        'провайдера")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(openrouterGroup: openrouter(env: 'K2')),
        local: {
          'providers': {
            'openrouter': {
              'base_url': 'https://mine.test/v1',
              'api_key_secret': 'codelab/mine',
            },
          },
        },
      );

      final result = defer(root, folder);

      final provider = providerOf(result, 'openrouter');
      expect(provider.config.baseUrl, Uri.parse('https://mine.test/v1'));
      expect((provider.key! as SecretKeyRef).name, 'codelab/mine');
      expect(keysOf(result), isEmpty);
    });

    test('a project that sets only the key of a provider whose global '
        'address changed gets the whole group of the base (scenario "Проект '
        'наследует изменённый адрес", D3)', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(
          openrouterGroup: openrouter(baseUrl: 'https://new-or.test/v1'),
        ),
        local: {
          'providers': {
            'openrouter': {'api_key_secret': 'codelab/mine'},
          },
        },
      );

      final result = defer(root, folder);

      final provider = providerOf(result, 'openrouter');
      expect(provider.config.baseUrl, Uri.parse('https://or.test/v1'));
      expect((provider.key! as EnvKeyRef).variable, 'K1');
      expect(keysOf(result), ['providers.openrouter']);
    });

    test('a new global provider with a key and the model default that '
        'points at it are excluded (scenario "Новый глобальный провайдер с '
        'ключом не появляется в другой папке")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(
          model: 'n/m',
          providers: {
            'n': {
              'kind': 'openai-compatible',
              'base_url': 'https://n.test/v1',
              'api_key_secret': 'codelab/n',
              'models': {'m': <String, Object?>{}},
            },
          },
        ),
      );

      final result = defer(root, folder);

      expect(result, isA<FolderSessionAccepted>());
      expect(configOf(result).providers.map((p) => p.config.name), [
        'openrouter',
        'p',
      ]);
      expect(configOf(result).defaultModel.provider, 'p');
      expect(configOf(result).validateSnapshot(), isEmpty);
      expect(keysOf(result), ['agent.default_model', 'providers.n']);
    });

    test('a new global provider without a key appears at once (scenario '
        '"Новый глобальный провайдер без ключа появляется сразу")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(providers: {'ollama': plain('ollama')}),
      );

      final result = defer(root, folder);

      expect(providerOf(result, 'ollama').models, contains('m'));
      expect(keysOf(result), isEmpty);
    });
  });

  group('servers (R0-1, R0-4, R6-1, D5)', () {
    test('a new global stdio server is absent, an HTTP server without '
        'substitutions stays (scenario "Новый глобальный stdio-сервер ждёт '
        'перезапуска в другой папке")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(
          servers: [
            stdioA,
            {'name': 'h', 'type': 'http', 'url': 'https://h.test/mcp'},
          ],
        ),
      );

      final result = defer(root, folder);

      expect(configOf(result).mcpServers.map((s) => s.name), ['h']);
      expect(keysOf(result), ['mcp.servers[x]']);
    });

    test('an HTTP server with a ${"\${secret:…}"} substitution: a new one is '
        'absent, a changed one is the element of the base', () {
      Map<String, Object?> http(String url) => {
        'name': 'h',
        'type': 'http',
        'url': url,
        'headers': {'Authorization': r'Bearer ${secret:codelab/mcp/h/token}'},
      };
      final root = load(
        '/A',
        global: user(servers: [http('https://h.test/mcp')]),
      );
      final folder = load(
        '/B',
        global: user(
          servers: [
            http('https://h2.test/mcp'),
            {
              'name': 'n',
              'type': 'http',
              'url': 'https://n.test/mcp',
              'headers': {'Authorization': r'Bearer ${secret:codelab/mcp/n/t}'},
            },
          ],
        ),
      );

      final result = defer(root, folder);

      expect(configOf(result).mcpServers.map((s) => s.name), ['h']);
      expect(
        (serverOf(result, 'h') as McpHttpServerConfig).url,
        Uri.parse('https://h.test/mcp'),
      );
      expect(keysOf(result), ['mcp.servers[h]', 'mcp.servers[n]']);
    });

    test('a changed command is the element of the base; disabling together '
        'with a command edit gives the base element with enabled: false', () {
      final root = load(
        '/A',
        global: user(
          servers: [
            stdioA,
            {'name': 'z', 'type': 'stdio', 'command': 'z-a'},
          ],
        ),
      );
      final folder = load(
        '/B',
        global: user(
          servers: [
            stdioB,
            {'name': 'z', 'type': 'stdio', 'command': 'z-b', 'enabled': false},
          ],
        ),
      );

      final result = defer(root, folder);

      final x = serverOf(result, 'x') as McpStdioServerConfig;
      expect(x.command, 'run-a');
      final z = serverOf(result, 'z') as McpStdioServerConfig;
      expect(z.command, 'z-a');
      expect(z.enabled, isFalse);
      expect(keysOf(result), ['mcp.servers[x]', 'mcp.servers[z]']);
    });

    test('a project that replaces the server by its own element keeps it '
        '(scenario "Проект перекрывает сервер своим элементом")', () {
      final root = load('/A', global: user(servers: [stdioA]));
      final folder = load(
        '/B',
        global: user(servers: [stdioB]),
        local: {
          'mcp': {
            'servers': [
              {'name': 'x', 'type': 'stdio', 'command': 'run-c'},
            ],
          },
        },
      );

      final result = defer(root, folder);

      expect((serverOf(result, 'x') as McpStdioServerConfig).command, 'run-c');
      expect(keysOf(result), isEmpty);
    });

    test('a project element equal to the new global one is not an override: '
        'fail closed (scenario "Совпадение с глобальным значением не '
        'считается перекрытием", D1)', () {
      final root = load('/A', global: user(servers: [stdioA]));
      final folder = load(
        '/B',
        global: user(servers: [stdioB]),
        local: {
          'mcp': {
            'servers': [stdioB],
          },
        },
      );

      final result = defer(root, folder);

      expect((serverOf(result, 'x') as McpStdioServerConfig).command, 'run-a');
      expect(keysOf(result), ['mcp.servers[x]']);
    });
  });

  group('permissions (R0-1, a1, D4)', () {
    final execAllow = {
      'tools': {'exec': 'allow'},
    };

    test('a folder without project layers gets the section of the base '
        '(scenario "Глобальные права после старта в папке без проектных '
        'слоёв")', () {
      final root = load('/A', global: user());
      final folder = load('/B', global: user(permissions: execAllow));

      final result = defer(root, folder);

      expect(result, isA<FolderSessionAccepted>());
      expect(configOf(result).permissions.rules.toolPolicies, isEmpty);
      expect(keysOf(result), ['permissions.tools.exec']);
    });

    test('a folder with project layers is refused (scenario "Глобальные '
        'права после старта в папке с проектными слоями")', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(permissions: execAllow),
        project: {
          'budget': {'max_steps': 7},
        },
      );

      final result = defer(root, folder);

      expect(result, isA<FolderSessionRefused>());
      final problem = problemOf(result);
      expect(problem.kind, ConfigIssueKind.semantic);
      expect(problem.key, 'permissions');
      expect(problem.source, 'config reload');
      expect(
        problem.message,
        'the global permissions changed after the agent started; restart '
        'the agent to open sessions in this folder',
      );
    });
  });

  group('the base and the pair of snapshots (D1, D2, D9)', () {
    test('a root with project layers: the base is its snapshot without the '
        'project, so the root project does not leak into the folder', () {
      final root = load(
        '/A',
        global: user(),
        local: {
          'mcp': {
            'servers': [stdioA],
          },
        },
      );
      final folder = load(
        '/B',
        global: user(openrouterGroup: openrouter(env: 'K2')),
      );

      final result = defer(root, folder);

      expect(configOf(result).mcpServers, isEmpty);
      expect(
        (providerOf(result, 'openrouter').key! as EnvKeyRef).variable,
        'K1',
      );
      expect(keysOf(result), ['providers.openrouter']);
    });

    test('a base without withoutProjectValues defers the whole difference '
        '(D9, fail closed)', () {
      final root = load(
        '/A',
        global: user(),
        local: {
          'agent': {'effort': 'low'},
        },
      );
      final applied = CoreConfig(
        defaultModel: root.config!.defaultModel,
        providers: root.config!.providers,
        projectRoot: '/A',
        withoutProject: root.config!.withoutProject,
      );
      final folder = load('/B', global: user());

      final result = deferForFolderSession(
        applied: applied,
        appliedValues: root.values,
        folder: folder,
      );

      expect(keysOf(result), contains('providers.openrouter'));
    });

    test('no global edit: nothing is substituted, the config of the folder '
        'is returned as is', () {
      final root = load('/A', global: user());
      final folder = load('/B', global: user());

      final result = defer(root, folder);

      expect(keysOf(result), isEmpty);
      expect(result, isA<FolderSessionAccepted>());
      expect(identical(configOf(result), folder.config), isTrue);
    });
  });

  group('no leaks', () {
    test('the keys and the problem carry no values, addresses or variable '
        'names, and the keys are sorted', () {
      final root = load('/A', global: user());
      final changed = user(
        openrouterGroup: openrouter(
          env: 'K2',
          baseUrl: 'https://$marker.example/v1',
        ),
        providers: {
          'zeta': {
            'kind': 'openai-compatible',
            'base_url': 'https://zeta.test/v1',
            'api_key_secret': 'codelab/zeta',
            'models': {'m': <String, Object?>{}},
          },
        },
        servers: [stdioB],
        permissions: {
          'tools': {'exec': 'allow'},
        },
      );
      final allowed = defer(root, load('/B', global: changed));
      final refused = defer(
        root,
        load(
          '/B',
          global: changed,
          project: {
            'budget': {'max_steps': 7},
          },
        ),
      );

      expect(keysOf(allowed), [...keysOf(allowed)]..sort());
      for (final text in [
        keysOf(allowed).join(' '),
        problemOf(refused).toString(),
        problemOf(refused).message,
      ]) {
        expect(text, isNot(contains(marker)));
        expect(text, isNot(contains('https://')));
        expect(text, isNot(contains('K1')));
        expect(text, isNot(contains('K2')));
      }
    });
  });

  // Ревью change `defer-restart-keys-in-folder-sessions`.
  group('a key supplied by the project layer (D23 (a), R0-4, D3)', () {
    Map<String, Object?> pLocal({String? baseUrl}) => {
      'providers': {
        'p': {'api_key_secret': 'codelab/p', 'base_url': ?baseUrl},
      },
    };

    test('the global address changed, the key comes from the project: the '
        'group of the base, the project secret does not go to the new '
        'address', () {
      final root = load('/A', global: user());
      final changed = user(providers: {'p': plain('evil-$marker')});
      final folder = load('/B', global: changed, local: pLocal());

      final result = defer(root, folder);

      final provider = providerOf(result, 'p');
      expect(provider.config.baseUrl, Uri.parse('https://p.test/v1'));
      expect(provider.key, isNull, reason: 'the key of the project is dropped');
      expect(keysOf(result), ['providers.p']);
      expect(keysOf(result).join(), isNot(contains(marker)));
    });

    test('the project sets its own address together with the key: its group '
        'is kept', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(providers: {'p': plain('moved')}),
        local: pLocal(baseUrl: 'https://mine.test/v1'),
      );

      final result = defer(root, folder);

      final provider = providerOf(result, 'p');
      expect(provider.config.baseUrl, Uri.parse('https://mine.test/v1'));
      expect((provider.key! as SecretKeyRef).name, 'codelab/p');
      expect(keysOf(result), isEmpty);
    });

    test('the global address did not change: the key of the project works '
        'at once', () {
      final root = load('/A', global: user());
      final folder = load('/B', global: user(), local: pLocal());

      final result = defer(root, folder);

      expect((providerOf(result, 'p').key! as SecretKeyRef).name, 'codelab/p');
      expect(keysOf(result), isEmpty);
    });
  });

  // Повторное ревью: способ задать ключ проекта x изменённый глобальный лист
  // группы. Секрет проекта не должен попасть в итоговую группу (R0-4, D3).
  group('a project key x a changed global leaf of the group (matrix)', () {
    // Способы задать ключ в проектном слое для глобального провайдера `p`.
    final keyWays = <String, Map<String, Object?>>{
      'api_key_env': {'api_key_env': 'K1'},
      'literal api_key': {'api_key': marker},
      'headers with a secret reference': {
        'headers': {'Authorization': r'Bearer ${secret:codelab/p/auth}'},
      },
      'secret-named header': {
        'headers': {'X-Api-Key': marker},
      },
    };
    // Изменённый после старта глобальный лист группы.
    //
    // Поля адреса (`base_url`, `kind`) наследуются проектом, поэтому ключ
    // проекта пошёл бы на новый адрес: группа берётся из базы. Поля
    // аутентификации (`auth_header`, `headers`) правило группы D23 берёт
    // только из слоя с ключом, то есть проект их отбрасывает: изменённый лист
    // до группы не доходит, группа проекта идёт на прежний адрес (безопасно,
    // но не подстановка из базы и без ключа в `restartKeys`).
    final leaves = <String, (Map<String, Object?>, bool)>{
      'base_url': ({'base_url': 'https://evil.test/v1'}, true),
      'kind': ({'kind': 'anthropic'}, true),
      'auth_header': ({'auth_header': 'X-Auth'}, false),
      'headers.X-Org': (
        {
          'headers': {'X-Org': 'a'},
        },
        false,
      ),
    };

    for (final MapEntry(key: keyName, value: keyWay) in keyWays.entries) {
      for (final MapEntry(key: leafName, value: (leaf, fromBase))
          in leaves.entries) {
        test('$keyName, global $leafName changed: no project secret meets '
            'the changed leaf', () {
          final root = load('/A', global: user());
          final folder = load(
            '/B',
            global: user(
              providers: {
                'p': {...plain('p'), ...leaf},
              },
            ),
            local: {
              'providers': {'p': keyWay},
            },
          );

          final result = defer(root, folder);

          final provider = providerOf(result, 'p');
          // Ни при каком способе задать ключ изменённый лист до группы с
          // ключом проекта не доходит.
          expect(provider.config.baseUrl, Uri.parse('https://p.test/v1'));
          expect(provider.config.api, ProviderApi.openaiChat);
          expect(provider.config.authHeader, isNot('X-Auth'));
          expect(provider.config.headers.keys, isNot(contains('X-Org')));
          expect(keysOf(result).join(), isNot(contains(marker)));
          if (fromBase) {
            expect(provider.config.authHeader, 'Authorization');
            expect(provider.config.headers, isEmpty);
            expect(provider.config.apiKey, isNull);
            expect(provider.key, isNull);
            expect(provider.headerTemplates, isEmpty);
            expect(keysOf(result), contains('providers.p'));
          }
        });
      }
    }

    test('the project overrides only a part of the changed leaves: the '
        'group of the base', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(
          providers: {
            'p': {...plain('evil'), 'kind': 'anthropic'},
          },
        ),
        // `kind` перекрыт проектом, унаследованный `base_url` остался новым
        // глобальным: ключ проекта не должен уйти на него.
        local: {
          'providers': {
            'p': {'kind': 'openai-compatible', 'api_key_secret': 'codelab/p'},
          },
        },
      );

      final result = defer(root, folder);

      final provider = providerOf(result, 'p');
      expect(provider.config.baseUrl, Uri.parse('https://p.test/v1'));
      expect(provider.config.api, ProviderApi.openaiChat);
      expect(provider.key, isNull);
      expect(keysOf(result), contains('providers.p'));
    });
  });

  group('the pair of snapshots of the folder (D9)', () {
    test('a folder with withoutProject but without withoutProjectValues: '
        'nothing is overlapped, the group comes from the base', () {
      final root = load('/A', global: user());
      final loaded = load(
        '/B',
        global: user(openrouterGroup: openrouter(env: 'K2')),
        local: {
          'budget': {'max_steps': 7},
        },
      );
      final config = loaded.config!;
      final stripped = ConfigLoadResult(
        config: CoreConfig(
          defaultModel: config.defaultModel,
          providers: config.providers,
          providerProblems: config.providerProblems,
          projectRoot: '/B',
          withoutProject: config.withoutProject,
        ),
        values: loaded.values,
      );

      final result = defer(root, stripped);

      expect(keysOf(result), contains('providers.openrouter'));
      expect(
        (providerOf(result, 'openrouter').key! as EnvKeyRef).variable,
        'K1',
      );
    });
  });

  group('default model and new provider (D3, D5)', () {
    Map<String, Object?> newKeyed(String id) => {
      'kind': 'openai-compatible',
      'base_url': 'https://$id.test/v1',
      'api_key_secret': 'codelab/$id',
      'models': {'m': <String, Object?>{}},
    };

    test('the folder sets its own agent.default_model: the model of the '
        'project wins and agent.default_model is not a restart key', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(model: 'n/m', providers: {'n': newKeyed('n')}),
        local: {
          'agent': {'default_model': 'p/m'},
        },
      );

      final result = defer(root, folder);

      expect(configOf(result).defaultModel.provider, 'p');
      expect(configOf(result).validateSnapshot(), isEmpty);
      expect(keysOf(result), ['providers.n']);
    });

    test('the project overrides every leaf of the group of a new global '
        'provider: its group is kept', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(providers: {'n': newKeyed('n')}),
        local: {
          'providers': {
            'n': {
              'kind': 'anthropic',
              'base_url': 'https://mine.test',
              'api_key_secret': 'codelab/mine',
              'models': {'m': <String, Object?>{}},
            },
          },
        },
      );

      final result = defer(root, folder);

      final provider = providerOf(result, 'n');
      expect(provider.config.baseUrl, Uri.parse('https://mine.test'));
      expect(keysOf(result), isNot(contains('providers.n')));
    });

    test('the project repeats the kind of a new global provider: the leaf '
        'is equal, so it is not an override and the provider is excluded '
        '(D1, fail closed)', () {
      final root = load('/A', global: user());
      final folder = load(
        '/B',
        global: user(providers: {'n': newKeyed('n')}),
        local: {
          'providers': {
            'n': {
              'kind': 'openai-compatible',
              'base_url': 'https://mine.test/v1',
              'api_key_secret': 'codelab/mine',
              'models': {'m': <String, Object?>{}},
            },
          },
        },
      );

      final result = defer(root, folder);

      expect(configOf(result).providers.map((p) => p.config.name), [
        'openrouter',
        'p',
      ]);
      expect(keysOf(result), ['providers.n']);
    });

    test('the root has a project agent.default_model: a deferred reference '
        'to a new global provider does not fall back to the model of the '
        'root project', () {
      Map<String, Object?> noModel() => norm({
        'providers': {'p': plain('p')},
      });
      final root = load(
        '/A',
        global: noModel(),
        local: {
          'providers': {'rp': plain('rp')},
          'agent': {'default_model': 'rp/m'},
        },
      );
      final folder = load(
        '/B',
        global: {
          ...noModel(),
          'providers': {'p': plain('p'), 'n': newKeyed('n')},
          'agent': {'default_model': 'n/m'},
        },
      );

      final result = defer(root, folder);

      expect(result, isA<FolderSessionAccepted>());
      expect(configOf(result).validateSnapshot(), isEmpty);
      expect(configOf(result).defaultModel.provider, isNot('rp'));
    });
  });

  group('permissions are independent of the root and cwd (D4)', () {
    test('the same global rules with paths in /A and /B: no refusal', () {
      final rules = {
        'permissions': {
          'deny': ['read:~/.ssh/**', 'write:/etc/**'],
        },
      };
      final root = load(
        '/A',
        global: user(permissions: rules['permissions']),
        project: {
          'permissions': {
            'deny': ['write:secret/**'],
          },
        },
      );
      final folder = load(
        '/B',
        global: user(permissions: rules['permissions']),
        project: {
          'budget': {'max_steps': 7},
        },
      );

      final result = defer(root, folder);

      expect(result, isA<FolderSessionAccepted>());
      expect(keysOf(result), isEmpty);
    });
  });

  test('every field of DeferredConfigParts has an overlap rule (D5)', () {
    // Новое структурированное отложенное поле без правила перекрытия
    // оставило бы дыру R0 в сессиях других папок: поля читаются из исходника.
    final source = File('lib/src/config/core_config.dart').readAsStringSync();
    final start = source.indexOf('final class DeferredConfigParts');
    final body = source.substring(start, source.indexOf('\n}\n', start));
    final fields = RegExp(
      r'^  final [\w<>?, ]+ (\w+);',
      multiLine: true,
    ).allMatches(body).map((m) => m.group(1)!).toSet();

    expect(fields, isNotEmpty);
    expect(folderSessionOverlapRules.keys.toSet(), fields);
  });
}
