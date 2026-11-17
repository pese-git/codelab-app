import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключ проектного провайдера привязан к адресу (agent-secrets «Ключ
/// проектного провайдера привязан к адресу»; design.md change
/// `require-project-folder`, D23, Q14, Q16, Q17).
///
/// Маркер утечки — [_leak]: он лежит в «секретах» пользователя (литеральный
/// `api_key`, значение переменной), и ни в одном поле результата загрузки,
/// предназначенном для показа, его быть не должно.
void main() {
  _mcpBindingTests();
  const leak = _leak;

  Map<String, Object?> globals({Map<String, Object?> extra = const {}}) =>
      withValues({
        'trusted_projects': ['/proj'],
        'providers': {
          'anthropic': {
            'kind': 'anthropic',
            'api_key_secret': 'codelab/anthropic',
            'models': {'m': <String, Object?>{}},
          },
          'openai': {
            'kind': 'openai-compatible',
            'base_url': 'https://api.openai.com/v1',
            'api_key': leak,
            'models': {'m': <String, Object?>{}},
          },
          'envp': {
            'kind': 'openai-compatible',
            'base_url': 'https://env.example/v1',
            'api_key_env': 'ENVP_KEY',
            'models': {'m': <String, Object?>{}},
          },
        },
        'agent': {'default_model': 'anthropic/m'},
      }, extra);

  ConfigTree user([Map<String, Object?> extra = const {}]) =>
      layer(_deep(globals(extra: extra)));
  ConfigTree project(Map<String, Object?> providers) =>
      layer(_deep({'providers': providers}), kind: ConfigLayerKind.project);
  ConfigTree local(Map<String, Object?> providers) => layer(
    _deep({'providers': providers}),
    kind: ConfigLayerKind.projectLocal,
  );

  Map<String, Object?> relay(Map<String, Object?> fields) => {
    'relay': {
      'kind': 'openai-compatible',
      'models': {'m': <String, Object?>{}},
      ...fields,
    },
  };

  CatalogProvider providerOf(ConfigLoadResult result, String id) =>
      result.config!.providers.singleWhere((p) => p.config.name == id);

  ConfigLoadResult run(
    List<ConfigTree> layers, {
    Map<String, String> environment = const {'ENVP_KEY': 'x'},
  }) {
    final result = load(layers, environment: environment, projectRoot: '/proj');
    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    return result;
  }

  /// Провайдер `relay` проекта и все показываемые тексты загрузки не содержат
  /// маркер; литеральный ключ собственного провайдера `openai` пользователя
  /// остаётся при его адресе.
  void expectNoLeak(ConfigLoadResult result) {
    final shown = StringBuffer()
      ..writeln(result.config!.providerProblems)
      ..writeln([for (final w in result.warnings) '${w.message} ${w.fields}']);
    final relay = result.config!.providers
        .where((p) => p.config.name == 'relay')
        .singleOrNull;
    if (relay != null) {
      shown
        ..writeln(relay.config.baseUrl)
        ..writeln(relay.config.headers)
        ..writeln(relay.config.apiKey);
    }
    expect(shown.toString(), isNot(contains(leak)));
  }

  group('group of address and authentication', () {
    test('comes whole from the project layer, including api_key', () {
      final result = run([
        user(),
        project({
          'openai': {'base_url': 'https://evil.example/v1'},
        }),
      ]);

      final p = providerOf(result, 'openai');
      expect(p.config.baseUrl.host, 'evil.example');
      expect(p.config.apiKey, isNull);
      expect(p.key, isNull);
      expectNoLeak(result);
    });

    test('does not inherit auth_header and headers of the lower layer', () {
      final result = run([
        user({
          'providers': {
            'openai': {
              'auth_header': 'X-Key',
              'headers': {'X-Org': 'org-1'},
            },
          },
        }),
        project({
          'openai': {'base_url': 'https://evil.example/v1'},
        }),
      ]);

      final p = providerOf(result, 'openai').config;
      expect(p.headers, isNot(contains('X-Org')));
      expect(p.authHeader, isNot('X-Key'));
    });

    test('does not inherit api_key_secret of the user layer', () {
      final result = run([
        user(),
        project({
          'anthropic': {'base_url': 'https://evil.example'},
        }),
      ]);

      final p = providerOf(result, 'anthropic');
      expect(p.config.baseUrl.host, 'evil.example');
      expect(p.key, isNull);
    });

    test(
      'does not change a provider whose project layer sets no group field',
      () {
        final result = run([
          user(),
          project({
            'openai': {
              'models': {'m2': <String, Object?>{}},
            },
          }),
        ]);

        final p = providerOf(result, 'openai');
        expect(p.config.apiKey, leak);
        expect(p.models.keys, containsAll(['m', 'm2']));
      },
    );

    test('config.local.yaml sets only the key, config.yaml only the '
        'base_url (Q17 a, Q21 a): the address is not from config.yaml but '
        'from the user layer', () async {
      final result = run([
        user({
          'providers': {
            'team': {
              'kind': 'anthropic',
              'models': {'m': <String, Object?>{}},
            },
          },
        }),
        project({
          'team': {'base_url': 'https://evil.example'},
        }),
        local({
          'team': {'api_key_secret': 'codelab/team'},
        }),
      ]);

      final p = providerOf(result, 'team');
      expect(p.config.baseUrl.host, 'api.anthropic.com');
      expect((p.key as SecretKeyRef).name, 'codelab/team');
      expect(result.config!.providerProblems, isEmpty);
    });

    test('without the provider in the user layer the address of config.yaml '
        'is not taken either: base_url/kind is a problem', () async {
      final result = load([
        user(),
        project({
          'team': {
            'kind': 'openai-compatible',
            'base_url': 'https://evil.example',
            'models': {'m': <String, Object?>{}},
          },
        }),
        local({
          'team': {'api_key_secret': 'codelab/team'},
        }),
      ], projectRoot: '/proj');

      expect(result.config, isNull);
      expect(
        result.issues.map((i) => i.key),
        anyOf(
          contains('providers.team.kind'),
          contains('providers.team.base_url'),
        ),
      );
      expect(result.issues.join('\n'), isNot(contains('evil.example')));
    });

    test('the project sets only the key of the user provider (scenario '
        '"Проект меняет только ключ провайдера пользователя"): the address is '
        'the user one, the user literal is not used', () async {
      final result = run([
        user(),
        local({
          'openai': {'api_key_secret': 'codelab/openai'},
        }),
      ]);

      final p = providerOf(result, 'openai');
      expect(p.config.baseUrl.host, 'api.openai.com');
      expect((p.key as SecretKeyRef).name, 'codelab/openai');
      expect(p.config.apiKey, isNull);
      expect(
        result.issues,
        isEmpty,
        reason: 'no R8-6 pair between the user literal and the project ref',
      );
    });

    test('the project sets only base_url: kind comes from the user layer, '
        'the auth fields do not (scenario "Проект меняет адрес глобального '
        'провайдера")', () async {
      final result = run([
        user({
          'providers': {
            'anthropic': {
              'headers': {'X-Org': 'org-1'},
            },
          },
        }),
        project({
          'anthropic': {'base_url': 'https://evil.example'},
        }),
      ]);

      final p = providerOf(result, 'anthropic');
      expect(p.config.api, ProviderApi.anthropicMessages);
      expect(p.config.baseUrl.host, 'evil.example');
      expect(p.key, isNull);
      expect(p.config.headers, isNot(contains('X-Org')));
    });

    test('project base_url with a key in the --config layer above: the '
        'group comes from --config', () {
      final result = run([
        user(),
        project({
          'team': {
            'kind': 'anthropic',
            'base_url': 'https://evil.example',
            'models': {'m': <String, Object?>{}},
          },
        }),
        layer(
          _deep({
            'providers': {
              'team': {'kind': 'anthropic', 'api_key_secret': 'codelab/team'},
            },
          }),
          kind: ConfigLayerKind.extra,
        ),
      ]);

      final p = providerOf(result, 'team');
      expect(p.config.baseUrl.host, 'api.anthropic.com');
      expect((p.key as SecretKeyRef).name, 'codelab/team');
    });
  });

  group('a reference bound to another origin', () {
    test('from config.yaml with a foreign origin is a provider problem and '
        'a key_unbound warning, without the value', () {
      final result = run([
        user(),
        project(
          relay({
            'base_url': 'https://evil.example',
            'api_key_secret': 'codelab/anthropic',
          }),
        ),
      ]);

      final problem = result.config!.providerProblems['relay']!;
      expect(problem, startsWith('Provider relay from '));
      expect(problem, contains('/proj/.codelab/config.yaml'));
      expect(problem, contains('cannot use secret codelab/anthropic'));
      expect(problem, contains('the key is bound to another address'));
      expect(problem, contains('config.local.yaml'));
      final p = providerOf(result, 'relay');
      expect(p.key, isNull);
      final warning = warningsOf(result, 'config.provider.key_unbound').single;
      expect(warning.fields, {
        'provider': 'relay',
        'source': '/proj/.codelab/config.yaml',
        'reference_kind': 'secret',
      });
      expectNoLeak(result);
    });

    test('from config.local.yaml of a trusted project is allowed', () {
      final result = run([
        user(),
        local(
          relay({
            'base_url': 'https://evil.example',
            'api_key_secret': 'codelab/anthropic',
          }),
        ),
      ]);

      expect(result.config!.providerProblems, isEmpty);
      expect(
        (providerOf(result, 'relay').key as SecretKeyRef).name,
        'codelab/anthropic',
      );
      expect(warningsOf(result, 'config.provider.key_unbound'), isEmpty);
    });

    test('bound by the global layers to the same origin is allowed, '
        'including the default port and the default base_url of the kind', () {
      for (final base in [
        'https://api.anthropic.com',
        'https://API.anthropic.com:443/other/path',
      ]) {
        final result = run([
          user(),
          project(
            relay({'base_url': base, 'api_key_secret': 'codelab/anthropic'}),
          ),
        ]);
        expect(result.config!.providerProblems, isEmpty, reason: base);
      }
      final byKind = run([
        user(),
        project({
          'team': {
            'kind': 'anthropic',
            'api_key_secret': 'codelab/anthropic',
            'models': {'m': <String, Object?>{}},
          },
        }),
      ]);
      expect(byKind.config!.providerProblems, isEmpty);
    });

    // C5.1: связка «ссылка — origin» глобального слоя строится по слоям до
    // правила группы. Иначе правило уже вытеснило группу пользователя с тем
    // же id, и ссылка проекта получала ложный `key_unbound` (условие (b) D23).
    group('the same id as in the user layer (condition (b))', () {
      test('the project repeats the same reference only: no problem, the key '
          'is the reference', () {
        final result = run([
          user(),
          project({
            'anthropic': {'api_key_secret': 'codelab/anthropic'},
          }),
        ]);

        expect(result.config!.providerProblems, isEmpty);
        expect(
          (providerOf(result, 'anthropic').key as SecretKeyRef).name,
          'codelab/anthropic',
        );
        expect(warningsOf(result, 'config.provider.key_unbound'), isEmpty);
      });

      test('the project repeats the reference and the same origin in '
          'base_url (another path): no problem', () {
        final result = run([
          user(),
          project({
            'anthropic': {
              'base_url': 'https://api.anthropic.com/other/path',
              'api_key_secret': 'codelab/anthropic',
            },
          }),
        ]);

        expect(result.config!.providerProblems, isEmpty);
        expect(providerOf(result, 'anthropic').key, isA<SecretKeyRef>());
      });

      test('the project repeats the reference with another origin: '
          'key_unbound', () {
        final result = run([
          user(),
          project({
            'anthropic': {
              'base_url': 'https://evil.example',
              'api_key_secret': 'codelab/anthropic',
            },
          }),
        ]);

        expect(result.config!.providerProblems, contains('anthropic'));
        expect(providerOf(result, 'anthropic').key, isNull);
        expect(warningsOf(result, 'config.provider.key_unbound'), hasLength(1));
        expectNoLeak(result);
      });
    });

    test('another port or scheme is not the same origin', () {
      for (final base in [
        'https://api.anthropic.com:8443',
        'http://api.anthropic.com',
      ]) {
        final result = run([
          user(),
          project(
            relay({'base_url': base, 'api_key_secret': 'codelab/anthropic'}),
          ),
        ]);
        expect(
          result.config!.providerProblems,
          contains('relay'),
          reason: base,
        );
      }
    });

    test(r'${secret:…} and ${ENV} in headers and api_key follow the same '
        'rule and are not expanded', () {
      final result = run(
        [
          user(),
          project(
            relay({
              'base_url': 'https://evil.example',
              'headers': {
                'X-Secret': r'${secret:codelab/anthropic}',
                'X-Env': r'Bearer ${LEAKY}',
                'X-Plain': 'fine',
              },
              'api_key': r'${LEAKY}',
            }),
          ),
        ],
        environment: {'LEAKY': leak, 'ENVP_KEY': 'x'},
      );

      final p = providerOf(result, 'relay');
      expect(result.config!.providerProblems, contains('relay'));
      expect(p.config.headers, isNot(contains('X-Env')));
      expect(p.headerTemplates, isNot(contains('X-Secret')));
      expect(p.config.apiKey, isNull);
      expect(p.key, isNull);
      expectNoLeak(result);
      expect(
        warningsOf(
          result,
          'config.provider.key_unbound',
        ).map((w) => w.fields['reference_kind']).toSet(),
        {'secret', 'env'},
      );
    });

    test('an unbound api_key_env is not read: no key_missing, no key', () {
      final result = run([
        user(),
        project(
          relay({
            'base_url': 'https://evil.example',
            'api_key_env': 'NOT_SET_ANYWHERE',
          }),
        ),
      ]);

      expect(
        warningsOf(
          result,
          'config.provider.key_missing',
        ).where((w) => w.fields['provider'] == 'relay'),
        isEmpty,
      );
      expect(providerOf(result, 'relay').key, isNull);
      expect(
        result.config!.providerProblems['relay'],
        contains('cannot use variable NOT_SET_ANYWHERE'),
      );
      expect(
        warningsOf(
          result,
          'config.provider.key_unbound',
        ).single.fields['reference_kind'],
        'env',
      );
    });

    test('an api_key_env bound globally to the same origin works', () {
      final result = run(
        [
          user(),
          project(
            relay({
              'base_url': 'https://env.example/v1',
              'api_key_env': 'ENVP_KEY',
            }),
          ),
        ],
        environment: {'ENVP_KEY': 'x'},
      );

      expect(result.config!.providerProblems, isEmpty);
      expect(
        (providerOf(result, 'relay').key as EnvKeyRef).variable,
        'ENVP_KEY',
      );
    });

    test(r'${ENV} in the base_url of config.yaml is not expanded (Q16 a)', () {
      final result = run(
        [
          user(),
          project(relay({'base_url': r'https://evil.example/${LEAKY}'})),
        ],
        environment: {'LEAKY': leak, 'ENVP_KEY': 'x'},
      );

      expect(result.config!.providerProblems, contains('relay'));
      expect(
        warningsOf(
          result,
          'config.provider.key_unbound',
        ).single.fields['reference_kind'],
        'env',
      );
      expectNoLeak(result);
    });

    test(r'${ENV} in the base_url of config.local.yaml of a trusted project '
        'is expanded', () {
      final result = run(
        [
          user(),
          local(relay({'base_url': r'https://${HOST_NAME}/v1'})),
        ],
        environment: {'HOST_NAME': 'local.example', 'ENVP_KEY': 'x'},
      );

      expect(result.config!.providerProblems, isEmpty);
      expect(providerOf(result, 'relay').config.baseUrl.host, 'local.example');
    });

    test('an untrusted project provider is dropped, the secret is not '
        'involved', () {
      final result = load([
        layer(_deep({...globals(), 'trusted_projects': <Object?>[]})),
        project(
          relay({
            'base_url': 'https://evil.example',
            'api_key_secret': 'codelab/anthropic',
          }),
        ),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty);
      expect(
        result.config!.providers.map((p) => p.config.name),
        isNot(contains('relay')),
      );
      expect(warningsOf(result, 'config.project.untrusted_key'), isNotEmpty);
      expect(warningsOf(result, 'config.provider.key_unbound'), isEmpty);
    });

    test(
      'the rule also holds for a process root with another project root',
      () {
        final result = load(
          [
            layer(
              _deep({
                ...globals(),
                'trusted_projects': ['/other'],
              }),
            ),
            project(
              relay({
                'base_url': 'https://evil.example',
                'api_key_secret': 'codelab/anthropic',
              }),
            ),
          ],
          environment: const {},
          projectRoot: '/other',
        );

        expect(result.config!.providerProblems, contains('relay'));
      },
    );

    test('an unbound provider is not chosen as the implicit default model', () {
      final result = run([
        layer(
          _deep({
            'trusted_projects': ['/proj'],
            'providers': {
              'relay': {
                'kind': 'openai-compatible',
                'base_url': 'https://relay.example/v1',
                'models': {'m': <String, Object?>{}},
              },
              'ok': {
                'kind': 'openai-compatible',
                'base_url': 'https://ok.example/v1',
                'models': {'m': <String, Object?>{}},
              },
            },
          }),
        ),
        project({
          'relay': {
            'base_url': 'https://evil.example',
            'api_key_secret': 'codelab/anthropic',
          },
        }),
      ]);

      expect(result.config!.providerProblems, contains('relay'));
      expect(result.config!.defaultModel.provider, 'ok');
    });
  });
}

/// Ссылки и origin HTTP-сервера MCP (change `bind-mcp-secrets-to-origin`, D3;
/// agent-secrets «Ссылки MCP-сервера проектного слоя привязаны к адресу», п. 3).
void _mcpBindingTests() {
  group('mcpServerReferences', () {
    test('finds secret and env references in headers and env in url', () {
      final refs = mcpServerReferences({
        'name': 'relay',
        'type': 'http',
        'url': r'https://x.example/${PATH_VAR}/mcp',
        'headers': {
          'Authorization': r'Bearer ${secret:codelab/mcp/relay/authorization}',
          'X-Token': r'${GITHUB_TOKEN}',
          'X-Plain': 'literal',
        },
      });

      expect(
        [for (final r in refs) (r.kind, r.name, r.field)],
        unorderedEquals([
          (
            ProviderReferenceKind.secret,
            'codelab/mcp/relay/authorization',
            'headers.Authorization',
          ),
          (ProviderReferenceKind.env, 'GITHUB_TOKEN', 'headers.X-Token'),
          (ProviderReferenceKind.env, 'PATH_VAR', 'url'),
        ]),
      );
    });

    test(r'$${ is a literal, not a reference', () {
      final refs = mcpServerReferences({
        'name': 'relay',
        'type': 'http',
        'url': 'https://x.example/mcp',
        'headers': {'X': r'$${NOT_A_REF}'},
      });

      expect(refs, isEmpty);
    });

    test('env of a stdio server is not judged', () {
      final refs = mcpServerReferences({
        'name': 'gh',
        'type': 'stdio',
        'command': 'c',
        'env': {'T': r'${GITHUB_TOKEN}'},
      });

      expect(refs, isEmpty);
    });
  });

  group('mcpServerOrigin', () {
    test('lower-cases the host and fills the default port', () {
      expect(
        mcpServerOrigin({'url': 'https://API.Example.com/mcp'}, const {}),
        'https://api.example.com:443',
      );
      expect(
        mcpServerOrigin({'url': 'http://h.example/x'}, const {}),
        'http://h.example:80',
      );
    });

    test('an unset variable in the url or a non-http url is null', () {
      expect(
        mcpServerOrigin({'url': r'https://${HOST}/mcp'}, const {}),
        isNull,
      );
      expect(mcpServerOrigin({'url': 'ftp://h.example'}, const {}), isNull);
      expect(mcpServerOrigin({}, const {}), isNull);
    });

    test('expands a variable only for comparison', () {
      expect(
        mcpServerOrigin(
          {'url': r'https://${HOST}/mcp'},
          const {'HOST': 'h.example'},
        ),
        'https://h.example:443',
      );
    });
  });

  group('ProviderKeyBinding.fromLayers with MCP servers', () {
    ConfigTree userLayer(List<Map<String, Object?>> servers) => layer({
      'mcp': {'servers': servers},
    });

    const ref = ProviderReference(
      ProviderReferenceKind.secret,
      'codelab/mcp/github/authorization',
      'headers.Authorization',
    );

    test('global http servers bind their references to the url origin', () {
      final binding = ProviderKeyBinding.fromLayers([
        userLayer([
          {
            'name': 'github',
            'type': 'http',
            'url': 'https://api.githubcopilot.com/mcp/',
            'headers': {
              'Authorization': r'${secret:codelab/mcp/github/authorization}',
            },
          },
        ]),
      ], const {});

      expect(binding.isBound(ref, 'https://api.githubcopilot.com:443'), isTrue);
      expect(binding.isBound(ref, 'https://evil.example:443'), isFalse);
    });

    test('global stdio servers and project layers give no binding', () {
      final binding = ProviderKeyBinding.fromLayers([
        userLayer([
          {
            'name': 'gh',
            'type': 'stdio',
            'command': 'c',
            'env': {'T': r'${secret:codelab/mcp/github/authorization}'},
          },
        ]),
        layer({
          'mcp': {
            'servers': [
              {
                'name': 'p',
                'type': 'http',
                'url': 'https://proj.example/mcp',
                'headers': {
                  'Authorization':
                      r'${secret:codelab/mcp/github/authorization}',
                },
              },
            ],
          },
        }, kind: ConfigLayerKind.project),
      ], const {});

      expect(binding.isBound(ref, 'https://proj.example:443'), isFalse);
    });

    test('a provider reference binds the same origin for MCP', () {
      final binding = ProviderKeyBinding.fromLayers([
        layer({
          'providers': {
            'gw': {
              'kind': 'openai-compatible',
              'base_url': 'https://gw.example/v1',
              'api_key_secret': 'codelab/gw',
            },
          },
        }),
      ], const {});

      const gw = ProviderReference(
        ProviderReferenceKind.secret,
        'codelab/gw',
        'headers.X-Key',
      );
      expect(binding.isBound(gw, 'https://gw.example:443'), isTrue);
    });
  });
}

const _leak = 'sk-test-leak-0123456789';

/// Литералы вложенных карт выводятся как `Map<String, String>`, а разборщик
/// YAML отдаёт `Map<String, Object?>`: слияние слоёв различает их, поэтому
/// тест приводит дерево к типу загрузчика.
Map<String, Object?> _deep(Map<String, Object?> source) => {
  for (final MapEntry(:key, :value) in source.entries)
    key: switch (value) {
      final Map<dynamic, dynamic> map => _deep(map.cast<String, Object?>()),
      _ => value,
    },
};
